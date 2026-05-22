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
  SOURCE_CAPABILITIES,
  SharedRedactionRules,
  type RunDetail,
  type RunSummary,
  type IterationRun,
  type IterationState,
  type SkyBridgeSeverity,
  type SkyBridgeEventType,
  type SkyBridgeEvent,
  type SkyBridgeSourcePlatform
} from "@skybridge-agent-hub/event-schema";
import { send as sendNtfy, type NotificationMessage } from "@skybridge-agent-hub/notification-ntfy";
import { MemoryStore, SqliteStore, type EventStore, type StoredAuditRecord, type StoredEvent, type StoredNotification } from "./store.js";

export type { StoredAuditRecord, StoredEvent, StoredNotification } from "./store.js";

interface CreateServerOptions {
  dbFile?: string | false;
  dataFile?: string | false;
  jsonMigrationFile?: string | false;
  logger?: boolean;
}

type StoredIterationRun = IterationRun & { events: Array<{ type: string; time: string; payload: Record<string, unknown> }> };

const ITERATION_STATES: IterationState[] = [
  "idle",
  "queued",
  "planning",
  "coding",
  "local_checking",
  "pushing",
  "pr_opened",
  "ci_pending",
  "ci_failed",
  "ci_repairing",
  "ci_green",
  "auto_merge_enabled",
  "merged",
  "blocked",
  "failed"
];

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
  const iterationStore = new Map<string, StoredIterationRun>();
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

  const recordNotification = async (
    message: NotificationMessage,
    provider: StoredNotification["provider"],
    status: StoredNotification["status"],
    error?: string,
    event?: StoredEvent
  ) => {
    const now = new Date().toISOString();
    await store.addNotification({
      id: nanoid(),
      category: event ? categoryForEvent(event) : "manual",
      severity: event?.severity,
      source_event_id: event?.id,
      target: provider,
      provider,
      dedupe_key: event ? `${event.type}:${event.correlation?.run_id ?? event.correlation?.session_id ?? event.id}:${provider}` : undefined,
      status,
      message,
      retry_count: 0,
      createdAt: now,
      updatedAt: now,
      error
    });
  };

  const maybeNotify = async (event: StoredEvent) => {
    if (!isNotificationTrigger(event)) return;
    const message = notificationForEvent(event);
    if (!process.env.NTFY_TOPIC_URL) {
      await recordNotification(message, "placeholder", "skipped", "NTFY_TOPIC_URL is not configured.", event);
      return;
    }
    const result = await sendNtfy(message);
    await recordNotification(message, result.provider, result.status, result.error, event);
  };

  const addStoredEvent = async (event: StoredEvent) => {
    await store.addEvent(event);
    const auditRecord = auditRecordForEvent(event);
    if (auditRecord) await store.addAuditRecord(auditRecord);
    broadcast(event);
    void maybeNotify(event);
  };

  const healthResponse = () => ({
    ok: true,
    service: "skybridge-server",
    persistence: store.kind,
    dbFile: persistence.dbFile,
    jsonMigrationFile: persistence.jsonMigrationFile,
    time: new Date().toISOString()
  });

  app.get("/health", async () => healthResponse());
  app.get("/v1/health", async () => healthResponse());
  app.get("/v1/sources", async () => ({ sources: SOURCE_CAPABILITIES }));

  app.get("/v1/iterations", async () => ({
    iterations: [...iterationStore.values()].map(({ events: _events, ...iteration }) => iteration)
      .sort((a, b) => b.updated_at.localeCompare(a.updated_at))
  }));

  app.get<{ Params: { iterationId: string } }>("/v1/iterations/:iterationId", async (request, reply) => {
    const iteration = iterationStore.get(decodeURIComponent(request.params.iterationId));
    if (!iteration) return reply.code(404).send({ ok: false, error: "iteration_not_found" });
    return { iteration };
  });

  app.post<{ Body: Partial<IterationRun> }>("/v1/iterations", async (request, reply) => {
    const parsed = parseIterationInput(request.body);
    if (!parsed.ok) return reply.code(400).send(parsed.response);
    iterationStore.set(parsed.iteration.iteration_id, { ...parsed.iteration, events: [] });
    return reply.code(201).send({ ok: true, iteration: parsed.iteration });
  });

  app.patch<{ Params: { iterationId: string }; Body: { state?: string; last_error?: unknown; pr_number?: unknown; attempts?: unknown; checks?: unknown } }>(
    "/v1/iterations/:iterationId/state",
    async (request, reply) => {
      const iterationId = decodeURIComponent(request.params.iterationId);
      const existing = iterationStore.get(iterationId);
      if (!existing) return reply.code(404).send({ ok: false, error: "iteration_not_found" });
      if (!request.body?.state || !isIterationState(request.body.state)) {
        return reply.code(400).send({ ok: false, error: "invalid_state" });
      }
      const updated: StoredIterationRun = {
        ...existing,
        state: request.body.state,
        attempts: typeof request.body.attempts === "number" && Number.isInteger(request.body.attempts) ? request.body.attempts : existing.attempts,
        pr_number: typeof request.body.pr_number === "number" && Number.isInteger(request.body.pr_number) ? request.body.pr_number : existing.pr_number,
        last_error: safeString(request.body.last_error),
        checks: Array.isArray(request.body.checks) ? sanitizeChecks(request.body.checks) : existing.checks,
        updated_at: new Date().toISOString()
      };
      iterationStore.set(iterationId, updated);
      return { ok: true, iteration: updated };
    }
  );

  app.post<{ Params: { iterationId: string }; Body: { type?: string; payload?: unknown } }>("/v1/iterations/:iterationId/events", async (request, reply) => {
    const iterationId = decodeURIComponent(request.params.iterationId);
    const existing = iterationStore.get(iterationId);
    if (!existing) return reply.code(404).send({ ok: false, error: "iteration_not_found" });
    const type = safeString(request.body?.type);
    if (!type || !type.startsWith("iteration.")) return reply.code(400).send({ ok: false, error: "invalid_iteration_event" });
    const payload = sanitizeIterationPayload(request.body?.payload);
    if (!payload.ok) return reply.code(400).send(payload.response);
    const event = { type, time: new Date().toISOString(), payload: payload.payload };
    existing.events.push(event);
    existing.updated_at = event.time;
    iterationStore.set(iterationId, existing);
    return reply.code(202).send({ ok: true, event });
  });

  app.get<{ Params: { iterationId: string } }>("/v1/iterations/:iterationId/logs", async (request, reply) => {
    const iteration = iterationStore.get(decodeURIComponent(request.params.iterationId));
    if (!iteration) return reply.code(404).send({ ok: false, error: "iteration_not_found" });
    return {
      iteration_id: iteration.iteration_id,
      raw_logs_included: false,
      metadata_only: true,
      local_log_hint: `.agent/iterations/${iteration.iteration_id}/`
    };
  });

  app.get("/v1/supervisor/status", async () => supervisorStatus([...iterationStore.values()], store.listEvents()));
  app.get("/v1/supervisor/next-action", async () => supervisorNextAction([...iterationStore.values()]));

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
    await addStoredEvent(stored);
    return reply.code(202).send({ ok: true, id: stored.id });
  });

  app.get<{ Querystring: EventListQuery }>("/v1/events", async (request, reply) => {
    const parsed = parseEventListQuery(request.query);
    if (!parsed.ok) return reply.code(400).send(parsed.response);
    const { limit, offset, ...filters } = parsed.query;
    const filtered = filterEvents(store.listEvents(), filters);
    const end = Math.max(0, filtered.length - offset);
    const start = Math.max(0, end - limit);
    const events = filtered.slice(start, end);
    return { events };
  });

  app.get<{ Querystring: RunListQuery }>("/v1/runs", async (request, reply) => {
    const parsed = parseRunListQuery(request.query);
    if (!parsed.ok) return reply.code(400).send(parsed.response);
    const { limit, ...filters } = parsed.query;
    return { runs: filterRuns(summarizeRuns(store.listEvents()), filters).slice(0, limit) };
  });

  app.get<{ Params: { runId: string }; Querystring: { limit?: string | number } }>("/v1/runs/:runId", async (request, reply) => {
    const runId = decodeURIComponent(request.params.runId);
    const limit = parseBoundedInteger(request.query.limit, "limit", 1, 1000, 200);
    if (!limit.ok) return reply.code(400).send(limit.response);
    const events = store.listEvents().filter((event) => runGroupId(event) === runId);
    const [summary] = summarizeRuns(events);
    if (!summary) return reply.code(404).send({ ok: false, error: "run_not_found" });
    return { summary, events: events.slice(-limit.value) } satisfies RunDetail;
  });

  app.get<{ Querystring: NotificationListQuery }>("/v1/notifications", async (request, reply) => {
    const parsed = parseNotificationListQuery(request.query);
    if (!parsed.ok) return reply.code(400).send(parsed.response);
    const { limit, ...filters } = parsed.query;
    return { notifications: filterNotifications(store.listNotifications(1000), filters).slice(0, limit) };
  });

  app.get("/v1/notifications/providers", async () => ({ providers: notificationProviders() }));
  app.get("/v1/notifications/rules", async () => ({ rules: notificationRules() }));

  app.get("/v1/nodes", async () => ({ nodes: summarizeNodes(store.listEvents()) }));

  app.get("/v1/summary", async () => {
    const events = store.listEvents();
    const runs = summarizeRuns(events);
    const notifications = store.listNotifications(1000);
    return {
      health: healthResponse(),
      totals: {
        events: events.length,
        runs: runs.length,
        active_runs: runs.filter((run) => run.status === "running").length,
        failed_runs: runs.filter((run) => run.status === "failed").length,
        notifications: notifications.length,
        notification_failed: notifications.filter((notification) => notification.status === "failed").length,
        notification_skipped: notifications.filter((notification) => notification.status === "skipped").length,
        nodes: summarizeNodes(events).length,
        node_stale: summarizeNodes(events).filter((node) => node.status === "stale").length,
        attention_items: runs.filter((run) => run.status === "failed").length
          + events.filter((event) => event.type === "approval.requested").length
          + notifications.filter((notification) => notification.status === "failed" || notification.status === "skipped").length
      },
      sources: summarizeSources(events)
    };
  });

  app.get("/v1/metrics", async () => platformMetrics(store.listEvents(), store.listNotifications(1000)));
  app.get<{ Querystring: AuditListQuery }>("/v1/audit", async (request, reply) => {
    const parsed = parseAuditListQuery(request.query);
    if (!parsed.ok) return reply.code(400).send(parsed.response);
    const { limit, ...filters } = parsed.query;
    return { audit: listAuditRecordsForQuery(store, filters).slice(0, limit) };
  });
  app.get<{ Querystring: AuditListQuery }>("/v1/audit/export", async (request, reply) => {
    const parsed = parseAuditListQuery(request.query);
    if (!parsed.ok) return reply.code(400).send(parsed.response);
    const { limit, ...filters } = parsed.query;
    const audit = listAuditRecordsForQuery(store, filters).slice(0, limit);
    reply
      .header("Content-Type", "application/x-ndjson; charset=utf-8")
      .header("X-SkyBridge-Audit-Export", "fixture-safe-local-jsonl")
      .header("X-SkyBridge-Raw-Payload-Included", "false");
    return audit.map((record) => JSON.stringify(record)).join("\n") + (audit.length > 0 ? "\n" : "");
  });

  app.get("/v1/approvals", async () => ({ approvals: summarizeApprovals(store.listEvents()).filter((item) => item.status === "pending") }));
  app.get<{ Params: { approvalId: string } }>("/v1/approvals/:approvalId", async (request, reply) => {
    const approval = summarizeApprovals(store.listEvents()).find((item) => item.approval_id === decodeURIComponent(request.params.approvalId));
    if (!approval) return reply.code(404).send({ ok: false, error: "approval_not_found" });
    return { approval };
  });
  app.post<{ Params: { approvalId: string }; Body: { decision?: "accepted" | "denied"; actor?: string; reason?: string } }>("/v1/approvals/:approvalId/resolve", async (request, reply) => {
    const approvalId = decodeURIComponent(request.params.approvalId);
    const decision = request.body?.decision;
    if (decision !== "accepted" && decision !== "denied") return reply.code(400).send({ ok: false, error: "decision must be accepted or denied" });
    const existing = summarizeApprovals(store.listEvents()).find((item) => item.approval_id === approvalId);
    if (!existing) return reply.code(404).send({ ok: false, error: "approval_not_found" });
    const event = createEvent({
      type: decision === "accepted" ? "approval.resolved" : "approval.denied",
      severity: decision === "accepted" ? "info" : "warning",
      source: { platform: "skybridge", adapter: "approval-api" },
      correlation: { run_id: existing.run_id, session_id: existing.session_id },
      payload: {
        approval_id: approvalId,
        decision,
        actor: safeString(request.body?.actor) ?? "operator",
        reason: safeString(request.body?.reason),
        remote_execution_enabled: false
      }
    });
    const stored: StoredEvent = { ...event, id: event.event_id ?? nanoid(), receivedAt: new Date().toISOString() };
    await addStoredEvent(stored);
    return reply.code(202).send({ ok: true, approval_id: approvalId, decision });
  });

  app.post<{ Body: NotificationMessage }>("/v1/notifications/send", async (request, reply) => {
    const message = request.body;
    if (!message?.title || !message?.body) {
      return reply.code(400).send({ ok: false, error: "title and body are required" });
    }
    const result = await sendNtfy(message);
    const provider = result.status === "skipped" ? "placeholder" : result.provider;
    await recordNotification(message, provider, result.status, result.error);
    return reply.code(202).send({ ok: true, provider, status: result.status, skipped: result.status === "skipped" });
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
    await addStoredEvent(stored);
    return reply.code(202).send({ ok: true, id: stored.id });
  });

  return app;
}

