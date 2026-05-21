import cors from "@fastify/cors";
import Fastify, { type FastifyInstance } from "fastify";
import { basename, dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { nanoid } from "nanoid";
import {
  createEvent,
  isNotificationTrigger,
  parseEvent,
  type RunSummary,
  type SkyBridgeEvent
} from "@skybridge-agent-hub/event-schema";
import { send as sendNtfy, type NotificationMessage } from "@skybridge-agent-hub/notification-ntfy";
import { MemoryStore, SqliteStore, type EventStore, type StoredEvent, type StoredNotification } from "./store.js";

export type { StoredEvent, StoredNotification } from "./store.js";

interface CreateServerOptions {
  dbFile?: string | false;
  dataFile?: string | false;
  jsonMigrationFile?: string | false;
  logger?: boolean;
}

function summarizeRuns(events: StoredEvent[]): RunSummary[] {
  const grouped = new Map<string, StoredEvent[]>();
  for (const event of events) {
    const runId = event.correlation?.run_id ?? event.correlation?.session_id ?? "unknown";
    const existing = grouped.get(runId) ?? [];
    existing.push(event);
    grouped.set(runId, existing);
  }

  return [...grouped.entries()].map(([run_id, runEvents]) => {
    const first = runEvents[0]!;
    const last = runEvents.at(-1)!;
    const failed = runEvents.some((event) => event.type === "run.failed" || event.severity === "error" || event.severity === "critical");
    const completed = runEvents.some((event) => event.type === "run.completed" || event.type === "session.completed");
    const status: RunSummary["status"] = failed ? "failed" : completed ? "completed" : run_id === "unknown" ? "unknown" : "running";
    return {
      run_id,
      session_id: last.correlation?.session_id,
      source_platform: last.source.platform,
      source_adapter: last.source.adapter,
      status,
      event_count: runEvents.length,
      first_seen_at: first.receivedAt,
      last_seen_at: last.receivedAt,
      last_event_type: last.type
    };
  }).sort((a, b) => b.last_seen_at.localeCompare(a.last_seen_at));
}

function notificationForEvent(event: StoredEvent): NotificationMessage {
  return {
    title: `SkyBridge ${event.type}`,
    body: [
      `Source: ${event.source.platform}/${event.source.adapter}`,
      `Run: ${event.correlation?.run_id ?? event.correlation?.session_id ?? "unknown"}`,
      `Severity: ${event.severity}`
    ].join("\n"),
    priority: event.severity === "critical" || event.type === "approval.requested" ? "high" : "default",
    url: process.env.SKYBRIDGE_PUBLIC_URL
  };
}

export async function createServer(options: CreateServerOptions = {}): Promise<FastifyInstance> {
  const persistence = resolvePersistence(options);
  const store: EventStore = persistence.dbFile ? new SqliteStore({ dbFile: persistence.dbFile, legacyJsonFile: persistence.jsonMigrationFile }) : new MemoryStore();
  const clients = new Set<{ write: (data: string) => void }>();
  const app = Fastify({ logger: options.logger ?? true });

  await store.load();
  await app.register(cors, { origin: true });
  app.addHook("onClose", async () => {
    await store.close();
  });

  const broadcast = (event: StoredEvent) => {
    const payload = `event: skybridge.event\ndata: ${JSON.stringify(event)}\n\n`;
    for (const client of clients) {
      try {
        client.write(payload);
      } catch {
        clients.delete(client);
      }
    }
  };

  const recordNotification = async (message: NotificationMessage, provider: "ntfy" | "placeholder", status: StoredNotification["status"], error?: string) => {
    await store.addNotification({
      id: nanoid(),
      provider,
      status,
      message,
      createdAt: new Date().toISOString(),
      error
    });
  };

  const maybeNotify = async (event: StoredEvent) => {
    if (!isNotificationTrigger(event)) return;
    const message = notificationForEvent(event);
    if (!process.env.NTFY_TOPIC_URL) {
      await recordNotification(message, "placeholder", "skipped", "NTFY_TOPIC_URL is not configured.");
      return;
    }
    try {
      await sendNtfy(message);
      await recordNotification(message, "ntfy", "sent");
    } catch (error) {
      await recordNotification(message, "ntfy", "failed", error instanceof Error ? error.message : String(error));
    }
  };

  app.get("/health", async () => ({
    ok: true,
    service: "skybridge-server",
    persistence: store.kind,
    dbFile: persistence.dbFile,
    jsonMigrationFile: persistence.jsonMigrationFile,
    time: new Date().toISOString()
  }));

  app.post("/v1/events", async (request, reply) => {
    const event = parseEvent(request.body);
    const stored: StoredEvent = {
      ...event,
      id: event.event_id ?? nanoid(),
      event_id: event.event_id ?? undefined,
      receivedAt: new Date().toISOString()
    };
    await store.addEvent(stored);
    broadcast(stored);
    void maybeNotify(stored);
    return reply.code(202).send({ ok: true, id: stored.id });
  });

  app.get("/v1/events", async () => ({
    events: store.listEvents(200)
  }));

  app.get("/v1/runs", async () => ({
    runs: summarizeRuns(store.listEvents())
  }));

  app.get("/v1/notifications", async () => ({
    notifications: store.listNotifications(200)
  }));

  app.post<{ Body: NotificationMessage }>("/v1/notifications/send", async (request, reply) => {
    const message = request.body;
    if (!message?.title || !message?.body) {
      return reply.code(400).send({ ok: false, error: "title and body are required" });
    }
    if (!process.env.NTFY_TOPIC_URL) {
      await recordNotification(message, "placeholder", "skipped", "NTFY_TOPIC_URL is not configured.");
      return reply.code(202).send({ ok: true, provider: "placeholder", skipped: true });
    }
    await sendNtfy(message);
    await recordNotification(message, "ntfy", "sent");
    return reply.code(202).send({ ok: true, provider: "ntfy" });
  });

  app.get("/v1/stream", async (_request, reply) => {
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no"
    });

    const client = { write: (data: string) => reply.raw.write(data) };
    clients.add(client);
    reply.raw.write(`event: connected\ndata: ${JSON.stringify({ ok: true })}\n\n`);
    for (const event of store.listEvents(20)) {
      client.write(`event: skybridge.event\ndata: ${JSON.stringify(event)}\n\n`);
    }

    reply.raw.on("close", () => {
      clients.delete(client);
    });
  });

  app.post("/v1/dev/seed", async (_request, reply) => {
    if (process.env.NODE_ENV === "production") return reply.code(404).send({ ok: false });
    const event = createEvent({
      type: "run.started",
      source: { platform: "skybridge", adapter: "dev-seed" },
      correlation: { run_id: `seed-${Date.now()}` },
      payload: { message: "Seed event" }
    });
    const stored: StoredEvent = { ...event, id: nanoid(), receivedAt: new Date().toISOString() };
    await store.addEvent(stored);
    broadcast(stored);
    return reply.code(202).send({ ok: true, id: stored.id });
  });

  return app;
}

function resolvePersistence(options: CreateServerOptions): { dbFile?: string; jsonMigrationFile?: string } {
  if (options.dbFile === false || options.dataFile === false) return {};

  const legacyEnvFile = process.env.SKYBRIDGE_DATA_FILE;
  const defaultJsonFile = join(process.cwd(), ".data", "skybridge-store.json");
  const jsonMigrationFile = options.jsonMigrationFile === false
    ? undefined
    : options.jsonMigrationFile ?? legacyEnvFile ?? defaultJsonFile;

  const dbFile = options.dbFile
    ?? process.env.SKYBRIDGE_DB_FILE
    ?? sqlitePathFromLegacy(options.dataFile || legacyEnvFile)
    ?? join(process.cwd(), ".data", "skybridge.sqlite");

  return { dbFile, jsonMigrationFile };
}

function sqlitePathFromLegacy(filePath: string | false | undefined): string | undefined {
  if (!filePath) return undefined;
  if (extname(filePath).toLowerCase() !== ".json") return filePath;
  return join(dirname(filePath), `${basename(filePath, ".json")}.sqlite`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const port = Number(process.env.PORT || 8787);
  const host = process.env.HOST || "0.0.0.0";
  const app = await createServer();
  await app.listen({ port, host });
}
