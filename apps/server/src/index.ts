import cors from "@fastify/cors";
import Fastify, { type FastifyInstance } from "fastify";
import { existsSync, readFileSync } from "node:fs";
import { timingSafeEqual } from "node:crypto";
import { basename, dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { nanoid } from "nanoid";
import { ZodError } from "zod";
import {
  createEvent,
  listAdapterCapabilities,
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
  type SkyBridgeSourcePlatform,
  type MasterGoal,
  type EvidenceSummary,
  type GoalPriority,
  type GoalRisk,
  type GoalStatus,
  type Project,
  type ProjectControlState,
  type Task,
  type TaskEvent,
  type TaskRisk,
  type TaskSource,
  type TaskStatus,
  type PlannerDecisionAction,
  type Worker,
  type WorkerCapability,
  type WorkerStatus,
} from "@skybridge-agent-hub/event-schema";
import {
  send as sendNtfy,
  type NotificationMessage,
} from "@skybridge-agent-hub/notification-ntfy";
import {
  MemoryStore,
  SqliteStore,
  type EventStore,
  type StoredAuditRecord,
  type StoredEvent,
  type StoredIterationRun,
  type StoredMasterGoal,
  type StoredNotification,
  type StoredProject,
  type StoredTask,
  type StoredTaskEvent,
  type StoredWorker,
  type StoredWorkerHeartbeat,
} from "./store.js";

export type {
  StoredAuditRecord,
  StoredEvent,
  StoredNotification,
} from "./store.js";

interface CreateServerOptions {
  dbFile?: string | false;
  dataFile?: string | false;
  jsonMigrationFile?: string | false;
  logger?: boolean;
}

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
  "failed",
];

const GOAL_STATUSES: GoalStatus[] = [
  "draft",
  "ready",
  "queued",
  "active",
  "partially_completed",
  "completed",
  "failed",
  "blocked",
  "superseded",
  "archived",
  "paused",
  "cancelled",
];
const GOAL_PRIORITIES: GoalPriority[] = ["low", "normal", "high", "urgent"];
const GOAL_RISKS: GoalRisk[] = ["low", "medium", "high"];
const PROJECT_STATUSES = ["active", "paused", "archived"] as const;
const TASK_STATUSES: TaskStatus[] = [
  "queued",
  "claimed",
  "running",
  "completed",
  "failed",
  "blocked",
  "cancelled",
  "stale",
];
const TASK_RISKS: TaskRisk[] = ["low", "medium", "high"];
const TASK_SOURCES: TaskSource[] = [
  "manual",
  "planner",
  "rule_based",
  "hermes-planner",
  "hermes",
  "codex",
  "opencode",
  "custom",
];

function getConfiguredWorkerTokens(): string[] {
  const tokens: string[] = [];
  const envToken = process.env.SKYBRIDGE_WORKER_TOKEN?.trim();
  if (envToken) tokens.push(envToken);

  const tokensFile = process.env.SKYBRIDGE_WORKER_TOKENS_FILE?.trim();
  if (tokensFile && existsSync(tokensFile)) {
    for (const line of readFileSync(tokensFile, "utf8").split(/\r?\n/)) {
      const token = line.trim();
      if (token && !token.startsWith("#")) tokens.push(token);
    }
  }

  return [...new Set(tokens)];
}

function isWorkerAuthRequired(): boolean {
  return getConfiguredWorkerTokens().length > 0 || process.env.SKYBRIDGE_REQUIRE_WORKER_AUTH === "true";
}

function validateWorkerAuth(authorization: string | string[] | undefined):
  | { ok: true }
  | { ok: false; status: 401 | 403; error: string } {
  const configuredTokens = getConfiguredWorkerTokens();
  if (!isWorkerAuthRequired()) return { ok: true };
  if (configuredTokens.length === 0) return { ok: false, status: 403, error: "worker_auth_not_configured" };

  const header = Array.isArray(authorization) ? authorization[0] : authorization;
  if (!header) return { ok: false, status: 401, error: "missing_worker_token" };
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match?.[1]?.trim()) return { ok: false, status: 401, error: "invalid_worker_auth_scheme" };

  const candidate = match[1].trim();
  for (const token of configuredTokens) {
    if (constantTimeEqual(candidate, token)) return { ok: true };
  }
  return { ok: false, status: 403, error: "invalid_worker_token" };
}

function constantTimeEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  if (leftBuffer.length !== rightBuffer.length) return false;
  return timingSafeEqual(leftBuffer, rightBuffer);
}

function summarizeRuns(events: StoredEvent[]): RunSummary[] {
  const grouped = new Map<string, StoredEvent[]>();
  for (const event of events) {
    const runId =
      event.correlation?.run_id ?? event.correlation?.session_id ?? "unknown";
    const existing = grouped.get(runId) ?? [];
    existing.push(event);
    grouped.set(runId, existing);
  }

  return [...grouped.entries()]
    .map(([run_id, runEvents]) => {
      const first = runEvents[0]!;
      const last = runEvents.at(-1)!;
      const failed = runEvents.some(
        (event) =>
          event.type === "run.failed" ||
          event.severity === "error" ||
          event.severity === "critical",
      );
      const completed = runEvents.some(
        (event) =>
          event.type === "run.completed" || event.type === "session.completed",
      );
      const status: RunSummary["status"] = failed
        ? "failed"
        : completed
          ? "completed"
          : run_id === "unknown"
            ? "unknown"
            : "running";
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
        tool_call_count: runEvents.filter((event) =>
          event.type.startsWith("tool."),
        ).length,
        active_tool_count: activeToolCount(runEvents),
        failed_tool_count: runEvents.filter(
          (event) => event.type === "tool.failed",
        ).length,
        notification_count: runEvents.filter((event) =>
          event.type.startsWith("notification."),
        ).length,
        first_seen_at: first.receivedAt,
        last_seen_at: last.receivedAt,
        last_event_type: last.type,
        title:
          firstSafeString(runEvents, "title") ??
          firstSafeString(runEvents, "goalFile"),
        lifecycle: safeString(latestPayload.lifecycle),
        branch: firstSafeString(runEvents, "branch"),
        cwd: firstSourceCwd(runEvents),
        goal:
          firstSafeString(runEvents, "goal") ??
          firstSafeString(runEvents, "goalFile"),
        goal_id: firstSafeString(runEvents, "goalId"),
        latest_message_summary: latestMessageSummary(runEvents),
      };
    })
    .sort((a, b) => b.last_seen_at.localeCompare(a.last_seen_at));
}

function notificationForEvent(event: StoredEvent): NotificationMessage {
  return {
    title: `SkyBridge ${event.type}`,
    body: [
      `Source: ${event.source.platform}/${event.source.adapter}`,
      `Run: ${event.correlation?.run_id ?? event.correlation?.session_id ?? "unknown"}`,
      `Severity: ${event.severity}`,
    ].join("\n"),
    priority:
      event.severity === "critical" || event.type === "approval.requested"
        ? "high"
        : "default",
    url: process.env.SKYBRIDGE_PUBLIC_URL,
  };
}