interface EventListQuery {
  run_id?: string;
  session_id?: string;
  platform?: SkyBridgeSourcePlatform;
  adapter?: string;
  source_platform?: string;
  source_adapter?: string;
  type?: SkyBridgeEventType;
  severity?: SkyBridgeSeverity;
  from?: string;
  to?: string;
  limit?: string | number;
  offset?: string | number;
}

type ParsedEventListQuery = Omit<EventListQuery, "limit" | "offset"> & { limit: number; offset: number };

interface RunListQuery {
  platform?: SkyBridgeSourcePlatform;
  adapter?: string;
  source_platform?: string;
  source_adapter?: string;
  status?: RunSummary["status"];
  lifecycle?: string;
  branch?: string;
  goal?: string;
  from?: string;
  to?: string;
  limit?: string | number;
}

type ParsedRunListQuery = Omit<RunListQuery, "limit"> & { limit: number };

interface NotificationListQuery {
  status?: StoredNotification["status"];
  provider?: StoredNotification["provider"];
  severity?: SkyBridgeSeverity;
  limit?: string | number;
}

type ParsedNotificationListQuery = Omit<NotificationListQuery, "limit"> & { limit: number };

interface AuditListQuery {
  action?: string;
  actor?: string;
  run_id?: string;
  from?: string;
  to?: string;
  limit?: string | number;
}

