import cors from "@fastify/cors";
import Fastify, { type FastifyInstance } from "fastify";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
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

export type StoredEvent = SkyBridgeEvent & { id: string; receivedAt: string };

interface StoredNotification {
  id: string;
  provider: "ntfy" | "placeholder";
  status: "sent" | "skipped" | "failed";
  message: NotificationMessage;
  createdAt: string;
  error?: string;
}

interface LocalStoreData {
  events: StoredEvent[];
  notifications: StoredNotification[];
}

class LocalJsonStore {
  private data: LocalStoreData = { events: [], notifications: [] };

  constructor(private readonly filePath: string | undefined) {}

  async load(): Promise<void> {
    if (!this.filePath) return;
    try {
      const content = await readFile(this.filePath, "utf8");
      const parsed = JSON.parse(content) as Partial<LocalStoreData>;
      this.data = {
        events: parsed.events ?? [],
        notifications: parsed.notifications ?? []
      };
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
  }

  listEvents(): StoredEvent[] {
    return [...this.data.events];
  }

  listNotifications(): StoredNotification[] {
    return [...this.data.notifications];
  }

  async addEvent(event: StoredEvent): Promise<void> {
    this.data.events.push(event);
    await this.persist();
  }

  async addNotification(notification: StoredNotification): Promise<void> {
    this.data.notifications.push(notification);
    await this.persist();
  }

  private async persist(): Promise<void> {
    if (!this.filePath) return;
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, JSON.stringify(this.data, null, 2), "utf8");
  }
}

interface CreateServerOptions {
  dataFile?: string | false;
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
  const dataFile = options.dataFile === false ? undefined : options.dataFile ?? process.env.SKYBRIDGE_DATA_FILE ?? join(process.cwd(), ".data", "skybridge-store.json");
  const store = new LocalJsonStore(dataFile);
  const clients = new Set<{ write: (data: string) => void }>();
  const app = Fastify({ logger: options.logger ?? true });

  await store.load();
  await app.register(cors, { origin: true });

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
    persistence: dataFile ? "local-json" : "memory",
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
    events: store.listEvents().slice(-200)
  }));

  app.get("/v1/runs", async () => ({
    runs: summarizeRuns(store.listEvents())
  }));

  app.get("/v1/notifications", async () => ({
    notifications: store.listNotifications().slice(-200)
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
    for (const event of store.listEvents().slice(-20)) {
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

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const port = Number(process.env.PORT || 8787);
  const host = process.env.HOST || "0.0.0.0";
  const app = await createServer();
  await app.listen({ port, host });
}