export async function createServer(
  options: CreateServerOptions = {},
): Promise<FastifyInstance> {
  const persistence = resolvePersistence(options);
  const store: EventStore = persistence.dbFile
    ? new SqliteStore({
        dbFile: persistence.dbFile,
        legacyJsonFile: persistence.jsonMigrationFile,
      })
    : new MemoryStore();
  const clients = new Set<{ write: (data: string) => void }>();
  const app = Fastify({ logger: options.logger ?? true });

  await store.load();
  await app.register(cors, { origin: true });
  app.addHook("onClose", async () => {
    await store.close();
  });

  const requireWorkerAuth = async (
    request: { headers: Record<string, string | string[] | undefined> },
    reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
  ) => {
    const auth = validateWorkerAuth(request.headers.authorization);
    if (auth.ok) return;
    return reply.code(auth.status).send({
      ok: false,
      error: auth.error,
      auth_mode: "bearer_token",
    });
  };

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
    event?: StoredEvent,
  ) => {
    const now = new Date().toISOString();
    await store.addNotification({
      id: nanoid(),
      category: event ? categoryForEvent(event) : "manual",
      severity: event?.severity,
      source_event_id: event?.id,
      target: provider,
      provider,
      dedupe_key: event
        ? `${event.type}:${event.correlation?.run_id ?? event.correlation?.session_id ?? event.id}:${provider}`
        : undefined,
      status,
      message,
      retry_count: 0,
      createdAt: now,
      updatedAt: now,
      error,
    });
  };

  const maybeNotify = async (event: StoredEvent) => {
    if (!isNotificationTrigger(event)) return;
    const message = notificationForEvent(event);
    if (!process.env.NTFY_TOPIC_URL) {
      await recordNotification(
        message,
        "placeholder",
        "skipped",
        "NTFY_TOPIC_URL is not configured.",
        event,
      );
      return;
    }
    const result = await sendNtfy(message);
    await recordNotification(
      message,
      result.provider,
      result.status,
      result.error,
      event,
    );
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
    time: new Date().toISOString(),
  });

  app.get("/health", async () => healthResponse());
  app.get("/v1/health", async () => healthResponse());
  app.get("/v1/sources", async () => ({ sources: SOURCE_CAPABILITIES }));
  app.get<{ Querystring: { role?: string } }>(
    "/v1/adapters",
    async (request, reply) => {
      const role = request.query.role;
      if (
        role &&
        ![
          "planner",
          "executor",
          "scm_ci_provider",
          "notification_provider",
          "runtime_provider",
        ].includes(role)
      ) {
        return reply.code(400).send({ ok: false, error: "invalid_role" });
      }
      return {
        adapters: listAdapterCapabilities(
          role as Parameters<typeof listAdapterCapabilities>[0],
        ),
      };
    },
  );

  app.post<{ Body: Record<string, unknown> }>(
    "/v1/workers/register",
    { preHandler: requireWorkerAuth },
    async (request, reply) => {
      const parsed = parseWorkerInput(request.body);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      const existing = store.getWorker(parsed.worker.worker_id);
      const worker: StoredWorker = {
        ...(existing ?? parsed.worker),
        ...parsed.worker,
        created_at: existing?.created_at ?? parsed.worker.created_at,
        updated_at: new Date().toISOString(),
      };
      await store.upsertWorker(worker);
      await addStoredEvent(coreEvent("worker.registered", { worker_id: worker.worker_id, provider: worker.provider }));
      return reply.code(existing ? 200 : 201).send({ ok: true, worker: presentWorker(worker, store) });
    },
  );

  app.post<{
    Params: { workerId: string };
    Body: { status_note?: unknown; load?: unknown; seen_at?: unknown };
  }>("/v1/workers/:workerId/heartbeat", { preHandler: requireWorkerAuth }, async (request, reply) => {
    const workerId = decodeURIComponent(request.params.workerId);
    const worker = store.getWorker(workerId);
    if (!worker) return reply.code(404).send({ ok: false, error: "worker_not_found" });
    const now = new Date().toISOString();
    const seenAt = safeIsoString(request.body?.seen_at) ?? now;
    const heartbeat: StoredWorkerHeartbeat = {
      heartbeat_id: `wh_${nanoid()}`,
      worker_id: workerId,
      seen_at: seenAt,
      status_note: safeString(request.body?.status_note),
      load: typeof request.body?.load === "number" && Number.isFinite(request.body.load) ? request.body.load : undefined,
    };
    await store.addWorkerHeartbeat(heartbeat);
    await store.upsertWorker({ ...worker, updated_at: now });
    await addStoredEvent(coreEvent("worker.heartbeat", { worker_id: workerId }));
    return { ok: true, worker: presentWorker(store.getWorker(workerId)!, store), heartbeat };
  });

  app.get("/v1/workers", async () => ({
    workers: store.listWorkers().map((worker) => presentWorker(worker, store)),
  }));

  app.get<{ Params: { workerId: string } }>(
    "/v1/workers/:workerId",
    async (request, reply) => {
      const worker = store.getWorker(decodeURIComponent(request.params.workerId));
      if (!worker) return reply.code(404).send({ ok: false, error: "worker_not_found" });
      return { worker: presentWorker(worker, store) };
    },
  );

  app.patch<{
    Params: { workerId: string };
    Body: { name?: unknown; enabled?: unknown; labels?: unknown; capabilities?: unknown };
  }>("/v1/workers/:workerId", async (request, reply) => {
    const workerId = decodeURIComponent(request.params.workerId);
    const worker = store.getWorker(workerId);
    if (!worker) return reply.code(404).send({ ok: false, error: "worker_not_found" });
    const updated: StoredWorker = {
      ...worker,
      name: safeString(request.body?.name) ?? worker.name,
      enabled: typeof request.body?.enabled === "boolean" ? request.body.enabled : worker.enabled,
      labels: safeStringArray(request.body?.labels) ?? worker.labels,
      capabilities: safeStringArray(request.body?.capabilities) ?? worker.capabilities,
      updated_at: new Date().toISOString(),
    };
    await store.upsertWorker(updated);
    return { ok: true, worker: presentWorker(updated, store) };
  });

  app.post<{ Body: Record<string, unknown> }>("/v1/projects", async (request, reply) => {
    const parsed = parseProjectInput(request.body);
    if (!parsed.ok) return reply.code(400).send(parsed.response);
    if (store.getProject(parsed.project.project_id))
      return reply.code(409).send({ ok: false, error: "project_exists" });
    await store.upsertProject(parsed.project);
    await addStoredEvent(coreEvent("project.created", { project_id: parsed.project.project_id, name: parsed.project.name }));
    return reply.code(201).send({ ok: true, project: parsed.project });
  });

  app.get("/v1/projects", async () => ({
    projects: mergeProjectViews(store.listProjects(), summarizeProjects(summarizeRuns(store.listEvents()), store.listIterations(1000))),
  }));

  app.get<{ Params: { projectId: string } }>(
    "/v1/projects/:projectId",
    async (request, reply) => {
      const project = store.getProject(decodeURIComponent(request.params.projectId));
      if (!project) return reply.code(404).send({ ok: false, error: "project_not_found" });
      return { project };
    },
  );

  app.get<{ Params: { projectId: string } }>(
    "/v1/projects/:projectId/control",
    async (request, reply) => {
      const project = store.getProject(decodeURIComponent(request.params.projectId));
      if (!project) return reply.code(404).send({ ok: false, error: "project_not_found" });
      return { ok: true, control_state: controlStateForProject(project) };
    },
  );

  app.patch<{ Params: { projectId: string }; Body: Record<string, unknown> }>(
    "/v1/projects/:projectId/control",
    async (request, reply) => {
      const project = store.getProject(decodeURIComponent(request.params.projectId));
      if (!project) return reply.code(404).send({ ok: false, error: "project_not_found" });
      const parsed = parseProjectControlPatch(project.control_state, request.body);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      const updated: StoredProject = {
        ...project,
        control_state: parsed.controlState,
        updated_at: parsed.controlState.updated_at,
      };
      await store.upsertProject(updated);
      await addStoredEvent(coreEvent("project.control_updated", {
        project_id: project.project_id,
        state: parsed.controlState.state,
        stop_requested: parsed.controlState.stop_requested,
        current_worker_id: parsed.controlState.current_worker_id,
        current_task_id: parsed.controlState.current_task_id,
        degraded_reason: parsed.controlState.degraded_reason,
        stop_reason: parsed.controlState.stop_reason,
      }));
      return { ok: true, project: updated, control_state: parsed.controlState };
    },
  );

  app.post<{ Params: { projectId: string }; Body: Record<string, unknown> }>(
    "/v1/projects/:projectId/goals",
    async (request, reply) => {
      const projectId = decodeURIComponent(request.params.projectId);
      if (!store.getProject(projectId)) return reply.code(404).send({ ok: false, error: "project_not_found" });
      const parsed = parseGoalInput(projectId, request.body, store);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      await store.upsertGoal(parsed.goal);
      await addStoredEvent(coreEvent("goal.created", { project_id: projectId, goal_id: parsed.goal.goal_id, title: parsed.goal.title }));
      return reply.code(201).send({ ok: true, goal: withGoalSummary(parsed.goal, store) });
    },
  );

  app.get<{ Params: { projectId: string } }>(
    "/v1/projects/:projectId/goals",
    async (request, reply) => {
      const projectId = decodeURIComponent(request.params.projectId);
      if (!store.getProject(projectId)) return reply.code(404).send({ ok: false, error: "project_not_found" });
      return { goals: store.listGoals(projectId).map((goal) => withGoalSummary(goal, store)) };
    },
  );

  app.get<{ Params: { goalId: string } }>("/v1/goals/:goalId", async (request, reply) => {
    const goal = store.getGoal(decodeURIComponent(request.params.goalId));
    if (!goal) return reply.code(404).send({ ok: false, error: "goal_not_found" });
    return { goal: withGoalSummary(goal, store) };
  });

  app.patch<{ Params: { goalId: string }; Body: Record<string, unknown> }>(
    "/v1/goals/:goalId",
    async (request, reply) => {
      const goal = store.getGoal(decodeURIComponent(request.params.goalId));
      if (!goal) return reply.code(404).send({ ok: false, error: "goal_not_found" });
      const parsed = parseGoalPatch(goal, request.body, store);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      const updated = parsed.goal;
      await store.upsertGoal(updated);
      return { ok: true, goal: withGoalSummary(updated, store) };
    },
  );

  app.post<{ Body: Record<string, unknown> }>("/v1/tasks", async (request, reply) => {
    const parsed = parseTaskInput(request.body, store);
    if (!parsed.ok) return reply.code(parsed.status ?? 400).send(parsed.response);
    await store.upsertTask(parsed.task);
    await recordTaskEvent(parsed.task, "task.created", undefined, "Task created.", addStoredEvent, store);
    return reply.code(201).send({ ok: true, task: withTaskEvents(parsed.task, store) });
  });

  app.get<{ Querystring: { status?: string; project_id?: string; goal_id?: string } }>("/v1/tasks", async (request, reply) => {
    if (request.query.status && !TASK_STATUSES.includes(request.query.status as TaskStatus))
      return reply.code(400).send({ ok: false, error: "invalid_task_status" });
    return {
      tasks: store.listTasks({
        projectId: request.query.project_id,
        goalId: request.query.goal_id,
        status: request.query.status,
      }).map((task) => withTaskEvents(task, store)),
    };
  });

  app.get<{ Params: { projectId: string } }>("/v1/projects/:projectId/tasks", async (request, reply) => {
    const projectId = decodeURIComponent(request.params.projectId);
    if (!store.getProject(projectId)) return reply.code(404).send({ ok: false, error: "project_not_found" });
    return { tasks: store.listTasks({ projectId }).map((task) => withTaskEvents(task, store)) };
  });

  app.get<{ Params: { taskId: string } }>("/v1/tasks/:taskId", async (request, reply) => {
    const task = store.getTask(decodeURIComponent(request.params.taskId));
    if (!task) return reply.code(404).send({ ok: false, error: "task_not_found" });
    return { task: withTaskEvents(task, store) };
  });

  app.post<{ Params: { taskId: string }; Body: { worker_id?: unknown } }>("/v1/tasks/:taskId/claim", { preHandler: requireWorkerAuth }, async (request, reply) => {
    const task = store.getTask(decodeURIComponent(request.params.taskId));
    if (!task) return reply.code(404).send({ ok: false, error: "task_not_found" });
    const workerId = safeString(request.body?.worker_id);
    if (!workerId) return reply.code(400).send({ ok: false, error: "missing_worker_id" });
    const worker = store.getWorker(workerId);
    if (!worker) return reply.code(404).send({ ok: false, error: "worker_not_found" });
    const workerView = presentWorker(worker, store);
    if (!workerView.enabled || workerView.status !== "online")
      return reply.code(409).send({ ok: false, error: "worker_unavailable" });
    if (task.goal_id) {
      const goal = store.getGoal(task.goal_id);
      if (goal && ["archived", "superseded"].includes(goal.status))
        return reply.code(409).send({ ok: false, error: "goal_not_executable" });
    }
    if (!["queued", "failed", "stale"].includes(task.status))
      return reply.code(409).send({ ok: false, error: "task_not_claimable" });
    const now = new Date().toISOString();
    const updated: StoredTask = {
      ...task,
      status: "claimed",
      assigned_worker_id: workerId,
      claim: { claim_id: `claim_${nanoid()}`, task_id: task.task_id, worker_id: workerId, claimed_at: now },
      updated_at: now,
    };
    await store.upsertTask(updated);
    await recordTaskEvent(updated, "task.claimed", workerId, "Task claimed.", addStoredEvent, store);
    return { ok: true, task: withTaskEvents(updated, store) };
  });

  app.post<{ Params: { taskId: string }; Body: { worker_id?: unknown } }>("/v1/tasks/:taskId/start", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return updateTaskTerminal(request.params.taskId, request.body?.worker_id, "running", "task.started", reply, store, addStoredEvent);
  });

  app.post<{ Params: { taskId: string }; Body: Record<string, unknown> }>("/v1/tasks/:taskId/complete", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return finishTask(request.params.taskId, request.body, "completed", "task.completed", reply, store, addStoredEvent);
  });

  app.post<{ Params: { taskId: string }; Body: Record<string, unknown> }>("/v1/tasks/:taskId/fail", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return finishTask(request.params.taskId, request.body, "failed", "task.failed", reply, store, addStoredEvent);
  });

  app.post<{ Params: { taskId: string }; Body: Record<string, unknown> }>("/v1/tasks/:taskId/block", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return finishTask(request.params.taskId, request.body, "blocked", "task.blocked", reply, store, addStoredEvent);
  });

  app.post<{ Params: { taskId: string } }>("/v1/tasks/:taskId/requeue", { preHandler: requireWorkerAuth }, async (request, reply) => {
    const task = store.getTask(decodeURIComponent(request.params.taskId));
    if (!task) return reply.code(404).send({ ok: false, error: "task_not_found" });
    if (task.status === "completed" || task.status === "cancelled")
      return reply.code(409).send({ ok: false, error: "task_not_requeueable" });
    const updated: StoredTask = {
      ...task,
      status: "queued",
      assigned_worker_id: undefined,
      claim: undefined,
      updated_at: new Date().toISOString(),
    };
    await store.upsertTask(updated);
    await recordTaskEvent(updated, "task.requeued", undefined, "Task requeued.", addStoredEvent, store);
    return { ok: true, task: withTaskEvents(updated, store) };
  });

  app.get("/v1/workers/summary", async () => summarizeWorkers(store));
  app.get("/v1/tasks/summary", async () => summarizeTasks(store));

  app.get<{ Querystring: IterationListQuery }>(
    "/v1/iterations",
    async (request, reply) => {
      const parsed = parseIterationListQuery(request.query);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      const { limit, ...filters } = parsed.query;
      return {
        iterations: filterIterations(
          store
            .listIterations()
            .sort((a, b) => b.updated_at.localeCompare(a.updated_at)),
          filters,
        )
          .slice(0, limit)
          .map(({ events: _events, ...iteration }) => iteration),
      };
    },
  );

  app.get<{ Params: { iterationId: string } }>(
    "/v1/iterations/:iterationId",
    async (request, reply) => {
      const iteration = store.getIteration(
        decodeURIComponent(request.params.iterationId),
      );
      if (!iteration)
        return reply
          .code(404)
          .send({ ok: false, error: "iteration_not_found" });
      return { iteration };
    },
  );

  app.post<{ Body: Partial<IterationRun> }>(
    "/v1/iterations",
    async (request, reply) => {
      const parsed = parseIterationInput(request.body);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      await store.upsertIteration({ ...parsed.iteration, events: [] });
      return reply.code(201).send({ ok: true, iteration: parsed.iteration });
    },
  );

  app.patch<{
    Params: { iterationId: string };
    Body: {
      state?: string;
      last_error?: unknown;
      pr_number?: unknown;
      attempts?: unknown;
      checks?: unknown;
    };
  }>("/v1/iterations/:iterationId/state", async (request, reply) => {
    const iterationId = decodeURIComponent(request.params.iterationId);
    const existing = store.getIteration(iterationId);
    if (!existing)
      return reply.code(404).send({ ok: false, error: "iteration_not_found" });
    if (!request.body?.state || !isIterationState(request.body.state)) {
      return reply.code(400).send({ ok: false, error: "invalid_state" });
    }
    const updated: StoredIterationRun = {
      ...existing,
      state: request.body.state,
      attempts:
        typeof request.body.attempts === "number" &&
        Number.isInteger(request.body.attempts)
          ? request.body.attempts
          : existing.attempts,
      pr_number:
        typeof request.body.pr_number === "number" &&
        Number.isInteger(request.body.pr_number)
          ? request.body.pr_number
          : existing.pr_number,
      last_error: safeString(request.body.last_error),
      checks: Array.isArray(request.body.checks)
        ? sanitizeChecks(request.body.checks)
        : existing.checks,
      updated_at: new Date().toISOString(),
    };
    await store.upsertIteration(updated);
    return { ok: true, iteration: updated };
  });

  app.post<{
    Params: { iterationId: string };
    Body: { type?: string; payload?: unknown };
  }>("/v1/iterations/:iterationId/events", async (request, reply) => {
    const iterationId = decodeURIComponent(request.params.iterationId);
    const existing = store.getIteration(iterationId);
    if (!existing)
      return reply.code(404).send({ ok: false, error: "iteration_not_found" });
    const type = safeString(request.body?.type);
    if (!type || !type.startsWith("iteration."))
      return reply
        .code(400)
        .send({ ok: false, error: "invalid_iteration_event" });
    const payload = sanitizeIterationPayload(request.body?.payload);
    if (!payload.ok) return reply.code(400).send(payload.response);
    const event = {
      iteration_id: iterationId,
      type,
      time: new Date().toISOString(),
      payload: payload.payload,
    };
    await store.addIterationEvent(event);
    return reply.code(202).send({ ok: true, event });
  });

  app.get<{ Params: { iterationId: string } }>(
    "/v1/iterations/:iterationId/logs",
    async (request, reply) => {
      const iteration = store.getIteration(
        decodeURIComponent(request.params.iterationId),
      );
      if (!iteration)
        return reply
          .code(404)
          .send({ ok: false, error: "iteration_not_found" });
      return {
        iteration_id: iteration.iteration_id,
        raw_logs_included: false,
        metadata_only: true,
        local_log_hint: `.agent/iterations/${iteration.iteration_id}/`,
      };
    },
  );

  app.get("/v1/supervisor/status", async () =>
    supervisorStatus(store.listIterations(), store.listEvents()),
  );
  app.get("/v1/supervisor/next-action", async () =>
    supervisorNextAction(store.listIterations()),
  );

  app.post("/v1/events", async (request, reply) => {
    const parsed = parseEventPayload(request.body);
    if (!parsed.ok) return reply.code(400).send(parsed.response);

    const event = parsed.event;
    const stored: StoredEvent = {
      ...event,
      id: event.event_id ?? nanoid(),
      event_id: event.event_id ?? undefined,
      receivedAt: new Date().toISOString(),
    };
    await addStoredEvent(stored);
    return reply.code(202).send({ ok: true, id: stored.id });
  });

  app.get<{ Querystring: EventListQuery }>(
    "/v1/events",
    async (request, reply) => {
      const parsed = parseEventListQuery(request.query);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      const { limit, offset, ...filters } = parsed.query;
      const filtered = filterEvents(store.listEvents(), filters);
      const end = Math.max(0, filtered.length - offset);
      const start = Math.max(0, end - limit);
      const events = filtered.slice(start, end);
      return { events };
    },
  );

  app.get<{ Querystring: RunListQuery }>("/v1/runs", async (request, reply) => {
    const parsed = parseRunListQuery(request.query);
    if (!parsed.ok) return reply.code(400).send(parsed.response);
    const { limit, ...filters } = parsed.query;
    return {
      runs: filterRuns(summarizeRuns(store.listEvents()), filters).slice(
        0,
        limit,
      ),
    };
  });

  app.get<{
    Params: { runId: string };
    Querystring: { limit?: string | number };
  }>("/v1/runs/:runId", async (request, reply) => {
    const runId = decodeURIComponent(request.params.runId);
    const limit = parseBoundedInteger(
      request.query.limit,
      "limit",
      1,
      1000,
      200,
    );
    if (!limit.ok) return reply.code(400).send(limit.response);
    const events = store
      .listEvents()
      .filter((event) => runGroupId(event) === runId);
    const [summary] = summarizeRuns(events);
    if (!summary)
      return reply.code(404).send({ ok: false, error: "run_not_found" });
    return { summary, events: events.slice(-limit.value) } satisfies RunDetail;
  });

  app.get<{ Querystring: NotificationListQuery }>(
    "/v1/notifications",
    async (request, reply) => {
      const parsed = parseNotificationListQuery(request.query);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      const { limit, ...filters } = parsed.query;
      return {
        notifications: filterNotifications(
          store.listNotifications(1000),
          filters,
        ).slice(0, limit),
      };
    },
  );

  app.get("/v1/notifications/providers", async () => ({
    providers: notificationProviders(),
  }));
  app.get("/v1/notifications/rules", async () => ({
    rules: notificationRules(),
  }));

  app.get("/v1/nodes", async () => ({
    nodes: summarizeNodes(store.listEvents()),
  }));

  app.get("/v1/summary", async () => {
    const events = store.listEvents();
    const runs = summarizeRuns(events);
    const notifications = store.listNotifications(1000);
    const iterations = store.listIterations(1000);
    const prs = summarizePrs(iterations, events);
    const automerge = summarizeAutoMerge(
      iterations,
      events,
      listAuditRecordsForQuery(store, {}),
    );
    const hermes = summarizeHermes(events, iterations);
    const workers = summarizeWorkers(store);
    const tasks = summarizeTasks(store);
    const activeGoals = store.listGoals().filter((goal) => goal.status === "active");
    const latestFailure = runs.find((run) => run.status === "failed");
    return {
      health: healthResponse(),
      totals: {
        events: events.length,
        runs: runs.length,
        active_runs: runs.filter((run) => run.status === "running").length,
        failed_runs: runs.filter((run) => run.status === "failed").length,
        open_prs: prs.open,
        ci_failed: prs.ci_failed,
        notifications: notifications.length,
        notification_failed: notifications.filter(
          (notification) => notification.status === "failed",
        ).length,
        notification_skipped: notifications.filter(
          (notification) => notification.status === "skipped",
        ).length,
        nodes: summarizeNodes(events).length,
        node_stale: summarizeNodes(events).filter(
          (node) => node.status === "stale",
        ).length,
        workers: workers.total,
        workers_online: workers.online,
        workers_stale: workers.stale,
        workers_offline: workers.offline,
        tasks: tasks.total,
        tasks_queued: tasks.queued,
        tasks_running: tasks.running + tasks.claimed,
        tasks_completed: tasks.completed,
        tasks_failed: tasks.failed,
        tasks_blocked: tasks.blocked,
        active_goals: activeGoals.length,
        automerge_blocked: automerge.blocked,
        attention_items:
          runs.filter((run) => run.status === "failed").length +
          events.filter((event) => event.type === "approval.requested").length +
          notifications.filter(
            (notification) =>
              notification.status === "failed" ||
              notification.status === "skipped",
          ).length,
      },
      latest: {
        ci_state: prs.latest_ci_state,
        automerge_sweep: automerge.latest_sweep,
        iteration: summarizeIterations(iterations).latest,
        hermes_status: hermes.status,
        notification: notifications.at(-1),
        failure: latestFailure,
        active_goal: activeGoals[0],
        latest_task_event: tasks.latest_event,
        next_recommended_action: nextRecommendedAction({
          latestFailure,
          prs,
          automerge,
          hermes,
          notifications,
          workers,
          tasks,
        }),
      },
      recent_failures: runs
        .filter((run) => run.status === "failed")
        .slice(0, 8),
      sources: summarizeSources(events),
    };
  });

  app.get("/v1/iterations/summary", async () =>
    summarizeIterations(store.listIterations(1000)),
  );
  app.get("/v1/prs/summary", async () =>
    summarizePrs(store.listIterations(1000), store.listEvents()),
  );
  app.get("/v1/notifications/summary", async () =>
    summarizeNotifications(
      store.listNotifications(1000),
      notificationProviders(),
      store.listEvents(),
    ),
  );
  app.get("/v1/hermes/summary", async () =>
    summarizeHermes(store.listEvents(), store.listIterations(1000)),
  );
  app.get("/v1/automerge/summary", async () =>
    summarizeAutoMerge(
      store.listIterations(1000),
      store.listEvents(),
      listAuditRecordsForQuery(store, {}),
    ),
  );

  app.get("/v1/metrics", async () =>
    platformMetrics(store.listEvents(), store.listNotifications(1000)),
  );
  app.get<{ Querystring: AuditListQuery }>(
    "/v1/audit",
    async (request, reply) => {
      const parsed = parseAuditListQuery(request.query);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      const { limit, ...filters } = parsed.query;
      return {
        audit: listAuditRecordsForQuery(store, filters).slice(0, limit),
      };
    },
  );
  app.get<{ Querystring: AuditListQuery }>(
    "/v1/audit/export",
    async (request, reply) => {
      const parsed = parseAuditListQuery(request.query);
      if (!parsed.ok) return reply.code(400).send(parsed.response);
      const { limit, ...filters } = parsed.query;
      const audit = listAuditRecordsForQuery(store, filters).slice(0, limit);
      reply
        .header("Content-Type", "application/x-ndjson; charset=utf-8")
        .header("X-SkyBridge-Audit-Export", "fixture-safe-local-jsonl")
        .header("X-SkyBridge-Raw-Payload-Included", "false");
      return (
        audit.map((record) => JSON.stringify(record)).join("\n") +
        (audit.length > 0 ? "\n" : "")
      );
    },
  );

  app.get("/v1/approvals", async () => ({
    approvals: summarizeApprovals(store.listEvents()).filter(
      (item) => item.status === "pending",
    ),
  }));
  app.get<{ Params: { approvalId: string } }>(
    "/v1/approvals/:approvalId",
    async (request, reply) => {
      const approval = summarizeApprovals(store.listEvents()).find(
        (item) =>
          item.approval_id === decodeURIComponent(request.params.approvalId),
      );
      if (!approval)
        return reply.code(404).send({ ok: false, error: "approval_not_found" });
      return { approval };
    },
  );
  app.post<{
    Params: { approvalId: string };
    Body: { decision?: "accepted" | "denied"; actor?: string; reason?: string };
  }>("/v1/approvals/:approvalId/resolve", async (request, reply) => {
    const approvalId = decodeURIComponent(request.params.approvalId);
    const decision = request.body?.decision;
    if (decision !== "accepted" && decision !== "denied")
      return reply
        .code(400)
        .send({ ok: false, error: "decision must be accepted or denied" });
    const existing = summarizeApprovals(store.listEvents()).find(
      (item) => item.approval_id === approvalId,
    );
    if (!existing)
      return reply.code(404).send({ ok: false, error: "approval_not_found" });
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
        remote_execution_enabled: false,
      },
    });
    const stored: StoredEvent = {
      ...event,
      id: event.event_id ?? nanoid(),
      receivedAt: new Date().toISOString(),
    };
    await addStoredEvent(stored);
    return reply
      .code(202)
      .send({ ok: true, approval_id: approvalId, decision });
  });

  app.post<{ Body: NotificationMessage }>(
    "/v1/notifications/send",
    async (request, reply) => {
      const message = request.body;
      if (!message?.title || !message?.body) {
        return reply
          .code(400)
          .send({ ok: false, error: "title and body are required" });
      }
      const result = await sendNtfy(message);
      const provider =
        result.status === "skipped" ? "placeholder" : result.provider;
      await recordNotification(message, provider, result.status, result.error);
      return reply
        .code(202)
        .send({
          ok: true,
          provider,
          status: result.status,
          skipped: result.status === "skipped",
        });
    },
  );

  app.get("/v1/stream", async (_request, reply) => {
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });

    const client = { write: (data: string) => reply.raw.write(data) };
    clients.add(client);
    reply.raw.write(
      `event: connected\ndata: ${JSON.stringify({ ok: true })}\n\n`,
    );
    for (const event of store.listEvents(20)) {
      client.write(
        `event: skybridge.event\ndata: ${JSON.stringify(event)}\n\n`,
      );
    }

    reply.raw.on("close", () => {
      clients.delete(client);
    });
  });

  app.post("/v1/dev/seed", async (_request, reply) => {
    if (process.env.NODE_ENV === "production")
      return reply.code(404).send({ ok: false });
    const event = createEvent({
      type: "run.started",
      source: { platform: "skybridge", adapter: "dev-seed" },
      correlation: { run_id: `seed-${Date.now()}` },
      payload: { message: "Seed event" },
    });
    const stored: StoredEvent = {
      ...event,
      id: nanoid(),
      receivedAt: new Date().toISOString(),
    };
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

type ParsedEventListQuery = Omit<EventListQuery, "limit" | "offset"> & {
  limit: number;
  offset: number;
};

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

type ParsedNotificationListQuery = Omit<NotificationListQuery, "limit"> & {
  limit: number;
};

interface IterationListQuery {
  state?: IterationState;
  project_id?: string;
  branch?: string;
  pr_number?: string | number;
  limit?: string | number;
}

type ParsedIterationListQuery = Omit<
  IterationListQuery,
  "limit" | "pr_number"
> & { limit: number; pr_number?: number };

interface AuditListQuery {
  action?: string;
  actor?: string;
  run_id?: string;
  from?: string;
  to?: string;
  limit?: string | number;
}

type ParsedAuditListQuery = Omit<AuditListQuery, "limit"> & { limit: number };

function filterEvents(
  events: StoredEvent[],
  query: Omit<ParsedEventListQuery, "limit" | "offset">,
): StoredEvent[] {
  const platform = query.platform ?? query.source_platform;
  const adapter = query.adapter ?? query.source_adapter;
  return events.filter((event) => {
    if (query.run_id && runGroupId(event) !== query.run_id) return false;
    if (query.session_id && event.correlation?.session_id !== query.session_id)
      return false;
    if (platform && event.source.platform !== platform) return false;
    if (adapter && event.source.adapter !== adapter) return false;
    if (query.type && event.type !== query.type) return false;
    if (query.severity && event.severity !== query.severity) return false;
    if (query.from && event.time < query.from) return false;
    if (query.to && event.time > query.to) return false;
    return true;
  });
}

function filterRuns(
  runs: RunSummary[],
  query: Omit<ParsedRunListQuery, "limit">,
): RunSummary[] {
  const platform = query.platform ?? query.source_platform;
  const adapter = query.adapter ?? query.source_adapter;
  const goal = query.goal?.toLowerCase();
  return runs.filter((run) => {
    if (platform && run.source_platform !== platform) return false;
    if (adapter && run.source_adapter !== adapter) return false;
    if (query.status && run.status !== query.status) return false;
    if (query.lifecycle && run.lifecycle !== query.lifecycle) return false;
    if (query.branch && run.branch !== query.branch) return false;
    if (
      goal &&
      !`${run.goal ?? ""} ${run.goal_id ?? ""} ${run.title ?? ""}`
        .toLowerCase()
        .includes(goal)
    )
      return false;
    if (query.from && run.last_seen_at < query.from) return false;
    if (query.to && run.first_seen_at > query.to) return false;
    return true;
  });
}

function filterNotifications(
  notifications: StoredNotification[],
  query: Omit<ParsedNotificationListQuery, "limit">,
): StoredNotification[] {
  return notifications.filter((notification) => {
    if (query.status && notification.status !== query.status) return false;
    if (query.provider && notification.provider !== query.provider)
      return false;
    if (query.severity) {
      const priority = notification.message.priority;
      const severityMatch =
        (query.severity === "critical" && priority === "urgent") ||
        (query.severity === "error" && priority === "high") ||
        (query.severity === "warning" && priority === "default") ||
        (query.severity === "info" &&
          (priority === "low" || priority === undefined));
      if (!severityMatch) return false;
    }
    return true;
  });
}

function filterIterations(
  iterations: StoredIterationRun[],
  query: Omit<ParsedIterationListQuery, "limit">,
): StoredIterationRun[] {
  return iterations.filter((iteration) => {
    if (query.state && iteration.state !== query.state) return false;
    if (query.project_id && iteration.project_id !== query.project_id)
      return false;
    if (query.branch && iteration.branch !== query.branch) return false;
    if (
      query.pr_number !== undefined &&
      iteration.pr_number !== query.pr_number
    )
      return false;
    return true;
  });
}

function filterAuditRecords(
  records: StoredAuditRecord[],
  query: Omit<ParsedAuditListQuery, "limit">,
): StoredAuditRecord[] {
  return records.filter((record) => {
    if (query.action && record.action !== query.action) return false;
    if (query.actor && record.actor !== query.actor) return false;
    if (query.run_id && record.run_id !== query.run_id) return false;
    if (query.from && record.time < query.from) return false;
    if (query.to && record.time > query.to) return false;
    return true;
  });
}

function listAuditRecordsForQuery(
  store: EventStore,
  filters: Omit<ParsedAuditListQuery, "limit">,
): StoredAuditRecord[] {
  const durableAudit = store.listAuditRecords(1000);
  const audit =
    durableAudit.length > 0 ? durableAudit : summarizeAudit(store.listEvents());
  return filterAuditRecords(audit, filters);
}

function parseEventListQuery(
  query: EventListQuery,
): ParsedQuery<ParsedEventListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 1000, 200);
  if (!limit.ok) return limit;
  const offset = parseBoundedInteger(query.offset, "offset", 0, 100_000, 0);
  if (!offset.ok) return offset;
  const validation = validateCommonQuery(query);
  if (!validation.ok) return validation;
  return {
    ok: true,
    query: { ...query, limit: limit.value, offset: offset.value },
  };
}