type ParsedAuditListQuery = Omit<AuditListQuery, "limit"> & { limit: number };

function filterEvents(events: StoredEvent[], query: Omit<ParsedEventListQuery, "limit" | "offset">): StoredEvent[] {
  const platform = query.platform ?? query.source_platform;
  const adapter = query.adapter ?? query.source_adapter;
  return events.filter((event) => {
    if (query.run_id && runGroupId(event) !== query.run_id) return false;
    if (query.session_id && event.correlation?.session_id !== query.session_id) return false;
    if (platform && event.source.platform !== platform) return false;
    if (adapter && event.source.adapter !== adapter) return false;
    if (query.type && event.type !== query.type) return false;
    if (query.severity && event.severity !== query.severity) return false;
    if (query.from && event.time < query.from) return false;
    if (query.to && event.time > query.to) return false;
    return true;
  });
}

function filterRuns(runs: RunSummary[], query: Omit<ParsedRunListQuery, "limit">): RunSummary[] {
  const platform = query.platform ?? query.source_platform;
  const adapter = query.adapter ?? query.source_adapter;
  const goal = query.goal?.toLowerCase();
  return runs.filter((run) => {
    if (platform && run.source_platform !== platform) return false;
    if (adapter && run.source_adapter !== adapter) return false;
    if (query.status && run.status !== query.status) return false;
    if (query.lifecycle && run.lifecycle !== query.lifecycle) return false;
    if (query.branch && run.branch !== query.branch) return false;
    if (goal && !`${run.goal ?? ""} ${run.goal_id ?? ""} ${run.title ?? ""}`.toLowerCase().includes(goal)) return false;
    if (query.from && run.last_seen_at < query.from) return false;
    if (query.to && run.first_seen_at > query.to) return false;
    return true;
  });
}

