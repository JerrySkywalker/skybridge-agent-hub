import cors from "@fastify/cors";
import Fastify, { type FastifyInstance } from "fastify";
import { existsSync } from "node:fs";
import { basename, dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { nanoid } from "nanoid";
import { ZodError } from "zod";
import {
  createEvent,
  isNotificationTrigger,
  parseEvent,
  type RunDetail,
  type RunSummary,
  type SkyBridgeEventType,
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
    const latestPayload = latestObjectPayload(runEvents);
    return {
      run_id,
      session_id: last.correlation?.session_id,
      source_platform: last.source.platform,
      source_adapter: last.source.adapter,
      source_agent_id: last.source.agent_id,
      source_node_id: last.source.node_id,
      status,
      event_count: runEvents.length,
      tool_call_count: runEvents.filter((event) => event.type.startsWith("tool.")).length,
      active_tool_count: activeToolCount(runEvents),
      failed_tool_count: runEvents.filter((event) => event.type === "tool.failed").length,
      notification_count: runEvents.filter((event) => event.type.startsWith("notification.")).length,
      first_seen_at: first.receivedAt,
      last_seen_at: last.receivedAt,
      last_event_type: last.type,
      title: firstSafeString(runEvents, "title") ?? firstSafeString(runEvents, "goalFile"),
      lifecycle: safeString(latestPayload.lifecycle),
      branch: firstSafeString(runEvents, "branch"),
      cwd: firstSourceCwd(runEvents),
      goal: firstSafeString(runEvents, "goal") ?? firstSafeString(runEvents, "goalFile"),
      goal_id: firstSafeString(runEvents, "goalId"),
      latest_message_summary: latestMessageSummary(runEvents)
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
    const parsed = parseEventPayload(request.body);
    if (!parsed.ok) return reply.code(400).send(parsed.response);

    const event = parsed.event;
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

  app.get<{ Querystring: EventListQuery }>("/v1/events", async (request) => ({
    events: filterEvents(store.listEvents(), request.query).slice(-eventLimit(request.query.limit))
  }));

  app.get("/v1/runs", async () => ({
    runs: summarizeRuns(store.listEvents())
  }));

  app.get<{ Params: { runId: string } }>("/v1/runs/:runId", async (request, reply) => {
    const runId = decodeURIComponent(request.params.runId);
    const events = store.listEvents().filter((event) => runGroupId(event) === runId);
    const [summary] = summarizeRuns(events);
    if (!summary) return reply.code(404).send({ ok: false, error: "run_not_found" });
    return { summary, events } satisfies RunDetail;
  });

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

interface EventListQuery {
  run_id?: string;
  session_id?: string;
  source_platform?: string;
  source_adapter?: string;
  type?: SkyBridgeEventType;
  from?: string;
  to?: string;
  limit?: string | number;
}

function filterEvents(events: StoredEvent[], query: EventListQuery): StoredEvent[] {
  return events.filter((event) => {
    if (query.run_id && runGroupId(event) !== query.run_id) return false;
    if (query.session_id && event.correlation?.session_id !== query.session_id) return false;
    if (query.source_platform && event.source.platform !== query.source_platform) return false;
    if (query.source_adapter && event.source.adapter !== query.source_adapter) return false;
    if (query.type && event.type !== query.type) return false;
    if (query.from && event.time < query.from) return false;
    if (query.to && event.time > query.to) return false;
    return true;
  });
}

function eventLimit(input: string | number | undefined): number {
  const parsed = typeof input === "number" ? input : Number(input);
  if (!Number.isFinite(parsed)) return 200;
  return Math.min(Math.max(Math.trunc(parsed), 1), 1000);
}

function runGroupId(event: StoredEvent): string {
  return event.correlation?.run_id ?? event.correlation?.session_id ?? "unknown";
}

function latestObjectPayload(events: StoredEvent[]): Record<string, unknown> {
  return events.at(-1)?.payload ?? {};
}

function firstSafeString(events: StoredEvent[], key: string): string | undefined {
  for (const event of events) {
    const value = safeString(event.payload[key]);
    if (value) return value;
  }
  return undefined;
}

function firstSourceCwd(events: StoredEvent[]): string | undefined {
  for (const event of events) {
    const value = safeString(event.source.cwd);
    if (value) return value;
  }
  return undefined;
}

function activeToolCount(events: StoredEvent[]): number {
  const active = new Set<string>();
  for (const event of events) {
    const id = event.correlation?.tool_call_id;
    if (!id) continue;
    if (event.type === "tool.started") active.add(id);
    if (event.type === "tool.completed" || event.type === "tool.failed") active.delete(id);
  }
  return active.size;
}

function latestMessageSummary(events: StoredEvent[]): string | undefined {
  for (const event of [...events].reverse()) {
    const direct = safeString(event.payload.summary) ?? safeString(event.payload.message);
    if (direct) return direct;
    const messageSummary = event.payload.message_summary;
    if (messageSummary && typeof messageSummary === "object") {
      const preview = safeString((messageSummary as Record<string, unknown>).preview);
      if (preview) return preview;
    }
  }
  return undefined;
}

function safeString(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 && input.length <= 200 ? input : undefined;
}

function resolvePersistence(options: CreateServerOptions): { dbFile?: string; jsonMigrationFile?: string } {
  if (options.dbFile === false || options.dataFile === false) return {};

  const repositoryRoot = findRepositoryRoot(dirname(fileURLToPath(import.meta.url)));
  const legacyEnvFile = process.env.SKYBRIDGE_DATA_FILE;
  const defaultJsonFile = join(repositoryRoot, ".data", "skybridge-store.json");
  const jsonMigrationFile = options.jsonMigrationFile === false
    ? undefined
    : options.jsonMigrationFile ?? legacyEnvFile ?? defaultJsonFile;

  const dbFile = options.dbFile
    ?? process.env.SKYBRIDGE_DB_FILE
    ?? sqlitePathFromLegacy(options.dataFile || legacyEnvFile)
    ?? join(repositoryRoot, ".data", "skybridge.sqlite");

  return { dbFile, jsonMigrationFile };
}

function parseEventPayload(input: unknown): { ok: true; event: SkyBridgeEvent } | { ok: false; response: ValidationErrorResponse } {
  try {
    return { ok: true, event: parseEvent(input) };
  } catch (error) {
    if (!(error instanceof ZodError)) throw error;
    return {
      ok: false,
      response: {
        ok: false,
        error: "invalid_event",
        message: "Event payload failed validation.",
        issues: error.issues.map((issue) => ({
          path: issue.path.join("."),
          code: issue.code,
          message: issue.message
        }))
      }
    };
  }
}

interface ValidationErrorResponse {
  ok: false;
  error: "invalid_event";
  message: string;
  issues: Array<{
    path: string;
    code: string;
    message: string;
  }>;
}

function findRepositoryRoot(startDir: string): string {
  let current = startDir;
  while (true) {
    if (existsSync(join(current, "pnpm-workspace.yaml"))) return current;
    const parent = dirname(current);
    if (parent === current) return process.cwd();
    current = parent;
  }
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