function parseRunListQuery(
  query: RunListQuery,
): ParsedQuery<ParsedRunListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 1000, 200);
  if (!limit.ok) return limit;
  const validation = validateCommonQuery(query);
  if (!validation.ok) return validation;
  if (
    query.status &&
    !["running", "completed", "failed", "unknown"].includes(query.status)
  ) {
    return invalidQuery(
      "status",
      "Expected one of running, completed, failed or unknown.",
    );
  }
  return { ok: true, query: { ...query, limit: limit.value } };
}

function parseNotificationListQuery(
  query: NotificationListQuery,
): ParsedQuery<ParsedNotificationListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 1000, 200);
  if (!limit.ok) return limit;
  if (
    query.status &&
    !["pending", "sent", "skipped", "failed"].includes(query.status)
  ) {
    return invalidQuery(
      "status",
      "Expected one of pending, sent, skipped or failed.",
    );
  }
  if (
    query.provider &&
    ![
      "ntfy",
      "apprise",
      "gotify",
      "bark",
      "wecom",
      "fcm",
      "xiaomi-push",
      "placeholder",
    ].includes(query.provider)
  ) {
    return invalidQuery(
      "provider",
      "Expected a supported notification provider.",
    );
  }
  if (query.severity && !isSeverity(query.severity))
    return invalidQuery("severity", "Expected a SkyBridge severity.");
  return { ok: true, query: { ...query, limit: limit.value } };
}