function filterNotifications(notifications: StoredNotification[], query: Omit<ParsedNotificationListQuery, "limit">): StoredNotification[] {
  return notifications.filter((notification) => {
    if (query.status && notification.status !== query.status) return false;
    if (query.provider && notification.provider !== query.provider) return false;
    if (query.severity) {
      const priority = notification.message.priority;
      const severityMatch =
        (query.severity === "critical" && priority === "urgent")
        || (query.severity === "error" && priority === "high")
        || (query.severity === "warning" && priority === "default")
        || (query.severity === "info" && (priority === "low" || priority === undefined));
      if (!severityMatch) return false;
    }
    return true;
  });
}

function filterAuditRecords(records: StoredAuditRecord[], query: Omit<ParsedAuditListQuery, "limit">): StoredAuditRecord[] {
  return records.filter((record) => {
    if (query.action && record.action !== query.action) return false;
    if (query.actor && record.actor !== query.actor) return false;
    if (query.run_id && record.run_id !== query.run_id) return false;
    if (query.from && record.time < query.from) return false;
    if (query.to && record.time > query.to) return false;
    return true;
  });
}

function listAuditRecordsForQuery(store: EventStore, filters: Omit<ParsedAuditListQuery, "limit">): StoredAuditRecord[] {
  const durableAudit = store.listAuditRecords(1000);
  const audit = durableAudit.length > 0 ? durableAudit : summarizeAudit(store.listEvents());
  return filterAuditRecords(audit, filters);
}

function parseEventListQuery(query: EventListQuery): ParsedQuery<ParsedEventListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 1000, 200);
  if (!limit.ok) return limit;
  const offset = parseBoundedInteger(query.offset, "offset", 0, 100_000, 0);
  if (!offset.ok) return offset;
  const validation = validateCommonQuery(query);
  if (!validation.ok) return validation;
  return { ok: true, query: { ...query, limit: limit.value, offset: offset.value } };
}

function parseRunListQuery(query: RunListQuery): ParsedQuery<ParsedRunListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 1000, 200);
  if (!limit.ok) return limit;
  const validation = validateCommonQuery(query);
  if (!validation.ok) return validation;
  if (query.status && !["running", "completed", "failed", "unknown"].includes(query.status)) {
    return invalidQuery("status", "Expected one of running, completed, failed or unknown.");
  }
  return { ok: true, query: { ...query, limit: limit.value } };
}

function parseNotificationListQuery(query: NotificationListQuery): ParsedQuery<ParsedNotificationListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 1000, 200);
  if (!limit.ok) return limit;
  if (query.status && !["pending", "sent", "skipped", "failed"].includes(query.status)) {
    return invalidQuery("status", "Expected one of pending, sent, skipped or failed.");
  }
  if (query.provider && !["ntfy", "apprise", "gotify", "bark", "wecom", "fcm", "xiaomi-push", "placeholder"].includes(query.provider)) {
    return invalidQuery("provider", "Expected a supported notification provider.");
  }
  if (query.severity && !isSeverity(query.severity)) return invalidQuery("severity", "Expected a SkyBridge severity.");
  return { ok: true, query: { ...query, limit: limit.value } };
}

function parseAuditListQuery(query: AuditListQuery): ParsedQuery<ParsedAuditListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 1000, 100);
  if (!limit.ok) return limit;
  if (query.from && !isIsoDate(query.from)) return invalidQuery("from", "Expected an ISO timestamp.");
  if (query.to && !isIsoDate(query.to)) return invalidQuery("to", "Expected an ISO timestamp.");
  if (query.from && query.to && query.from > query.to) return invalidQuery("from", "Expected from to be earlier than or equal to to.");
  return { ok: true, query: { ...query, limit: limit.value } };
}

function validateCommonQuery(query: EventListQuery | RunListQuery): ParsedQuery<{}> {
  const platform = query.platform ?? query.source_platform;
  if (platform && !isPlatform(platform)) return invalidQuery("platform", "Expected one of codex, opencode, hermes, skybridge or custom.");
  if ("severity" in query && query.severity && !isSeverity(query.severity)) return invalidQuery("severity", "Expected a SkyBridge severity.");
  if ("type" in query && query.type && !isEventType(query.type)) return invalidQuery("type", "Expected a SkyBridge event type.");
  if (query.from && !isIsoDate(query.from)) return invalidQuery("from", "Expected an ISO timestamp.");
  if (query.to && !isIsoDate(query.to)) return invalidQuery("to", "Expected an ISO timestamp.");
  if (query.from && query.to && query.from > query.to) return invalidQuery("from", "Expected from to be earlier than or equal to to.");
  return { ok: true, query: {} };
}

type ParsedQuery<T> = { ok: true; query: T } | { ok: false; response: QueryErrorResponse };
type ParsedNumber = { ok: true; value: number } | { ok: false; response: QueryErrorResponse };

function parseBoundedInteger(input: string | number | undefined, field: string, min: number, max: number, fallback: number): ParsedNumber {
  if (input === undefined || input === "") return { ok: true, value: fallback };
  const parsed = typeof input === "number" ? input : Number(input);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    return invalidQuery(field, `Expected an integer from ${min} to ${max}.`);
  }
  return { ok: true, value: parsed };
}

function invalidQuery(field: string, message: string): { ok: false; response: QueryErrorResponse } {
  return { ok: false, response: { ok: false, error: "invalid_query", issues: [{ field, message }] } };
}

interface QueryErrorResponse {
  ok: false;
  error: "invalid_query";
  issues: Array<{ field: string; message: string }>;
}

function isIsoDate(input: string): boolean {
  return !Number.isNaN(Date.parse(input)) && new Date(input).toISOString() === input;
}

function isPlatform(input: string): input is SkyBridgeSourcePlatform {
  return ["codex", "opencode", "hermes", "skybridge", "custom"].includes(input);
}

function isSeverity(input: string): input is SkyBridgeSeverity {
  return ["debug", "info", "warning", "error", "critical"].includes(input);
}

function isEventType(input: string): input is SkyBridgeEventType {
  return [
    "session.started",
    "session.completed",
    "run.started",
    "run.completed",
    "run.failed",
    "turn.started",
    "turn.completed",
    "plan.updated",
    "todo.updated",
    "tool.started",
    "tool.completed",
    "tool.failed",
    "file.edited",
    "diff.updated",
    "approval.requested",
    "approval.resolved",
    "approval.denied",
    "approval.expired",
    "message.delta",
    "message.completed",
    "agent.idle",
    "agent.error",
    "agent.stale",
    "node.connected",
    "node.heartbeat",
    "node.disconnected",
    "iteration.started",
    "iteration.state_changed",
    "iteration.local_check_started",
    "iteration.local_check_passed",
    "iteration.local_check_failed",
    "iteration.pr_opened",
    "iteration.ci_pending",
    "iteration.ci_failed",
    "iteration.ci_repair_started",
    "iteration.ci_green",
    "iteration.auto_merge_enabled",
    "iteration.merged",
    "iteration.blocked",
    "iteration.failed",
    "iteration.completed",
    "notification.requested",
    "notification.sent",
    "notification.skipped",
    "notification.failed"
  ].includes(input);
}