function parseIterationListQuery(
  query: IterationListQuery,
): ParsedQuery<ParsedIterationListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 200, 50);
  if (!limit.ok) return limit;
  if (query.state && !isIterationState(query.state))
    return invalidQuery("state", "Expected a valid iteration state.");
  if (query.project_id && !safeString(query.project_id))
    return invalidQuery("project_id", "Expected a bounded project id.");
  if (query.branch && !safeString(query.branch))
    return invalidQuery("branch", "Expected a bounded branch.");
  const prNumber =
    query.pr_number === undefined
      ? undefined
      : parseBoundedInteger(query.pr_number, "pr_number", 1, 999999999, 1);
  if (prNumber && !prNumber.ok) return prNumber;
  return {
    ok: true,
    query: { ...query, pr_number: prNumber?.value, limit: limit.value },
  };
}

function parseAuditListQuery(
  query: AuditListQuery,
): ParsedQuery<ParsedAuditListQuery> {
  const limit = parseBoundedInteger(query.limit, "limit", 1, 1000, 100);
  if (!limit.ok) return limit;
  if (query.from && !isIsoDate(query.from))
    return invalidQuery("from", "Expected an ISO timestamp.");
  if (query.to && !isIsoDate(query.to))
    return invalidQuery("to", "Expected an ISO timestamp.");
  if (query.from && query.to && query.from > query.to)
    return invalidQuery(
      "from",
      "Expected from to be earlier than or equal to to.",
    );
  return { ok: true, query: { ...query, limit: limit.value } };
}

function validateCommonQuery(
  query: EventListQuery | RunListQuery,
): ParsedQuery<{}> {
  const platform = query.platform ?? query.source_platform;
  if (platform && !isPlatform(platform))
    return invalidQuery(
      "platform",
      "Expected one of codex, opencode, hermes, skybridge or custom.",
    );
  if ("severity" in query && query.severity && !isSeverity(query.severity))
    return invalidQuery("severity", "Expected a SkyBridge severity.");
  if ("type" in query && query.type && !isEventType(query.type))
    return invalidQuery("type", "Expected a SkyBridge event type.");
  if (query.from && !isIsoDate(query.from))
    return invalidQuery("from", "Expected an ISO timestamp.");
  if (query.to && !isIsoDate(query.to))
    return invalidQuery("to", "Expected an ISO timestamp.");
  if (query.from && query.to && query.from > query.to)
    return invalidQuery(
      "from",
      "Expected from to be earlier than or equal to to.",
    );
  return { ok: true, query: {} };
}

type ParsedQuery<T> =
  | { ok: true; query: T }
  | { ok: false; response: QueryErrorResponse };
type ParsedNumber =
  | { ok: true; value: number }
  | { ok: false; response: QueryErrorResponse };

function parseBoundedInteger(
  input: string | number | undefined,
  field: string,
  min: number,
  max: number,
  fallback: number,
): ParsedNumber {
  if (input === undefined || input === "") return { ok: true, value: fallback };
  const parsed = typeof input === "number" ? input : Number(input);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    return invalidQuery(field, `Expected an integer from ${min} to ${max}.`);
  }
  return { ok: true, value: parsed };
}

function invalidQuery(
  field: string,
  message: string,
): { ok: false; response: QueryErrorResponse } {
  return {
    ok: false,
    response: {
      ok: false,
      error: "invalid_query",
      issues: [{ field, message }],
    },
  };
}

interface QueryErrorResponse {
  ok: false;
  error: "invalid_query";
  issues: Array<{ field: string; message: string }>;
}

function isIsoDate(input: string): boolean {
  return (
    !Number.isNaN(Date.parse(input)) && new Date(input).toISOString() === input
  );
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
    "notification.failed",
  ].includes(input);
}

function summarizeSources(events: StoredEvent[]) {
  const sources = new Map<
    string,
    {
      platform: string;
      adapter: string;
      event_count: number;
      latest_event_at: string;
    }
  >();
  for (const event of events) {
    const key = `${event.source.platform}/${event.source.adapter}`;
    const existing = sources.get(key);
    if (!existing) {
      sources.set(key, {
        platform: event.source.platform,
        adapter: event.source.adapter,
        event_count: 1,
        latest_event_at: event.time,
      });
      continue;
    }
    existing.event_count += 1;
    if (event.time > existing.latest_event_at)
      existing.latest_event_at = event.time;
  }
  return [...sources.values()].sort((a, b) =>
    b.latest_event_at.localeCompare(a.latest_event_at),
  );
}

function notificationProviders() {
  return [
    providerStatus(
      "ntfy",
      Boolean(process.env.NTFY_TOPIC_URL),
      "NTFY_TOPIC_URL",
    ),
    providerStatus("apprise", Boolean(process.env.APPRISE_URL), "APPRISE_URL"),
    providerStatus("gotify", Boolean(process.env.GOTIFY_URL), "GOTIFY_URL"),
    providerStatus("bark", Boolean(process.env.BARK_URL), "BARK_URL"),
    providerStatus(
      "wecom",
      Boolean(process.env.WECOM_WEBHOOK_URL),
      "WECOM_WEBHOOK_URL",
    ),
    providerStatus(
      "fcm",
      Boolean(process.env.FCM_SERVER_KEY),
      "FCM_SERVER_KEY",
    ),
    providerStatus(
      "xiaomi-push",
      Boolean(process.env.XIAOMI_PUSH_SECRET),
      "XIAOMI_PUSH_SECRET",
    ),
  ];
}

function providerStatus(
  provider: string,
  configured: boolean,
  required_env: string,
) {
  return {
    provider,
    configured,
    status: configured ? "available" : "skipped",
    required_env,
    credential_values_exposed: false,
  };
}

function notificationRules() {
  return [
    {
      id: "critical-failures",
      event_type_patterns: [
        "run.failed",
        "approval.requested",
        "notification.requested",
      ],
      severity_threshold: "warning",
      quiet_hours: "placeholder",
      providers: ["ntfy"],
      dedupe: true,
    },
  ];
}

function categoryForEvent(event: StoredEvent): string {
  if (event.type.startsWith("approval.")) return "approval";
  if (event.type.startsWith("notification.")) return "notification";
  if (event.type.startsWith("run.")) return "run";
  return "event";
}

function summarizeNodes(events: StoredEvent[]) {
  const nodes = new Map<
    string,
    {
      node_id: string;
      host?: string;
      labels: string[];
      capabilities: string[];
      sidecar_version?: string;
      last_seen: string;
      status: "connected" | "stale" | "disconnected";
      event_count: number;
    }
  >();
  for (const event of events.filter((item) => item.type.startsWith("node."))) {
    const nodeId =
      event.source.node_id ??
      safeString(event.payload.node_id) ??
      event.correlation?.session_id ??
      "unknown-node";
    const existing = nodes.get(nodeId) ?? {
      node_id: nodeId,
      labels: [],
      capabilities: [],
      last_seen: event.time,
      status: "connected" as const,
      event_count: 0,
    };
    existing.event_count += 1;
    existing.last_seen =
      event.time > existing.last_seen ? event.time : existing.last_seen;
    existing.host = safeString(event.payload.host) ?? existing.host;
    existing.sidecar_version =
      safeString(event.payload.sidecar_version) ?? existing.sidecar_version;
    existing.labels = safeStringArray(event.payload.labels) ?? existing.labels;
    existing.capabilities =
      safeStringArray(event.payload.capabilities) ?? existing.capabilities;
    existing.status =
      event.type === "node.disconnected" ? "disconnected" : "connected";
    nodes.set(nodeId, existing);
  }
  const staleBefore = Date.now() - 5 * 60 * 1000;
  return [...nodes.values()]
    .map((node) => ({
      ...node,
      status:
        node.status === "connected" && Date.parse(node.last_seen) < staleBefore
          ? "stale"
          : node.status,
    }))
    .sort((a, b) => b.last_seen.localeCompare(a.last_seen));
}