function summarizeSources(events: StoredEvent[]) {
  const sources = new Map<string, { platform: string; adapter: string; event_count: number; latest_event_at: string }>();
  for (const event of events) {
    const key = `${event.source.platform}/${event.source.adapter}`;
    const existing = sources.get(key);
    if (!existing) {
      sources.set(key, {
        platform: event.source.platform,
        adapter: event.source.adapter,
        event_count: 1,
        latest_event_at: event.time
      });
      continue;
    }
    existing.event_count += 1;
    if (event.time > existing.latest_event_at) existing.latest_event_at = event.time;
  }
  return [...sources.values()].sort((a, b) => b.latest_event_at.localeCompare(a.latest_event_at));
}

function notificationProviders() {
  return [
    providerStatus("ntfy", Boolean(process.env.NTFY_TOPIC_URL), "NTFY_TOPIC_URL"),
    providerStatus("apprise", Boolean(process.env.APPRISE_URL), "APPRISE_URL"),
    providerStatus("gotify", Boolean(process.env.GOTIFY_URL), "GOTIFY_URL"),
    providerStatus("bark", Boolean(process.env.BARK_URL), "BARK_URL"),
    providerStatus("wecom", Boolean(process.env.WECOM_WEBHOOK_URL), "WECOM_WEBHOOK_URL"),
    providerStatus("fcm", Boolean(process.env.FCM_SERVER_KEY), "FCM_SERVER_KEY"),
    providerStatus("xiaomi-push", Boolean(process.env.XIAOMI_PUSH_SECRET), "XIAOMI_PUSH_SECRET")
  ];
}

function providerStatus(provider: string, configured: boolean, required_env: string) {
  return {
    provider,
    configured,
    status: configured ? "available" : "skipped",
    required_env,
    credential_values_exposed: false
  };
}

function notificationRules() {
  return [
    {
      id: "critical-failures",
      event_type_patterns: ["run.failed", "approval.requested", "notification.requested"],
      severity_threshold: "warning",
      quiet_hours: "placeholder",
      providers: ["ntfy"],
      dedupe: true
    }
  ];
}

function categoryForEvent(event: StoredEvent): string {
  if (event.type.startsWith("approval.")) return "approval";
  if (event.type.startsWith("notification.")) return "notification";
  if (event.type.startsWith("run.")) return "run";
  return "event";
}

function summarizeNodes(events: StoredEvent[]) {
  const nodes = new Map<string, {
    node_id: string;
    host?: string;
    labels: string[];
    capabilities: string[];
    sidecar_version?: string;
    last_seen: string;
    status: "connected" | "stale" | "disconnected";
    event_count: number;
  }>();
  for (const event of events.filter((item) => item.type.startsWith("node."))) {
    const nodeId = event.source.node_id ?? safeString(event.payload.node_id) ?? event.correlation?.session_id ?? "unknown-node";
    const existing = nodes.get(nodeId) ?? {
      node_id: nodeId,
      labels: [],
      capabilities: [],
      last_seen: event.time,
      status: "connected" as const,
      event_count: 0
    };
    existing.event_count += 1;
    existing.last_seen = event.time > existing.last_seen ? event.time : existing.last_seen;
    existing.host = safeString(event.payload.host) ?? existing.host;
    existing.sidecar_version = safeString(event.payload.sidecar_version) ?? existing.sidecar_version;
    existing.labels = safeStringArray(event.payload.labels) ?? existing.labels;
    existing.capabilities = safeStringArray(event.payload.capabilities) ?? existing.capabilities;
    existing.status = event.type === "node.disconnected" ? "disconnected" : "connected";
    nodes.set(nodeId, existing);
  }
  const staleBefore = Date.now() - 5 * 60 * 1000;
  return [...nodes.values()].map((node) => ({
    ...node,
    status: node.status === "connected" && Date.parse(node.last_seen) < staleBefore ? "stale" : node.status
  })).sort((a, b) => b.last_seen.localeCompare(a.last_seen));
}

function platformMetrics(events: StoredEvent[], notifications: StoredNotification[]) {
  const runs = summarizeRuns(events);
  const nodes = summarizeNodes(events);
  return {
    total_events: events.length,
    runs_by_status: countBy(runs, (run) => run.status),
    runs_by_source: countBy(runs, (run) => run.source_platform),
    notifications_by_status: countBy(notifications, (notification) => notification.status),
    notifications_by_severity: countBy(notifications, (notification) => notification.severity ?? "unknown"),
    node_status_counts: countBy(nodes, (node) => node.status),
    recent_failures: runs.filter((run) => run.status === "failed").slice(0, 10)
  };
}

function summarizeAudit(events: StoredEvent[]) {
  return events
    .filter((event) =>
      event.type.startsWith("approval.")
      || event.type.startsWith("node.")
      || event.type.startsWith("notification.")
      || event.type === "run.failed"
    )
    .map((event) => auditRecordForEvent(event))
    .filter((record): record is StoredAuditRecord => Boolean(record))
    .sort((a, b) => b.time.localeCompare(a.time));
}

function auditRecordForEvent(event: StoredEvent): StoredAuditRecord | undefined {
  if (
    !event.type.startsWith("approval.")
    && !event.type.startsWith("node.")
    && !event.type.startsWith("notification.")
    && event.type !== "run.failed"
  ) {
    return undefined;
  }

  return {
    audit_id: `audit_${event.id}`,
    time: event.time,
    action: event.type,
    actor: safeString(event.payload.actor) ?? safeString(event.payload.operator) ?? event.source.agent_id ?? "system",
    source_adapter: `${event.source.platform}/${event.source.adapter}`,
    run_id: event.correlation?.run_id,
    session_id: event.correlation?.session_id,
    safety_decision: safetyDecisionForEvent(event),
    immutable_event_id: event.id,
    redaction_policy_version: "packages/event-schema/src/redaction-rules.json",
    raw_payload_included: false
  };
}

function summarizeApprovals(events: StoredEvent[]) {
  const approvals = new Map<string, {
    approval_id: string;
    run_id?: string;
    session_id?: string;
    status: "pending" | "accepted" | "denied" | "expired";
    title?: string;
    requested_at: string;
    resolved_at?: string;
    source: string;
  }>();
  for (const event of events.filter((item) => item.type.startsWith("approval."))) {
    const approvalId = safeString(event.payload.approval_id) ?? event.correlation?.tool_call_id ?? event.id;
    const existing = approvals.get(approvalId) ?? {
      approval_id: approvalId,
      run_id: event.correlation?.run_id,
      session_id: event.correlation?.session_id,
      status: "pending" as const,
      title: safeString(event.payload.title) ?? safeString(event.payload.permission) ?? event.type,
      requested_at: event.time,
      source: `${event.source.platform}/${event.source.adapter}`
    };
    if (event.type === "approval.resolved") existing.status = "accepted";
    if (event.type === "approval.denied") existing.status = "denied";
    if (event.type === "approval.expired") existing.status = "expired";
    if (event.type !== "approval.requested") existing.resolved_at = event.time;
    approvals.set(approvalId, existing);
  }
  return [...approvals.values()].sort((a, b) => b.requested_at.localeCompare(a.requested_at));
}

function safetyDecisionForEvent(event: StoredEvent): string {
  if (event.type === "approval.denied") return "operator_denied";
  if (event.type === "approval.expired") return "approval_expired";
  if (event.type === "approval.resolved") return "operator_accepted_local_record_only";
  if (event.type === "approval.requested") return "approval_required_remote_execution_disabled";
  if (event.type.startsWith("node.")) return "node_telemetry_only";
  if (event.type.startsWith("notification.")) return "notification_metadata_only";
  if (event.type === "run.failed") return "failure_observed";
  return "recorded";
}

function countBy<T>(items: T[], key: (item: T) => string): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const item of items) counts[key(item)] = (counts[key(item)] ?? 0) + 1;
  return counts;
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