function platformMetrics(
  events: StoredEvent[],
  notifications: StoredNotification[],
) {
  const runs = summarizeRuns(events);
  const nodes = summarizeNodes(events);
  return {
    total_events: events.length,
    runs_by_status: countBy(runs, (run) => run.status),
    runs_by_source: countBy(runs, (run) => run.source_platform),
    notifications_by_status: countBy(
      notifications,
      (notification) => notification.status,
    ),
    notifications_by_severity: countBy(
      notifications,
      (notification) => notification.severity ?? "unknown",
    ),
    node_status_counts: countBy(nodes, (node) => node.status),
    recent_failures: runs.filter((run) => run.status === "failed").slice(0, 10),
  };
}

function summarizeProjects(
  runs: RunSummary[],
  iterations: StoredIterationRun[],
) {
  const projects = new Map<
    string,
    {
      project_id: string;
      run_count: number;
      active_runs: number;
      failed_runs: number;
      iteration_count: number;
      latest_activity_at?: string;
    }
  >();

  for (const run of runs) {
    const projectId =
      run.source_platform === "skybridge"
        ? "skybridge-agent-hub"
        : run.source_platform;
    const project = projects.get(projectId) ?? {
      project_id: projectId,
      run_count: 0,
      active_runs: 0,
      failed_runs: 0,
      iteration_count: 0,
    };
    project.run_count += 1;
    if (run.status === "running") project.active_runs += 1;
    if (run.status === "failed") project.failed_runs += 1;
    project.latest_activity_at = maxIso(
      project.latest_activity_at,
      run.last_seen_at,
    );
    projects.set(projectId, project);
  }

  for (const iteration of iterations) {
    const project = projects.get(iteration.project_id) ?? {
      project_id: iteration.project_id,
      run_count: 0,
      active_runs: 0,
      failed_runs: 0,
      iteration_count: 0,
    };
    project.iteration_count += 1;
    project.latest_activity_at = maxIso(
      project.latest_activity_at,
      iteration.updated_at,
    );
    projects.set(iteration.project_id, project);
  }

  return [...projects.values()].sort((a, b) =>
    (b.latest_activity_at ?? "").localeCompare(a.latest_activity_at ?? ""),
  );
}

function summarizeIterations(iterations: StoredIterationRun[]) {
  const sorted = [...iterations].sort((a, b) =>
    b.updated_at.localeCompare(a.updated_at),
  );
  return {
    total: sorted.length,
    active: sorted.filter(
      (iteration) => !["merged", "blocked", "failed"].includes(iteration.state),
    ).length,
    blocked: sorted.filter((iteration) => iteration.state === "blocked").length,
    failed: sorted.filter(
      (iteration) =>
        iteration.state === "failed" || iteration.state === "ci_failed",
    ).length,
    repair_attempts: sorted.reduce(
      (sum, iteration) => sum + iteration.attempts,
      0,
    ),
    latest: sorted[0],
    recent: sorted.slice(0, 20).map((iteration) => ({
      ...iteration,
      blocked_reason: iteration.last_error,
      repair_attempts: iteration.attempts,
      raw_logs_included: false,
    })),
  };
}

function summarizePrs(iterations: StoredIterationRun[], events: StoredEvent[]) {
  const prs = new Map<
    number,
    {
      pr_number: number;
      branch?: string;
      repo?: string;
      state: "open" | "merged" | "blocked" | "unknown";
      ci_state: string;
      required_checks: Array<{
        name: string;
        status: string;
        summary?: string;
      }>;
      eligibility: "eligible" | "blocked" | "pending" | "unknown";
      risk: "low" | "needs_review" | "blocked" | "unknown";
      reasons: string[];
      updated_at: string;
    }
  >();

  for (const iteration of iterations.filter((item) => item.pr_number)) {
    const ciState = iteration.state.startsWith("ci_")
      ? iteration.state
      : iteration.checks.some((check) => check.status === "failed")
        ? "ci_failed"
        : iteration.checks.some((check) => check.status === "pending")
          ? "ci_pending"
          : iteration.checks.length > 0
            ? "ci_green"
            : "unknown";
    const risk = riskFromIteration(iteration);
    const reasons = [
      iteration.last_error,
      ...iteration.checks
        .filter((check) => check.status === "failed")
        .map((check) => `${check.name}: ${check.summary ?? "failed"}`),
    ].filter((reason): reason is string => Boolean(reason));
    prs.set(iteration.pr_number!, {
      pr_number: iteration.pr_number!,
      branch: iteration.branch,
      repo: iteration.repo,
      state:
        iteration.state === "merged"
          ? "merged"
          : iteration.state === "blocked" || iteration.state === "failed"
            ? "blocked"
            : "open",
      ci_state: ciState,
      required_checks: iteration.checks.map((check) => ({
        name: check.name,
        status: check.status,
        summary: check.summary,
      })),
      eligibility: eligibilityFromIteration(iteration, risk),
      risk,
      reasons,
      updated_at: iteration.updated_at,
    });
  }

  for (const event of events) {
    const prNumber = numberFromPayload(
      event.payload.pr_number ?? event.payload.prNumber,
    );
    if (!prNumber || prs.has(prNumber)) continue;
    prs.set(prNumber, {
      pr_number: prNumber,
      branch: safeString(event.payload.branch),
      state: event.type === "iteration.merged" ? "merged" : "unknown",
      ci_state: safeString(event.payload.ci_state) ?? "unknown",
      required_checks: safeChecksFromPayload(event.payload.required_checks),
      eligibility: safeEligibility(event.payload.eligibility),
      risk: safeRisk(event.payload.risk),
      reasons: safeStringArray(event.payload.reasons) ?? [],
      updated_at: event.time,
    });
  }

  const items = [...prs.values()].sort((a, b) =>
    b.updated_at.localeCompare(a.updated_at),
  );
  return {
    total: items.length,
    open: items.filter((pr) => pr.state === "open").length,
    merged: items.filter((pr) => pr.state === "merged").length,
    blocked: items.filter(
      (pr) => pr.eligibility === "blocked" || pr.state === "blocked",
    ).length,
    eligible: items.filter((pr) => pr.eligibility === "eligible").length,
    ci_failed: items.filter((pr) => pr.ci_state === "ci_failed").length,
    latest_ci_state: items[0]?.ci_state ?? "unknown",
    prs: items,
  };
}

function summarizeNotifications(
  notifications: StoredNotification[],
  providers: ReturnType<typeof notificationProviders>,
  events: StoredEvent[] = [],
) {
  const sorted = [...notifications].sort((a, b) =>
    b.createdAt.localeCompare(a.createdAt),
  );
  const notificationEvents = events.filter((event) =>
    event.type.startsWith("notification."),
  );
  return {
    total: notifications.length + notificationEvents.length,
    sent:
      notifications.filter((notification) => notification.status === "sent")
        .length +
      notificationEvents.filter((event) => event.type === "notification.sent")
        .length,
    skipped:
      notifications.filter((notification) => notification.status === "skipped")
        .length +
      notificationEvents.filter(
        (event) => event.type === "notification.skipped",
      ).length,
    failed:
      notifications.filter((notification) => notification.status === "failed")
        .length +
      notificationEvents.filter((event) => event.type === "notification.failed")
        .length,
    pending: notifications.filter(
      (notification) => notification.status === "pending",
    ).length,
    by_severity: countBy(
      notifications,
      (notification) => notification.severity ?? "unknown",
    ),
    providers,
    bootstrap_fallback: {
      status: "available-manual",
      script: "scripts/powershell/notify-bootstrap.ps1",
      real_send_requires_explicit_send: true,
    },
    latest: sorted[0],
    recent: sorted.slice(0, 20),
  };
}

function summarizeHermes(
  events: StoredEvent[],
  iterations: StoredIterationRun[],
) {
  const hermesEvents = events.filter(
    (event) =>
      event.source.platform === "hermes" ||
      event.source.adapter.toLowerCase().includes("hermes"),
  );
  const latest = hermesEvents.at(-1);
  const failed = [...hermesEvents]
    .reverse()
    .find(
      (event) =>
        event.severity === "error" ||
        event.severity === "critical" ||
        event.type === "run.failed" ||
        event.type === "agent.error",
    );
  const lastSafeRun = [...hermesEvents]
    .reverse()
    .find(
      (event) => event.type === "run.completed" || event.type === "agent.idle",
    );
  const nightly = [...events]
    .reverse()
    .find(
      (event) =>
        event.source.adapter.includes("nightly") ||
        safeString(event.payload.report_type) === "nightly",
    );
  const sweep = [...events]
    .reverse()
    .find(
      (event) =>
        event.source.adapter.includes("auto-merge") ||
        safeString(event.payload.mode)?.includes("Sweep"),
    );
  const status = failed ? "degraded" : latest ? "available" : "placeholder";
  return {
    status,
    tunnel: {
      status:
        safeString(latest?.payload.tunnel_status) ??
        (latest ? "observed" : "unknown"),
      public_exposure: false,
    },
    api: {
      health:
        safeString(latest?.payload.health) ??
        safeString(latest?.payload.api_health) ??
        status,
      base_publicly_exposed: false,
    },
    capabilities: safeStringArray(latest?.payload.capabilities) ?? [
      "health",
      "capabilities",
      "safe-run-smoke",
    ],
    last_safe_run: lastSafeRun
      ? {
          event_id: lastSafeRun.id,
          run_id: lastSafeRun.correlation?.run_id,
          time: lastSafeRun.time,
        }
      : undefined,
    nightly_report: nightly
      ? {
          event_id: nightly.id,
          time: nightly.time,
          summary: safeString(nightly.payload.summary) ?? nightly.type,
        }
      : undefined,
    sweep_dry_run: sweep
      ? {
          event_id: sweep.id,
          time: sweep.time,
          summary:
            safeString(sweep.payload.summary) ??
            safeString(sweep.payload.mode) ??
            sweep.type,
        }
      : undefined,
    degraded_reason: failed
      ? (safeString(failed.payload.summary) ??
        safeString(failed.payload.reason) ??
        failed.type)
      : undefined,
    related_iterations: iterations
      .filter(
        (iteration) =>
          iteration.branch.toLowerCase().includes("hermes") ||
          iteration.goal_id?.toLowerCase().includes("hermes"),
      )
      .slice(0, 5),
  };
}

function summarizeAutoMerge(
  iterations: StoredIterationRun[],
  events: StoredEvent[],
  audit: StoredAuditRecord[],
) {
  const sweepEvents = events.filter(
    (event) =>
      event.source.adapter.includes("auto-merge") ||
      safeString(event.payload.mode)?.includes("Sweep") ||
      safeString(event.payload.sweep_id),
  );
  const latestSweep = sweepEvents.at(-1);
  const prSummary = summarizePrs(iterations, events);
  return {
    enabled_by_default: false,
    dry_run_default: true,
    total_prs: prSummary.total,
    eligible: prSummary.eligible,
    blocked: prSummary.blocked,
    pending: prSummary.prs.filter((pr) => pr.eligibility === "pending").length,
    merged_history: audit
      .filter(
        (record) =>
          record.action === "iteration.merged" || record.action === "pr.merged",
      )
      .slice(0, 20),
    latest_sweep: latestSweep
      ? {
          event_id: latestSweep.id,
          time: latestSweep.time,
          mode: safeString(latestSweep.payload.mode) ?? "dry-run",
          dry_run: latestSweep.payload.dry_run !== false,
          summary: safeString(latestSweep.payload.summary),
          eligible: numberFromPayload(latestSweep.payload.eligible),
          blocked: numberFromPayload(latestSweep.payload.blocked),
        }
      : undefined,
    decisions: prSummary.prs.map((pr) => ({
      pr_number: pr.pr_number,
      eligibility: pr.eligibility,
      risk: pr.risk,
      reasons: pr.reasons,
      required_checks: pr.required_checks,
    })),
  };
}

function nextRecommendedAction(input: {
  latestFailure?: RunSummary;
  prs: ReturnType<typeof summarizePrs>;
  automerge: ReturnType<typeof summarizeAutoMerge>;
  hermes: ReturnType<typeof summarizeHermes>;
  notifications: StoredNotification[];
  workers?: ReturnType<typeof summarizeWorkers>;
  tasks?: ReturnType<typeof summarizeTasks>;
}) {
  if (input.latestFailure)
    return `Inspect failed run ${input.latestFailure.run_id}.`;
  if (input.tasks && input.tasks.blocked > 0)
    return "Open task queue and review blocked tasks.";
  if (input.tasks && input.tasks.queued > 0 && (!input.workers || input.workers.online === 0))
    return "Bring a worker online before claiming queued tasks.";
  if (input.tasks && input.tasks.queued > 0)
    return "Claim the next queued task with an online worker.";
  if (input.prs.ci_failed > 0) return "Open PR/CI and repair failed checks.";
  if (input.automerge.blocked > 0)
    return "Review blocked auto-merge decisions.";
  if (input.hermes.status === "degraded")
    return "Open Hermes adapter detail and check degraded reason.";
  if (
    input.notifications.some((notification) => notification.status === "failed")
  )
    return "Open notifications and repair provider configuration.";
  if (input.prs.eligible > 0)
    return "Review eligible low-risk PRs before enabling auto-merge.";
  return "Continue observing; no immediate operator action.";
}

function summarizeAudit(events: StoredEvent[]) {
  return events
    .filter(
      (event) =>
        event.type.startsWith("approval.") ||
        event.type.startsWith("node.") ||
        event.type.startsWith("notification.") ||
        event.type === "run.failed",
    )
    .map((event) => auditRecordForEvent(event))
    .filter((record): record is StoredAuditRecord => Boolean(record))
    .sort((a, b) => b.time.localeCompare(a.time));
}

function auditRecordForEvent(
  event: StoredEvent,
): StoredAuditRecord | undefined {
  if (
    !event.type.startsWith("approval.") &&
    !event.type.startsWith("node.") &&
    !event.type.startsWith("notification.") &&
    event.type !== "run.failed"
  ) {
    return undefined;
  }

  return {
    audit_id: `audit_${event.id}`,
    time: event.time,
    action: event.type,
    actor:
      safeString(event.payload.actor) ??
      safeString(event.payload.operator) ??
      event.source.agent_id ??
      "system",
    source_adapter: `${event.source.platform}/${event.source.adapter}`,
    run_id: event.correlation?.run_id,
    session_id: event.correlation?.session_id,
    safety_decision: safetyDecisionForEvent(event),
    immutable_event_id: event.id,
    redaction_policy_version: "packages/event-schema/src/redaction-rules.json",
    raw_payload_included: false,
  };
}

function summarizeApprovals(events: StoredEvent[]) {
  const approvals = new Map<
    string,
    {
      approval_id: string;
      run_id?: string;
      session_id?: string;
      status: "pending" | "accepted" | "denied" | "expired";
      title?: string;
      requested_at: string;
      resolved_at?: string;
      source: string;
    }
  >();
  for (const event of events.filter((item) =>
    item.type.startsWith("approval."),
  )) {
    const approvalId =
      safeString(event.payload.approval_id) ??
      event.correlation?.tool_call_id ??
      event.id;
    const existing = approvals.get(approvalId) ?? {
      approval_id: approvalId,
      run_id: event.correlation?.run_id,
      session_id: event.correlation?.session_id,
      status: "pending" as const,
      title:
        safeString(event.payload.title) ??
        safeString(event.payload.permission) ??
        event.type,
      requested_at: event.time,
      source: `${event.source.platform}/${event.source.adapter}`,
    };
    if (event.type === "approval.resolved") existing.status = "accepted";
    if (event.type === "approval.denied") existing.status = "denied";
    if (event.type === "approval.expired") existing.status = "expired";
    if (event.type !== "approval.requested") existing.resolved_at = event.time;
    approvals.set(approvalId, existing);
  }
  return [...approvals.values()].sort((a, b) =>
    b.requested_at.localeCompare(a.requested_at),
  );
}

function safetyDecisionForEvent(event: StoredEvent): string {
  if (event.type === "approval.denied") return "operator_denied";
  if (event.type === "approval.expired") return "approval_expired";
  if (event.type === "approval.resolved")
    return "operator_accepted_local_record_only";
  if (event.type === "approval.requested")
    return "approval_required_remote_execution_disabled";
  if (event.type.startsWith("node.")) return "node_telemetry_only";
  if (event.type.startsWith("notification."))
    return "notification_metadata_only";
  if (event.type === "run.failed") return "failure_observed";
  return "recorded";
}

function countBy<T>(
  items: T[],
  key: (item: T) => string,
): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const item of items) counts[key(item)] = (counts[key(item)] ?? 0) + 1;
  return counts;
}

function maxIso(current: string | undefined, next: string): string {
  return current && current > next ? current : next;
}

function numberFromPayload(input: unknown): number | undefined {
  if (typeof input === "number" && Number.isFinite(input)) return input;
  if (typeof input === "string" && /^\d+$/.test(input)) return Number(input);
  return undefined;
}

function safeChecksFromPayload(
  input: unknown,
): Array<{ name: string; status: string; summary?: string }> {
  if (!Array.isArray(input)) return [];
  return input.slice(0, 20).map((item) => {
    const record =
      item && typeof item === "object" ? (item as Record<string, unknown>) : {};
    return {
      name: safeString(record.name) ?? "check",
      status: safeString(record.status) ?? "unknown",
      summary: safeString(record.summary),
    };
  });
}

function safeEligibility(
  input: unknown,
): "eligible" | "blocked" | "pending" | "unknown" {
  return input === "eligible" || input === "blocked" || input === "pending"
    ? input
    : "unknown";
}

function safeRisk(
  input: unknown,
): "low" | "needs_review" | "blocked" | "unknown" {
  return input === "low" || input === "needs_review" || input === "blocked"
    ? input
    : "unknown";
}

function riskFromIteration(
  iteration: StoredIterationRun,
): "low" | "needs_review" | "blocked" | "unknown" {
  if (
    iteration.last_error?.toLowerCase().includes("high-risk") ||
    iteration.state === "blocked"
  )
    return "blocked";
  if (iteration.last_error) return "needs_review";
  if (iteration.checks.length > 0) return "low";
  return "unknown";
}

function eligibilityFromIteration(
  iteration: StoredIterationRun,
  risk: "low" | "needs_review" | "blocked" | "unknown",
): "eligible" | "blocked" | "pending" | "unknown" {
  if (
    risk === "blocked" ||
    iteration.state === "blocked" ||
    iteration.state === "failed" ||
    iteration.checks.some((check) => check.status === "failed")
  )
    return "blocked";
  if (iteration.state === "ci_green" && risk === "low") return "eligible";
  if (
    iteration.state === "ci_pending" ||
    iteration.checks.some((check) => check.status === "pending")
  )
    return "pending";
  return "unknown";
}

function runGroupId(event: StoredEvent): string {
  return (
    event.correlation?.run_id ?? event.correlation?.session_id ?? "unknown"
  );
}

function latestObjectPayload(events: StoredEvent[]): Record<string, unknown> {
  return events.at(-1)?.payload ?? {};
}

function firstSafeString(
  events: StoredEvent[],
  key: string,
): string | undefined {
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
    if (event.type === "tool.completed" || event.type === "tool.failed")
      active.delete(id);
  }
  return active.size;
}

function latestMessageSummary(events: StoredEvent[]): string | undefined {
  for (const event of [...events].reverse()) {
    const direct =
      safeString(event.payload.summary) ?? safeString(event.payload.message);
    if (direct) return direct;
    const messageSummary = event.payload.message_summary;
    if (messageSummary && typeof messageSummary === "object") {
      const preview = safeString(
        (messageSummary as Record<string, unknown>).preview,
      );
      if (preview) return preview;
    }
  }
  return undefined;
}

function safeString(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 && input.length <= 200
    ? input
    : undefined;
}

function safeStringArray(input: unknown): string[] | undefined {
  return Array.isArray(input) &&
    input.every((item) => typeof item === "string" && item.length <= 80)
    ? input
    : undefined;
}

function resolvePersistence(options: CreateServerOptions): {
  dbFile?: string;
  jsonMigrationFile?: string;
} {
  if (options.dbFile === false || options.dataFile === false) return {};

  const repositoryRoot = findRepositoryRoot(
    dirname(fileURLToPath(import.meta.url)),
  );
  const legacyEnvFile = process.env.SKYBRIDGE_DATA_FILE;
  const defaultJsonFile = join(repositoryRoot, ".data", "skybridge-store.json");
  const jsonMigrationFile =
    options.jsonMigrationFile === false
      ? undefined
      : (options.jsonMigrationFile ?? legacyEnvFile ?? defaultJsonFile);

  const dbFile =
    options.dbFile ??
    process.env.SKYBRIDGE_DB_FILE ??
    sqlitePathFromLegacy(options.dataFile || legacyEnvFile) ??
    join(repositoryRoot, ".data", "skybridge.sqlite");

  return { dbFile, jsonMigrationFile };
}

function parseEventPayload(
  input: unknown,
):
  | { ok: true; event: SkyBridgeEvent }
  | { ok: false; response: ValidationErrorResponse } {
  try {
    const payloadBytes = Buffer.byteLength(
      JSON.stringify(input ?? null),
      "utf8",
    );
    if (payloadBytes > SharedRedactionRules.maxPayloadBytes) {
      return {
        ok: false,
        response: {
          ok: false,
          error: "invalid_event",
          message: "Event payload exceeded the safe size limit.",
          issues: [
            {
              path: "",
              code: "too_big",
              message: `Payload must be <= ${SharedRedactionRules.maxPayloadBytes} bytes.`,
            },
          ],
        },
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
          message: issue.message,
        })),
      },
    };
  }
}

function coreEvent(type: SkyBridgeEventType, payload: Record<string, unknown>): StoredEvent {
  const event = createEvent({
    type,
    source: { platform: "skybridge", adapter: "core-api" },
    payload,
  });
  return {
    ...event,
    id: event.event_id ?? nanoid(),
    event_id: event.event_id ?? undefined,
    receivedAt: new Date().toISOString(),
  };
}

function parseProjectInput(input: Record<string, unknown> | undefined):
  | { ok: true; project: StoredProject }
  | { ok: false; response: QueryErrorResponse } {
  const now = new Date().toISOString();
  if (!input || typeof input !== "object") return invalidQuery("body", "Expected a project object.");
  const name = safeString(input.name);
  if (!name) return invalidQuery("name", "Expected a bounded project name.");
  const id = safeString(input.project_id) ?? slugId("project", name);
  const status = safeString(input.status) ?? "active";
  if (!PROJECT_STATUSES.includes(status as StoredProject["status"]))
    return invalidQuery("status", "Expected a valid project status.");
  return {
    ok: true,
    project: {
      project_id: id,
      name,
      repo: safeString(input.repo),
      description: safeString(input.description),
      status: status as StoredProject["status"],
      created_at: now,
      updated_at: now,
    },
  };
}

function controlStateForProject(project: StoredProject): ProjectControlState {
  return project.control_state ?? {
    state: "stopped",
    stop_requested: false,
    loop_task_count: 0,
    updated_at: project.updated_at,
  };
}

function parseProjectControlPatch(
  existing: ProjectControlState | undefined,
  input: Record<string, unknown> | undefined,
):
  | { ok: true; controlState: ProjectControlState }
  | { ok: false; response: QueryErrorResponse } {
  const now = new Date().toISOString();
  const current = existing ?? {
    state: "stopped" as const,
    stop_requested: false,
    loop_task_count: 0,
    updated_at: now,
  };
  if (!input || typeof input !== "object")
    return invalidQuery("body", "Expected a project control patch object.");
  const state = safeString(input.state);
  if (state && !["running", "paused", "stopped"].includes(state))
    return invalidQuery("state", "Expected running, paused or stopped.");
  const controlState: ProjectControlState = {
    ...current,
    state: (state as ProjectControlState["state"] | undefined) ?? current.state,
    stop_requested:
      typeof input.stop_requested === "boolean"
        ? input.stop_requested
        : current.stop_requested,
    max_rounds: safeOptionalInteger(input.max_rounds, 1, 1000) ?? current.max_rounds,
    max_tasks: safeOptionalInteger(input.max_tasks, 1, 1000) ?? current.max_tasks,
    current_worker_id: safeNullableString(input.current_worker_id, current.current_worker_id),
    current_task_id: safeNullableString(input.current_task_id, current.current_task_id),
    loop_task_count: safeOptionalInteger(input.loop_task_count, 0, 100000) ?? current.loop_task_count,
    degraded_reason: safeNullableString(input.degraded_reason, current.degraded_reason),
    idle_since: safeNullableIsoString(input.idle_since, current.idle_since),
    stop_reason: safeNullableString(input.stop_reason, current.stop_reason),
    last_error: safeNullableString(input.last_error, current.last_error),
    last_notification: safeNullableString(input.last_notification, current.last_notification),
    last_heartbeat: safeNullableIsoString(input.last_heartbeat, current.last_heartbeat),
    updated_at: now,
  };
  return { ok: true, controlState };
}

function safeOptionalInteger(input: unknown, min: number, max: number): number | undefined {
  if (input === undefined || input === null) return undefined;
  if (typeof input !== "number" || !Number.isInteger(input)) return undefined;
  if (input < min || input > max) return undefined;
  return input;
}