function safeStringArray(input: unknown): string[] | undefined {
  return Array.isArray(input) && input.every((item) => typeof item === "string" && item.length <= 80) ? input : undefined;
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
    const payloadBytes = Buffer.byteLength(JSON.stringify(input ?? null), "utf8");
    if (payloadBytes > SharedRedactionRules.maxPayloadBytes) {
      return {
        ok: false,
        response: {
          ok: false,
          error: "invalid_event",
          message: "Event payload exceeded the safe size limit.",
          issues: [{ path: "", code: "too_big", message: `Payload must be <= ${SharedRedactionRules.maxPayloadBytes} bytes.` }]
        }
      };
    }
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

function parseIterationInput(input: Partial<IterationRun> | undefined): { ok: true; iteration: IterationRun } | { ok: false; response: QueryErrorResponse & { message?: string } } {
  const now = new Date().toISOString();
  if (!input || typeof input !== "object") return invalidQuery("body", "Expected an iteration object.");
  if (!safeString(input.iteration_id)) return invalidQuery("iteration_id", "Expected a stable iteration id.");
  if (!safeString(input.project_id)) return invalidQuery("project_id", "Expected a project id.");
  if (!safeString(input.repo)) return invalidQuery("repo", "Expected a repository full name.");
  if (!safeString(input.branch)) return invalidQuery("branch", "Expected a branch.");
  if (!safeString(input.base_branch)) return invalidQuery("base_branch", "Expected a base branch.");
  if (!isIterationState(input.state ?? "")) return invalidQuery("state", "Expected a valid iteration state.");
  const iterationId = input.iteration_id!;
  const projectId = input.project_id!;
  const repo = input.repo!;
  const branch = input.branch!;
  const baseBranch = input.base_branch!;
  const state = input.state!;

  return {
    ok: true,
    iteration: {
      iteration_id: iterationId,
      project_id: projectId,
      goal_id: safeString(input.goal_id),
      repo,
      branch,
      base_branch: baseBranch,
      pr_number: typeof input.pr_number === "number" && Number.isInteger(input.pr_number) ? input.pr_number : undefined,
      state,
      attempts: typeof input.attempts === "number" && Number.isInteger(input.attempts) ? input.attempts : 0,
      max_attempts: typeof input.max_attempts === "number" && Number.isInteger(input.max_attempts) ? input.max_attempts : 3,
      last_error: safeString(input.last_error),
      checks: sanitizeChecks(input.checks ?? []),
      auto_merge_enabled: input.auto_merge_enabled === true,
      created_at: safeString(input.created_at) ?? now,
      updated_at: safeString(input.updated_at) ?? now
    }
  };
}

function isIterationState(input: string): input is IterationState {
  return (ITERATION_STATES as string[]).includes(input);
}

function sanitizeChecks(input: unknown): IterationRun["checks"] {
  if (!Array.isArray(input)) return [];
  return input.slice(0, 50).map((item) => {
    const record = item && typeof item === "object" ? item as Record<string, unknown> : {};
    const status = safeString(record.status);
    return {
      name: safeString(record.name) ?? "check",
      status: status === "pending" || status === "passed" || status === "failed" || status === "skipped" ? status : "pending",
      started_at: safeString(record.started_at),
      completed_at: safeString(record.completed_at),
      exit_code: typeof record.exit_code === "number" && Number.isInteger(record.exit_code) ? record.exit_code : undefined,
      summary: safeString(record.summary)
    };
  });
}

function sanitizeIterationPayload(input: unknown): { ok: true; payload: Record<string, unknown> } | { ok: false; response: QueryErrorResponse } {
  const redacted = redactUnsafePayload(input);
  const payload = redacted && typeof redacted === "object" && !Array.isArray(redacted) ? redacted as Record<string, unknown> : { value: redacted };
  const bytes = Buffer.byteLength(JSON.stringify(payload), "utf8");
  if (bytes > SharedRedactionRules.maxPayloadBytes) return invalidQuery("payload", `Payload must be <= ${SharedRedactionRules.maxPayloadBytes} bytes.`);
  return { ok: true, payload };
}

function redactUnsafePayload(input: unknown): unknown {
  if (typeof input === "string") return input.length > 200 ? `${input.slice(0, 200)}...` : input;
  if (Array.isArray(input)) return input.slice(0, 50).map(redactUnsafePayload);
  if (!input || typeof input !== "object") return input;
  const output: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (/token|secret|password|cookie|credential|authorization/i.test(key)) {
      output[key] = SharedRedactionRules.replacement;
    } else if (/prompt|patch|stdout|stderr|output|command_output|tool_result/i.test(key)) {
      output[key] = { omitted: true, reason: "unsafe_raw_payload" };
    } else {
      output[key] = redactUnsafePayload(value);
    }
  }
  return output;
}

function supervisorStatus(iterations: StoredIterationRun[], events: StoredEvent[]) {
  const sorted = iterations.sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  const blocked = sorted.filter((iteration) => iteration.state === "blocked" || iteration.state === "failed");
  const active = sorted.filter((iteration) => !["merged", "blocked", "failed"].includes(iteration.state));
  return {
    ok: true,
    raw_prompts_included: false,
    raw_logs_included: false,
    iterations: {
      total: iterations.length,
      active: active.length,
      blocked: blocked.length,
      latest: sorted[0]
    },
    recent_iteration_events: events.filter((event) => event.type.startsWith("iteration.")).slice(-20)
  };
}

function supervisorNextAction(iterations: StoredIterationRun[]) {
  const latest = iterations.sort((a, b) => b.updated_at.localeCompare(a.updated_at))[0];
  if (!latest) return { action: "start_next_iteration", reason: "no_iterations_recorded" };
  if (latest.state === "ci_failed") return { action: "repair_ci", iteration_id: latest.iteration_id, pr_number: latest.pr_number };
  if (latest.state === "blocked" || latest.state === "failed") return { action: "notify_human", iteration_id: latest.iteration_id, reason: latest.last_error };
  if (latest.state === "ci_green") return { action: latest.auto_merge_enabled ? "wait_for_merge" : "review_green_pr", iteration_id: latest.iteration_id, pr_number: latest.pr_number };
  return { action: "observe", iteration_id: latest.iteration_id, state: latest.state };
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