function safeNullableString(input: unknown, fallback: string | undefined): string | undefined {
  if (input === null) return undefined;
  return safeString(input) ?? fallback;
}

function safeNullableIsoString(input: unknown, fallback: string | undefined): string | undefined {
  if (input === null) return undefined;
  return safeIsoString(input) ?? fallback;
}

function parseGoalInput(projectId: string, input: Record<string, unknown> | undefined, store: EventStore):
  | { ok: true; goal: StoredMasterGoal }
  | { ok: false; response: QueryErrorResponse } {
  const now = new Date().toISOString();
  if (!input || typeof input !== "object") return invalidQuery("body", "Expected a goal object.");
  const title = safeString(input.title);
  if (!title) return invalidQuery("title", "Expected a bounded goal title.");
  const parsed = parseGoalMetadata(input, undefined, store);
  if (!parsed.ok) return parsed;
  return {
    ok: true,
    goal: {
      goal_id: safeString(input.goal_id) ?? slugId("goal", title),
      project_id: projectId,
      title,
      summary: safeString(input.summary),
      ...parsed.metadata,
      created_at: now,
      updated_at: now,
    },
  };
}

function parseGoalPatch(goal: StoredMasterGoal, input: Record<string, unknown> | undefined, store: EventStore):
  | { ok: true; goal: StoredMasterGoal }
  | { ok: false; response: QueryErrorResponse } {
  if (!input || typeof input !== "object") return invalidQuery("body", "Expected a goal patch object.");
  const parsed = parseGoalMetadata(input, goal, store);
  if (!parsed.ok) return parsed;
  const updated: StoredMasterGoal = {
    ...goal,
    title: safeString(input.title) ?? goal.title,
    summary: safeNullableString(input.summary, goal.summary),
    ...parsed.metadata,
    updated_at: new Date().toISOString(),
  };
  return { ok: true, goal: updated };
}

function parseGoalMetadata(
  input: Record<string, unknown>,
  existing: StoredMasterGoal | undefined,
  store: EventStore,
):
  | { ok: true; metadata: Omit<Partial<StoredMasterGoal>, "goal_id" | "project_id" | "title" | "summary" | "created_at" | "updated_at"> & { status: GoalStatus } }
  | { ok: false; response: QueryErrorResponse } {
  const status = safeString(input.status) ?? existing?.status ?? "draft";
  if (!GOAL_STATUSES.includes(status as GoalStatus)) return invalidQuery("status", "Expected a valid goal status.");
  const priority = safeString(input.priority) ?? existing?.priority ?? "normal";
  if (!GOAL_PRIORITIES.includes(priority as GoalPriority)) return invalidQuery("priority", "Expected a valid goal priority.");
  const risk = safeString(input.risk) ?? existing?.risk ?? "low";
  if (!GOAL_RISKS.includes(risk as GoalRisk)) return invalidQuery("risk", "Expected a valid goal risk.");
  const supersededBy = safeNullableString(input.superseded_by, existing?.superseded_by);
  const blockedReason = safeNullableString(input.blocked_reason, existing?.blocked_reason);
  const completionNote = safeNullableString(input.completion_note, existing?.completion_note);
  const evidenceSummary = safeEvidenceSummary(input.evidence_summary, existing?.evidence_summary);
  if (status === "blocked" && !blockedReason) return invalidQuery("blocked_reason", "Blocked goals require a reason.");
  if (status === "completed" && !completionNote && !evidenceSummary?.summary)
    return invalidQuery("completion_note", "Completed goals require an evidence summary or completion note.");
  if (status === "superseded" && !supersededBy) return invalidQuery("superseded_by", "Superseded goals require superseded_by.");
  if (supersededBy && !store.getGoal(supersededBy)) return invalidQuery("superseded_by", "Superseding goal was not found.");
  return {
    ok: true,
    metadata: {
      status: status as GoalStatus,
      source: safeNullableString(input.source, existing?.source),
      priority: priority as GoalPriority,
      risk: risk as GoalRisk,
      lifecycle: safeNullableString(input.lifecycle, existing?.lifecycle) ?? status,
      acceptance_criteria: safeStringArray(input.acceptance_criteria) ?? existing?.acceptance_criteria ?? [],
      evidence_requirements: safeStringArray(input.evidence_requirements) ?? existing?.evidence_requirements ?? [],
      dedupe_key: safeNullableString(input.dedupe_key, existing?.dedupe_key),
      supersedes: safeStringArray(input.supersedes) ?? existing?.supersedes ?? [],
      superseded_by: supersededBy,
      stale_reason: safeNullableString(input.stale_reason, existing?.stale_reason),
      blocked_reason: blockedReason,
      planner_metadata: safePlannerMetadata(input.planner_metadata) ?? existing?.planner_metadata,
      model_backend_metadata: safeModelBackendMetadata(input.model_backend_metadata) ?? existing?.model_backend_metadata,
      completion_note: completionNote,
      evidence_summary: evidenceSummary,
      progress_summary: existing?.progress_summary,
    },
  };
}

function parseWorkerInput(input: Record<string, unknown> | undefined):
  | { ok: true; worker: StoredWorker }
  | { ok: false; response: QueryErrorResponse } {
  const now = new Date().toISOString();
  if (!input || typeof input !== "object") return invalidQuery("body", "Expected a worker object.");
  const name = safeString(input.name);
  if (!name) return invalidQuery("name", "Expected a bounded worker name.");
  return {
    ok: true,
    worker: {
      worker_id: safeString(input.worker_id) ?? slugId("worker", name),
      name,
      provider: safeString(input.provider) ?? "manual",
      capabilities: safeStringArray(input.capabilities) ?? [],
      labels: safeStringArray(input.labels) ?? [],
      enabled: input.enabled !== false,
      auth_mode: safeWorkerAuthMode(input.auth_mode),
      api_base_redacted: redactApiBase(safeString(input.api_base)),
      allow_remote_server: typeof input.allow_remote_server === "boolean" ? input.allow_remote_server : undefined,
      created_at: now,
      updated_at: now,
    },
  };
}

function safeWorkerAuthMode(input: unknown): "none" | "bearer_token" | undefined {
  const value = safeString(input);
  if (!value) return undefined;
  if (value === "worker-token") return "bearer_token";
  if (value === "none" || value === "bearer_token") return value;
  return undefined;
}

function redactApiBase(input: string | undefined): string | undefined {
  if (!input) return undefined;
  try {
    const url = new URL(input);
    return `${url.protocol}//${url.host}`;
  } catch {
    return undefined;
  }
}

function parseTaskInput(input: Record<string, unknown> | undefined, store: EventStore):
  | { ok: true; task: StoredTask }
  | { ok: false; status?: number; response: QueryErrorResponse | { ok: false; error: string } } {
  const now = new Date().toISOString();
  if (!input || typeof input !== "object") return { ok: false, response: invalidQuery("body", "Expected a task object.").response };
  const title = safeString(input.title);
  const projectId = safeString(input.project_id);
  if (!title) return { ok: false, response: invalidQuery("title", "Expected a bounded task title.").response };
  if (!projectId) return { ok: false, response: invalidQuery("project_id", "Expected a project id.").response };
  if (!store.getProject(projectId)) return { ok: false, status: 404, response: { ok: false, error: "project_not_found" } };
  const goalId = safeString(input.goal_id);
  const goal = goalId ? store.getGoal(goalId) : undefined;
  if (goalId && !goal) return { ok: false, status: 404, response: { ok: false, error: "goal_not_found" } };
  if (goal && ["archived", "superseded"].includes(goal.status))
    return { ok: false, status: 409, response: { ok: false, error: "goal_not_executable" } };
  const risk = safeString(input.risk) ?? "low";
  const source = safeString(input.source) ?? "manual";
  if (!TASK_RISKS.includes(risk as TaskRisk)) return { ok: false, response: invalidQuery("risk", "Expected a valid task risk.").response };
  if (!TASK_SOURCES.includes(source as TaskSource)) return { ok: false, response: invalidQuery("source", "Expected a valid task source.").response };
  return {
    ok: true,
    task: {
      task_id: safeString(input.task_id) ?? slugId("task", title),
      project_id: projectId,
      goal_id: goalId,
      title,
      body: safeLongString(input.body),
      prompt_summary: safeString(input.prompt_summary),
      status: "queued",
      risk: risk as TaskRisk,
      source: source as TaskSource,
      task_type: safeString(input.task_type),
      planner_metadata: safePlannerMetadata(input.planner_metadata),
      allowed_paths: safePathArray(input.allowed_paths),
      blocked_paths: safePathArray(input.blocked_paths),
      validation: safeStringArray(input.validation),
      required_capabilities: safeStringArray(input.required_capabilities) ?? [],
      created_at: now,
      updated_at: now,
    },
  };
}

function presentWorker(worker: StoredWorker, store: EventStore): Worker {
  const latestHeartbeat = store.listWorkerHeartbeats(worker.worker_id)[0];
  const status = worker.enabled ? statusFromHeartbeat(latestHeartbeat) : "disabled";
  const currentTask = store
    .listTasks({ status: "claimed" })
    .find((task) => task.assigned_worker_id === worker.worker_id) ??
    store.listTasks({ status: "running" }).find((task) => task.assigned_worker_id === worker.worker_id);
  return {
    ...worker,
    status,
    current_task_id: currentTask?.task_id,
    last_seen_at: latestHeartbeat?.seen_at,
  };
}

function statusFromHeartbeat(heartbeat: StoredWorkerHeartbeat | undefined): WorkerStatus {
  if (!heartbeat) return "offline";
  const ageMs = Date.now() - Date.parse(heartbeat.seen_at);
  if (!Number.isFinite(ageMs)) return "offline";
  if (ageMs <= 2 * 60 * 1000) return "online";
  if (ageMs <= 15 * 60 * 1000) return "stale";
  return "offline";
}

function withTaskEvents(task: StoredTask, store: EventStore): Task & { events: StoredTaskEvent[]; last_event?: StoredTaskEvent } {
  const events = store.listTaskEvents(task.task_id);
  return { ...task, events, last_event: events.at(-1) };
}

async function recordTaskEvent(
  task: StoredTask,
  type: Extract<SkyBridgeEventType, `task.${string}`>,
  workerId: string | undefined,
  message: string,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
  store: EventStore,
  payload: Record<string, unknown> = {},
): Promise<void> {
  const event: StoredTaskEvent = {
    task_event_id: `te_${nanoid()}`,
    task_id: task.task_id,
    type,
    worker_id: workerId,
    time: new Date().toISOString(),
    message,
    payload: { status: task.status, ...payload },
  };
  await store.addTaskEvent(event);
  await addStoredEvent(coreEvent(type, {
    task_id: task.task_id,
    project_id: task.project_id,
    goal_id: task.goal_id,
    worker_id: workerId,
    status: task.status,
    risk: task.risk,
  }));
}

async function updateTaskTerminal(
  taskIdParam: string,
  workerIdInput: unknown,
  status: TaskStatus,
  eventType: Extract<SkyBridgeEventType, `task.${string}`>,
  reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
) {
  const task = store.getTask(decodeURIComponent(taskIdParam));
  if (!task) return reply.code(404).send({ ok: false, error: "task_not_found" });
  if (["completed", "cancelled"].includes(task.status)) return reply.code(409).send({ ok: false, error: "invalid_task_transition" });
  const workerId = safeString(workerIdInput) ?? task.assigned_worker_id;
  const updated: StoredTask = { ...task, status, assigned_worker_id: workerId, updated_at: new Date().toISOString() };
  await store.upsertTask(updated);
  await recordTaskEvent(updated, eventType, workerId, `Task ${status}.`, addStoredEvent, store);
  return { ok: true, task: withTaskEvents(updated, store) };
}

async function finishTask(
  taskIdParam: string,
  body: Record<string, unknown>,
  status: TaskStatus,
  eventType: Extract<SkyBridgeEventType, `task.${string}`>,
  reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
) {
  const task = store.getTask(decodeURIComponent(taskIdParam));
  if (!task) return reply.code(404).send({ ok: false, error: "task_not_found" });
  if (task.status === "completed" || task.status === "cancelled")
    return reply.code(409).send({ ok: false, error: "invalid_task_transition" });
  const workerId = safeString(body.worker_id) ?? task.assigned_worker_id;
  const updated: StoredTask = {
    ...task,
    status,
    assigned_worker_id: workerId,
    result: {
      summary: safeString(body.summary),
      result_url: safeString(body.result_url),
      pr_url: safeString(body.pr_url),
      error_summary: safeString(body.error_summary),
      evidence_summary: safeEvidenceSummary(body.evidence_summary),
    },
    updated_at: new Date().toISOString(),
  };
  await store.upsertTask(updated);
  if (updated.goal_id) await updateGoalProgress(updated.goal_id, store);
  await recordTaskEvent(
    updated,
    eventType,
    workerId,
    `Task ${status}.`,
    addStoredEvent,
    store,
    updated.result ? { ...updated.result } : {},
  );
  return { ok: true, task: withTaskEvents(updated, store) };
}

function summarizeWorkers(store: EventStore) {
  const workers = store.listWorkers().map((worker) => presentWorker(worker, store));
  const byStatus = countBy(workers, (worker) => worker.status);
  return {
    total: workers.length,
    online: byStatus.online ?? 0,
    stale: byStatus.stale ?? 0,
    offline: byStatus.offline ?? 0,
    disabled: byStatus.disabled ?? 0,
    workers,
  };
}

function summarizeTasks(store: EventStore) {
  const tasks = store.listTasks();
  const byStatus = countBy(tasks, (task) => task.status);
  const latestEvent = store.listTaskEvents().at(-1);
  return {
    total: tasks.length,
    queued: byStatus.queued ?? 0,
    claimed: byStatus.claimed ?? 0,
    running: byStatus.running ?? 0,
    completed: byStatus.completed ?? 0,
    failed: byStatus.failed ?? 0,
    blocked: byStatus.blocked ?? 0,
    cancelled: byStatus.cancelled ?? 0,
    stale: byStatus.stale ?? 0,
    latest_event: latestEvent,
  };
}

function withGoalSummary(goal: StoredMasterGoal, store: EventStore) {
  return { ...goal, task_summary: summarizeGoalTasks(goal.goal_id, store) };
}

function summarizeGoalTasks(goalId: string, store: EventStore) {
  const tasks = store.listTasks({ goalId });
  const byStatus = countBy(tasks, (task) => task.status);
  const evidence = tasks
    .map((task) => task.result?.evidence_summary)
    .filter((item): item is EvidenceSummary => !!item);
  return {
    total: tasks.length,
    queued: byStatus.queued ?? 0,
    claimed: byStatus.claimed ?? 0,
    running: byStatus.running ?? 0,
    completed: byStatus.completed ?? 0,
    failed: byStatus.failed ?? 0,
    blocked: byStatus.blocked ?? 0,
    cancelled: byStatus.cancelled ?? 0,
    stale: byStatus.stale ?? 0,
    evidence_count: evidence.length,
    latest_evidence: evidence.at(-1),
  };
}

async function updateGoalProgress(goalId: string, store: EventStore): Promise<void> {
  const goal = store.getGoal(goalId);
  if (!goal) return;
  const summary = summarizeGoalTasks(goalId, store);
  await store.upsertGoal({
    ...goal,
    progress_summary: {
      total_tasks: summary.total,
      queued_tasks: summary.queued,
      running_tasks: summary.running + summary.claimed,
      completed_tasks: summary.completed,
      failed_tasks: summary.failed,
      blocked_tasks: summary.blocked,
      evidence_count: summary.evidence_count,
      updated_at: new Date().toISOString(),
    },
    evidence_summary: summary.latest_evidence ?? goal.evidence_summary,
    status: goal.status === "active" && summary.completed > 0 ? "partially_completed" : goal.status,
    updated_at: new Date().toISOString(),
  });
}

function mergeProjectViews(projects: StoredProject[], derived: ReturnType<typeof summarizeProjects>) {
  const byId = new Map(derived.map((project) => [project.project_id, project]));
  const merged = projects.map((project) => ({
    ...project,
    ...(byId.get(project.project_id) ?? {
      run_count: 0,
      active_runs: 0,
      failed_runs: 0,
      iteration_count: 0,
      latest_activity_at: project.updated_at,
    }),
    goal_count: 0,
  }));
  for (const project of derived) {
    if (!projects.some((stored) => stored.project_id === project.project_id)) {
      merged.push(project as StoredProject & typeof project & { goal_count: number });
    }
  }
  return merged;
}

function slugId(prefix: string, value: string): string {
  const slug = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 40) || prefix;
  return `${prefix}_${slug}_${nanoid(6)}`;
}

function safeLongString(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 && input.length <= 8000
    ? input
    : undefined;
}

function safePathArray(input: unknown): string[] | undefined {
  const values = safeStringArray(input);
  if (!values) return undefined;
  return values
    .filter((value) => !/[<>:"|?*]/.test(value))
    .map((value) => value.replace(/\\/g, "/"))
    .slice(0, 50);
}

function safePlannerMetadata(input: unknown) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return undefined;
  const record = redactUnsafePayload(input) as Record<string, unknown>;
  const adapter = safeString(record.adapter);
  const decision = safeString(record.decision);
  if (!isPlannerDecisionAction(decision)) return undefined;
  if (!adapter || !decision) return undefined;
  return {
    adapter,
    decision,
    reason: safeString(record.reason) ?? "not provided",
    task_type: safeString(record.task_type),
    allowed_paths: safePathArray(record.allowed_paths) ?? [],
    blocked_paths: safePathArray(record.blocked_paths) ?? [],
    validation: safeStringArray(record.validation) ?? [],
    stop_criteria_status: safeStringArray(record.stop_criteria_status) ?? [],
    source_run_id: safeString(record.source_run_id),
    created_at: safeIsoString(record.created_at) ?? new Date().toISOString(),
    raw_response_included: false as const,
    secrets_included: false as const,
  };
}

function safeModelBackendMetadata(input: unknown) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return undefined;
  const record = redactUnsafePayload(input) as Record<string, unknown>;
  const adapter = safeString(record.adapter);
  if (!adapter) return undefined;
  return {
    adapter,
    backend: safeString(record.backend),
    model: safeString(record.model),
    audit_only: true as const,
    raw_response_included: false as const,
    secrets_included: false as const,
  };
}

function safeEvidenceSummary(input: unknown, fallback?: EvidenceSummary): EvidenceSummary | undefined {
  if (input === null) return undefined;
  if (!input || typeof input !== "object" || Array.isArray(input)) return fallback;
  const record = redactUnsafePayload(input) as Record<string, unknown>;
  const summary = safeString(record.summary);
  if (!summary) return fallback;
  return {
    task_id: safeString(record.task_id),
    goal_id: safeString(record.goal_id),
    pr_url: safeString(record.pr_url),
    commit_sha: safeString(record.commit_sha),
    changed_files: safePathArray(record.changed_files) ?? [],
    validation_status: safeString(record.validation_status),
    ci_status: safeString(record.ci_status),
    risk_status: safeString(record.risk_status),
    summary,
    created_at: safeIsoString(record.created_at) ?? new Date().toISOString(),
  };
}

function isPlannerDecisionAction(input: string | undefined): input is PlannerDecisionAction {
  return !!input && ["continue", "repair", "wait", "stop", "blocked"].includes(input);
}

function safeIsoString(input: unknown): string | undefined {
  if (typeof input !== "string" || input.length > 80) return undefined;
  const time = Date.parse(input);
  return Number.isFinite(time) ? input : undefined;
}

function parseIterationInput(
  input: Partial<IterationRun> | undefined,
):
  | { ok: true; iteration: IterationRun }
  | { ok: false; response: QueryErrorResponse & { message?: string } } {
  const now = new Date().toISOString();
  if (!input || typeof input !== "object")
    return invalidQuery("body", "Expected an iteration object.");
  if (!safeString(input.iteration_id))
    return invalidQuery("iteration_id", "Expected a stable iteration id.");
  if (!safeString(input.project_id))
    return invalidQuery("project_id", "Expected a project id.");
  if (!safeString(input.repo))
    return invalidQuery("repo", "Expected a repository full name.");
  if (!safeString(input.branch))
    return invalidQuery("branch", "Expected a branch.");
  if (!safeString(input.base_branch))
    return invalidQuery("base_branch", "Expected a base branch.");
  if (!isIterationState(input.state ?? ""))
    return invalidQuery("state", "Expected a valid iteration state.");
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
      pr_number:
        typeof input.pr_number === "number" && Number.isInteger(input.pr_number)
          ? input.pr_number
          : undefined,
      state,
      attempts:
        typeof input.attempts === "number" && Number.isInteger(input.attempts)
          ? input.attempts
          : 0,
      max_attempts:
        typeof input.max_attempts === "number" &&
        Number.isInteger(input.max_attempts)
          ? input.max_attempts
          : 3,
      last_error: safeString(input.last_error),
      checks: sanitizeChecks(input.checks ?? []),
      auto_merge_enabled: input.auto_merge_enabled === true,
      created_at: safeString(input.created_at) ?? now,
      updated_at: safeString(input.updated_at) ?? now,
    },
  };
}

function isIterationState(input: string): input is IterationState {
  return (ITERATION_STATES as string[]).includes(input);
}

function sanitizeChecks(input: unknown): IterationRun["checks"] {
  if (!Array.isArray(input)) return [];
  return input.slice(0, 50).map((item) => {
    const record =
      item && typeof item === "object" ? (item as Record<string, unknown>) : {};
    const status = safeString(record.status);
    return {
      name: safeString(record.name) ?? "check",
      status:
        status === "pending" ||
        status === "passed" ||
        status === "failed" ||
        status === "skipped"
          ? status
          : "pending",
      started_at: safeString(record.started_at),
      completed_at: safeString(record.completed_at),
      exit_code:
        typeof record.exit_code === "number" &&
        Number.isInteger(record.exit_code)
          ? record.exit_code
          : undefined,
      summary: safeString(record.summary),
    };
  });
}

function sanitizeIterationPayload(
  input: unknown,
):
  | { ok: true; payload: Record<string, unknown> }
  | { ok: false; response: QueryErrorResponse } {
  const redacted = redactUnsafePayload(input);
  const payload =
    redacted && typeof redacted === "object" && !Array.isArray(redacted)
      ? (redacted as Record<string, unknown>)
      : { value: redacted };
  const bytes = Buffer.byteLength(JSON.stringify(payload), "utf8");
  if (bytes > SharedRedactionRules.maxPayloadBytes)
    return invalidQuery(
      "payload",
      `Payload must be <= ${SharedRedactionRules.maxPayloadBytes} bytes.`,
    );
  return { ok: true, payload };
}

function redactUnsafePayload(input: unknown): unknown {
  if (typeof input === "string")
    return input.length > 200 ? `${input.slice(0, 200)}...` : input;
  if (Array.isArray(input)) return input.slice(0, 50).map(redactUnsafePayload);
  if (!input || typeof input !== "object") return input;
  const output: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (/token|secret|password|cookie|credential|authorization/i.test(key)) {
      output[key] = SharedRedactionRules.replacement;
    } else if (
      /prompt|patch|stdout|stderr|output|command_output|tool_result/i.test(key)
    ) {
      output[key] = { omitted: true, reason: "unsafe_raw_payload" };
    } else {
      output[key] = redactUnsafePayload(value);
    }
  }
  return output;
}

function supervisorStatus(
  iterations: StoredIterationRun[],
  events: StoredEvent[],
) {
  const sorted = iterations.sort((a, b) =>
    b.updated_at.localeCompare(a.updated_at),
  );
  const blocked = sorted.filter(
    (iteration) =>
      iteration.state === "blocked" || iteration.state === "failed",
  );
  const active = sorted.filter(
    (iteration) => !["merged", "blocked", "failed"].includes(iteration.state),
  );
  return {
    ok: true,
    raw_prompts_included: false,
    raw_logs_included: false,
    notification_path: {
      primary_for_skybridge_development: "bootstrap-direct",
      skybridge_notification_center_required: false,
      migration_stage: "dual-write-ready",
    },
    iterations: {
      total: iterations.length,
      active: active.length,
      blocked: blocked.length,
      latest: sorted[0],
    },
    recent_iteration_events: events
      .filter((event) => event.type.startsWith("iteration."))
      .slice(-20),
  };
}

function supervisorNextAction(iterations: StoredIterationRun[]) {
  const latest = iterations.sort((a, b) =>
    b.updated_at.localeCompare(a.updated_at),
  )[0];
  if (!latest)
    return { action: "start_next_iteration", reason: "no_iterations_recorded" };
  if (latest.state === "ci_failed")
    return {
      action: "repair_ci",
      iteration_id: latest.iteration_id,
      pr_number: latest.pr_number,
    };
  if (latest.state === "blocked" || latest.state === "failed")
    return {
      action: "notify_human",
      iteration_id: latest.iteration_id,
      reason: latest.last_error,
    };
  if (latest.state === "ci_green")
    return {
      action: latest.auto_merge_enabled ? "wait_for_merge" : "review_green_pr",
      iteration_id: latest.iteration_id,
      pr_number: latest.pr_number,
    };
  return {
    action: "observe",
    iteration_id: latest.iteration_id,
    state: latest.state,
  };
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

function sqlitePathFromLegacy(
  filePath: string | false | undefined,
): string | undefined {
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
