import cors from "@fastify/cors";
import Fastify, { type FastifyInstance } from "fastify";
import { existsSync, readFileSync } from "node:fs";
import { createHash, timingSafeEqual } from "node:crypto";
import { basename, dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { nanoid } from "nanoid";
import { ZodError } from "zod";
import {
  createEvent,
  CampaignDraftSchema,
  getTaskTemplate,
  listAdapterCapabilities,
  isNotificationTrigger,
  parseEvent,
  SOURCE_CAPABILITIES,
  SharedRedactionRules,
  TaskDraftSchema,
  fixtureOperatorApprovalGate,
  fixtureOperatorApprovalRequest,
  fixtureOperatorApprovalState,
  fixtureWorkerHeartbeat,
  fixtureWorkerPairingPreview,
  fixtureWorkerRegistration,
  parseOperatorApprovalRequest,
  parseWorkerHeartbeat,
  parseWorkerRegistration,
  type RunDetail,
  type RunSummary,
  type IterationRun,
  type IterationState,
  type SkyBridgeSeverity,
  type SkyBridgeEventType,
  type SkyBridgeEvent,
  type SkyBridgeSourcePlatform,
  type MasterGoal,
  type PlannerAdapterAuditMetadata,
  type PlanningProposalStatus,
  type EvidenceSummary,
  type CampaignStatus,
  type CampaignStepStatus,
  type GoalPriority,
  type GoalRisk,
  type GoalStatus,
  type Project,
  type ProjectControlState,
  type Task,
  type TaskEvent,
  type TaskLease,
  type TaskRisk,
  type TaskSource,
  type TaskStatus,
  type CampaignDraft,
  type PlannerDecisionAction,
  type TaskDraft,
  type TaskTemplate,
  type Worker,
  type WorkerCapability,
  type WorkerStatus,
  type OperatorApprovalRequest,
  type OperatorApprovalState,
  type ControlPlaneWorkerHeartbeat,
  type WorkerPairingPreview,
  type WorkerRegistration,
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
  type StoredPlanningMasterGoal,
  type StoredPlanningSession,
  type StoredNotification,
  type StoredProject,
  type StoredTask,
  type StoredTaskEvent,
  type StoredTaskProposal,
  type StoredCampaign,
  type StoredCampaignStep,
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

const ROUTE_SET_VERSION = "2026-06-17.goal-301-cloud-deploy-parity.goal-328-draft-submit";
const DRAFT_SUBMIT_CONFIRMATION_TEXT =
  "I_UNDERSTAND_CREATE_QUEUED_DRAFT_RECORDS_ONLY_NO_EXECUTION";

interface ServerVersionMetadata {
  schema: "skybridge.server_version.v1";
  service: "skybridge-server";
  server_version: string;
  commit_sha: string;
  image_tag: string;
  image_ref: string;
  build_time: string;
  route_set_version: string;
  token_printed: false;
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
const HYGIENE_METADATA_OPERATIONS = [
  "mark_evidence_repair_applied",
  "mark_keep_blocked",
  "mark_archived_by_operator_policy",
  "mark_excluded_from_requeue",
] as const;
const TASK_RISKS: TaskRisk[] = ["low", "medium", "high"];
const PROPOSAL_STATUSES: PlanningProposalStatus[] = [
  "proposed",
  "reviewed",
  "approved",
  "rejected",
  "deferred",
  "superseded",
  "blocked_dependency",
  "converted",
  "executed",
];
const CAMPAIGN_STATUSES: CampaignStatus[] = ["draft", "ready", "running", "paused", "held", "completed", "failed", "aborted"];
const CAMPAIGN_STEP_STATUSES: CampaignStepStatus[] = ["pending", "ready", "running", "completed", "recovered", "failed", "skipped", "held", "needs_human", "blocked_dependency"];
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
const DEFAULT_TASK_LEASE_SECONDS = 30 * 60;
const DEFAULT_TASK_MAX_ATTEMPTS = 1;
const MANUAL_TASK_PROVIDER_IDS = [
  "mock",
  "hermes_deepseek",
  "skybridge_server_hermes",
] as const;
type ManualTaskProviderId = (typeof MANUAL_TASK_PROVIDER_IDS)[number];

interface ManualTaskRunInput {
  question?: unknown;
  input_preview?: unknown;
  task_id?: unknown;
}

interface ManualTaskProviderRecord {
  schema: "skybridge.manual_task_provider.v1";
  provider_id: ManualTaskProviderId;
  status: string;
  configured: boolean;
  deterministic: boolean;
  network_enabled: boolean;
  hermes_live_call_enabled: false;
  server_mediated_llm_inference_enabled: boolean;
  cloud_hermes_provider_enabled: boolean;
  remote_llm_inference_enabled: false;
  disabled_by_default: boolean;
  deprecated?: boolean;
  preview_only?: boolean;
  ci_disabled: boolean;
  config_values_redacted: true;
  raw_request_persisted: false;
  raw_response_persisted: false;
  reason: string;
  token_printed: false;
}

interface ManualTaskResultRecord {
  schema: "skybridge.manual_task_result.v1";
  task_id?: string;
  provider_id: ManualTaskProviderId;
  provider_status: string;
  status: "succeeded" | "failed" | "blocked";
  result_preview: string;
  result_hash: string;
  duration_ms: number;
  error_summary: string;
  server_mediated_llm_inference_enabled: boolean;
  cloud_hermes_provider_enabled: boolean;
  live_call_performed: boolean;
  remote_llm_inference_enabled: false;
  output_executed: false;
  command_executed: false;
  workunit_created: false;
  task_created: false;
  task_claim_created: false;
  task_pr_created: false;
  remote_execution_enabled: false;
  arbitrary_command_enabled: false;
  queue_apply_enabled: false;
  raw_request_persisted: false;
  raw_response_persisted: false;
  token_printed: false;
}

interface ServerHermesConfig {
  configured: boolean;
  apiBase?: string;
  apiKey?: string;
  timeoutMs: number;
  maxResponseChars: number;
  reason: string;
}

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

function safeVersionValue(value: string | undefined, fallback: string): string {
  const trimmed = value?.trim();
  if (!trimmed) return fallback;
  return trimmed.replace(/[^A-Za-z0-9._:@/+~-]/g, "_").slice(0, 160);
}

function serverVersionMetadata(): ServerVersionMetadata {
  return {
    schema: "skybridge.server_version.v1",
    service: "skybridge-server",
    server_version: safeVersionValue(process.env.SKYBRIDGE_SERVER_VERSION, "0.1.0"),
    commit_sha: safeVersionValue(process.env.SKYBRIDGE_COMMIT_SHA, "unknown"),
    image_tag: safeVersionValue(process.env.SKYBRIDGE_IMAGE_TAG, "local"),
    image_ref: safeVersionValue(process.env.SKYBRIDGE_IMAGE_REF, "unknown"),
    build_time: safeVersionValue(process.env.SKYBRIDGE_BUILD_TIME, "unknown"),
    route_set_version: ROUTE_SET_VERSION,
    token_printed: false,
  };
}

function getProposalDependencies(proposal: StoredTaskProposal): string[] {
  return [...new Set([...(proposal.dependencies ?? []), ...(proposal.depends_on ?? [])].map((value) => value.trim()).filter(Boolean))];
}

function validateProposalConversion(proposal: StoredTaskProposal, allProposals: StoredTaskProposal[]): { ok: true } | { ok: false; error: string; reasons: string[] } {
  const reasons: string[] = [];
  if (proposal.status !== "approved") reasons.push("proposal status must be approved");
  if (proposal.risk !== "low") reasons.push("proposal risk must be low");
  if (!["docs", "local-smoke"].includes(proposal.task_type)) reasons.push("task_type must be docs or local-smoke");

  const blockedText = [
    proposal.title,
    proposal.body,
    proposal.prompt_summary,
    proposal.rationale,
    ...(proposal.expected_files ?? []),
  ].join(" ");
  if (/(production|deploy|secret|github settings|branch protection|server config|server-root-config|\/opt\/skybridge-agent-hub|\.env|private key|token file)/i.test(blockedText)) {
    reasons.push("proposal mentions a blocked high-risk surface");
  }

  const expectedFiles = proposal.expected_files ?? [];
  if (expectedFiles.length === 0) reasons.push("expected_files are required");
  for (const file of expectedFiles) {
    const normalized = file.replace(/\\/g, "/");
    const docsOk = proposal.task_type === "docs" && normalized.startsWith("docs/");
    const localSmokeOk = proposal.task_type === "local-smoke" && /^scripts\/powershell\/smoke-[^/]+\.ps1$/i.test(normalized);
    if (!docsOk && !localSmokeOk) reasons.push(`expected file is outside allowed ${proposal.task_type} paths: ${normalized}`);
  }

  for (const dependencyId of getProposalDependencies(proposal)) {
    const dependency = allProposals.find((candidate) => candidate.proposal_id === dependencyId);
    if (!dependency || !["converted", "executed"].includes(dependency.status)) {
      reasons.push(`dependency is not converted or executed: ${dependencyId}`);
    }
  }

  if (reasons.length > 0) return { ok: false, error: "proposal_not_convertible", reasons };
  return { ok: true };
}

function addSeconds(value: Date, seconds: number): string {
  return new Date(value.getTime() + seconds * 1000).toISOString();
}

function isActiveLease(lease: TaskLease | undefined): lease is TaskLease {
  return lease?.lease_status === "active";
}

function isExpiredLease(lease: TaskLease | undefined, now: Date): boolean {
  if (!isActiveLease(lease)) return false;
  const expiresAt = Date.parse(lease.lease_expires_at);
  return Number.isFinite(expiresAt) && expiresAt <= now.getTime();
}

function buildTaskLease(task: StoredTask, workerId: string, now: Date): TaskLease {
  const previousAttempt = task.lease?.current_attempt ?? 0;
  return {
    lease_id: `lease_${nanoid()}`,
    task_id: task.task_id,
    worker_id: workerId,
    project_id: task.project_id,
    claimed_at: now.toISOString(),
    lease_expires_at: addSeconds(now, DEFAULT_TASK_LEASE_SECONDS),
    heartbeat_at: now.toISOString(),
    lease_status: "active",
    current_attempt: previousAttempt + 1,
    max_attempts: task.lease?.max_attempts ?? DEFAULT_TASK_MAX_ATTEMPTS,
  };
}

function refreshTaskLease(task: StoredTask, workerId: string | undefined, now: Date): TaskLease | undefined {
  if (!isActiveLease(task.lease)) return task.lease;
  if (workerId && task.lease.worker_id !== workerId) return task.lease;
  return {
    ...task.lease,
    heartbeat_at: now.toISOString(),
    lease_expires_at: addSeconds(now, DEFAULT_TASK_LEASE_SECONDS),
    stale_reason: undefined,
  };
}

function releaseTaskLease(task: StoredTask, workerId: string | undefined, now: Date): TaskLease | undefined {
  if (!task.lease) return undefined;
  if (workerId && task.lease.worker_id !== workerId) return task.lease;
  return {
    ...task.lease,
    heartbeat_at: now.toISOString(),
    released_at: now.toISOString(),
    lease_status: "released",
    stale_reason: undefined,
  };
}

function markExpiredLease(task: StoredTask, now: Date): TaskLease | undefined {
  const lease = task.lease;
  if (!isActiveLease(lease) || !isExpiredLease(lease, now)) return lease;
  return {
    ...lease,
    lease_status: "expired",
    stale_reason: "lease_expires_at_elapsed",
    heartbeat_at: now.toISOString(),
  };
}

async function refreshWorkerActiveLease(
  store: EventStore,
  workerId: string,
  now: Date,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
): Promise<TaskLease | undefined> {
  const task = store.listTasks().find((candidate) =>
    candidate.assigned_worker_id === workerId &&
    ["claimed", "running"].includes(candidate.status) &&
    isActiveLease(candidate.lease)
  );
  if (!task) return undefined;
  const lease = refreshTaskLease(task, workerId, now);
  if (!lease || lease === task.lease) return task.lease;
  const updated: StoredTask = { ...task, lease, updated_at: now.toISOString() };
  await store.upsertTask(updated);
  await recordTaskEvent(updated, "task.updated", workerId, "Task lease refreshed by worker heartbeat.", addStoredEvent, store, {
    lease_id: lease.lease_id,
    lease_expires_at: lease.lease_expires_at,
  });
  return lease;
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
  const controlPlaneWorkers = new Map<string, WorkerRegistration>([
    [fixtureWorkerRegistration.worker_id, fixtureWorkerRegistration],
  ]);
  const controlPlanePairings = new Map<string, WorkerPairingPreview>([
    [fixtureWorkerPairingPreview.worker_id, fixtureWorkerPairingPreview],
  ]);
  const controlPlaneHeartbeats = new Map<string, ControlPlaneWorkerHeartbeat>([
    [fixtureWorkerHeartbeat.worker_id, fixtureWorkerHeartbeat],
  ]);
  const operatorApprovalRequests = new Map<string, OperatorApprovalRequest>([
    [fixtureOperatorApprovalRequest.approval_request_id, fixtureOperatorApprovalRequest],
  ]);
  const operatorApprovalStates = new Map<string, OperatorApprovalState>([
    [fixtureOperatorApprovalState.approval_request_id, fixtureOperatorApprovalState],
  ]);

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
    ...serverVersionMetadata(),
    persistence: store.kind,
    dbFile: persistence.dbFile,
    jsonMigrationFile: persistence.jsonMigrationFile,
    time: new Date().toISOString(),
  });

  app.get("/health", async () => healthResponse());
  app.get("/v1/health", async () => healthResponse());
  app.get("/v1/version", async () => serverVersionMetadata());
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

  app.get("/api/local-auth/status", async (request, reply) => {
    const gate = evaluateLocalAuthPreviewRequest({
      origin: safeString(request.headers.origin) ?? "repo-local-dev-fixture",
      fixtureAuth: safeString(request.headers["x-skybridge-fixture-auth"]) ?? "fixture-hash",
      payload: {},
    });
    if (!gate.accepted) return reply.code(401).send(gate);
    return localAuthSafeMetadata("local-auth-status");
  });

  app.post<{ Body: Record<string, unknown> }>(
    "/api/local-auth/validate-preview",
    async (request, reply) => {
      const gate = evaluateLocalAuthPreviewRequest({
        origin: safeString(request.headers.origin) ?? safeString(request.body?.origin) ?? "repo-local-dev-fixture",
        fixtureAuth: safeString(request.headers["x-skybridge-fixture-auth"]) ?? safeString(request.body?.fixture_auth),
        payload: request.body,
      });
      if (!gate.accepted) return reply.code(401).send(gate);
      return reply.code(202).send({
        ok: true,
        gate,
        safe_metadata: localAuthSafeMetadata("validate-preview"),
        token_printed: false,
      });
    },
  );

  app.get("/api/control-plane/local-auth-preview", async (request, reply) => {
    const gate = evaluateLocalAuthPreviewRequest({
      origin: safeString(request.headers.origin) ?? "repo-local-dev-fixture",
      fixtureAuth: safeString(request.headers["x-skybridge-fixture-auth"]) ?? "fixture-hash",
      payload: {},
    });
    if (!gate.accepted) return reply.code(401).send(gate);
    return localAuthSafeMetadata("server-control-plane-preview");
  });

  app.get("/api/workers/pairing-local-auth-preview", async (request, reply) => {
    const gate = evaluateLocalAuthPreviewRequest({
      origin: safeString(request.headers.origin) ?? "repo-local-dev-fixture",
      fixtureAuth: safeString(request.headers["x-skybridge-fixture-auth"]) ?? "fixture-hash",
      payload: {},
    });
    if (!gate.accepted) return reply.code(401).send(gate);
    return localAuthSafeMetadata("worker-pairing-preview");
  });

  app.get("/api/operator-approvals/local-auth-preview", async (request, reply) => {
    const gate = evaluateLocalAuthPreviewRequest({
      origin: safeString(request.headers.origin) ?? "repo-local-dev-fixture",
      fixtureAuth: safeString(request.headers["x-skybridge-fixture-auth"]) ?? "fixture-hash",
      payload: {},
    });
    if (!gate.accepted) return reply.code(401).send(gate);
    return localAuthSafeMetadata("approval-preview");
  });

  app.get("/api/resident-polling/local-auth-preview", async (request, reply) => {
    const gate = evaluateLocalAuthPreviewRequest({
      origin: safeString(request.headers.origin) ?? "repo-local-dev-fixture",
      fixtureAuth: safeString(request.headers["x-skybridge-fixture-auth"]) ?? "fixture-hash",
      payload: {},
    });
    if (!gate.accepted) return reply.code(401).send(gate);
    return localAuthSafeMetadata("resident-polling-preview");
  });

  app.get("/api/product-readiness/local-auth-preview", async (request, reply) => {
    const gate = evaluateLocalAuthPreviewRequest({
      origin: safeString(request.headers.origin) ?? "repo-local-dev-fixture",
      fixtureAuth: safeString(request.headers["x-skybridge-fixture-auth"]) ?? "fixture-hash",
      payload: {},
    });
    if (!gate.accepted) return reply.code(401).send(gate);
    return localAuthSafeMetadata("product-readiness-preview");
  });

  app.get("/api/release-dashboard/local-auth-preview", async (request, reply) => {
    const gate = evaluateLocalAuthPreviewRequest({
      origin: safeString(request.headers.origin) ?? "repo-local-dev-fixture",
      fixtureAuth: safeString(request.headers["x-skybridge-fixture-auth"]) ?? "fixture-hash",
      payload: {},
    });
    if (!gate.accepted) return reply.code(401).send(gate);
    return localAuthSafeMetadata("release-dashboard-preview");
  });

  app.get("/api/workers", async () => ({
    workers: [...controlPlaneWorkers.values()].map((worker) =>
      controlPlaneWorkerView(
        worker,
        controlPlanePairings.get(worker.worker_id),
        controlPlaneHeartbeats.get(worker.worker_id),
      ),
    ),
    remote_execution_enabled: false,
    arbitrary_command_enabled: false,
    execution_enabled: false,
    token_printed: false,
  }));

  app.get<{ Params: { workerId: string } }>(
    "/api/workers/:workerId/status",
    async (request, reply) => {
      const workerId = decodeURIComponent(request.params.workerId);
      const worker = controlPlaneWorkers.get(workerId);
      if (!worker) return reply.code(404).send({ ok: false, error: "worker_not_found", token_printed: false });
      return {
        worker: controlPlaneWorkerView(
          worker,
          controlPlanePairings.get(workerId),
          controlPlaneHeartbeats.get(workerId),
        ),
        heartbeat: controlPlaneHeartbeats.get(workerId),
        approval_gate: fixtureOperatorApprovalGate,
        remote_execution_enabled: false,
        arbitrary_command_enabled: false,
        execution_enabled: false,
        token_printed: false,
      };
    },
  );

  app.post<{ Body: Record<string, unknown> }>(
    "/api/workers/register-preview",
    async (request, reply) => {
      const unsafe = findUnsafeControlPlanePayload(request.body);
      if (unsafe.length > 0) return reply.code(400).send(workerIngestRejection(unsafe));
      try {
        const registration = parseWorkerRegistration({
          ...fixtureWorkerRegistration,
          ...request.body,
          execution_enabled: false,
          queue_apply_enabled: false,
          remote_execution_enabled: false,
          arbitrary_command_enabled: false,
          pairing_code_raw_persisted: false,
          token_printed: false,
        });
        controlPlaneWorkers.set(registration.worker_id, registration);
        return reply.code(202).send({
          ok: true,
          worker: registration,
          remote_execution_enabled: false,
          arbitrary_command_enabled: false,
          execution_enabled: false,
          token_printed: false,
        });
      } catch (error) {
        return reply.code(400).send({ ok: false, error: "invalid_worker_registration", message: error instanceof Error ? error.message : String(error), token_printed: false });
      }
    },
  );

  app.post<{ Body: Record<string, unknown> }>(
    "/api/workers/pairing-preview",
    async (request, reply) => {
      const unsafe = findUnsafeControlPlanePayload(request.body);
      if (unsafe.length > 0) return reply.code(400).send(workerIngestRejection(unsafe));
      const workerId = safeString(request.body?.worker_id) ?? fixtureWorkerRegistration.worker_id;
      const worker = controlPlaneWorkers.get(workerId) ?? fixtureWorkerRegistration;
      const preview: WorkerPairingPreview = {
        ...fixtureWorkerPairingPreview,
        worker_id: worker.worker_id,
        resident_enabled: worker.resident_enabled,
        paired: request.body?.paired === true,
        pairing_state: request.body?.paired === true ? "paired" : "pairing_preview",
        pairing_code_hash: safeString(request.body?.pairing_code_hash) ?? worker.pairing_code_hash,
        pairing_code_raw_persisted: false,
        execution_enabled: false,
        queue_apply_enabled: false,
        remote_execution_enabled: false,
        arbitrary_command_enabled: false,
        token_printed: false,
      };
      controlPlanePairings.set(worker.worker_id, preview);
      return reply.code(202).send({
        ok: true,
        pairing_preview: preview,
        approval_gate: fixtureOperatorApprovalGate,
        remote_execution_enabled: false,
        arbitrary_command_enabled: false,
        execution_enabled: false,
        token_printed: false,
      });
    },
  );

  app.post<{ Params: { workerId: string } }>(
    "/api/workers/:workerId/revoke-preview",
    async (request, reply) => {
      const workerId = decodeURIComponent(request.params.workerId);
      const pairing = controlPlanePairings.get(workerId);
      if (!pairing) return reply.code(404).send({ ok: false, error: "pairing_not_found", token_printed: false });
      const revoked: WorkerPairingPreview = {
        ...pairing,
        paired: false,
        pairing_state: "revoked",
        execution_enabled: false,
        queue_apply_enabled: false,
        remote_execution_enabled: false,
        arbitrary_command_enabled: false,
        token_printed: false,
      };
      controlPlanePairings.set(workerId, revoked);
      return { ok: true, pairing_preview: revoked, token_printed: false };
    },
  );

  app.post<{
    Params: { workerId: string };
    Body: Record<string, unknown>;
  }>("/api/workers/:workerId/heartbeat-ingest", async (request, reply) => {
    const unsafe = findUnsafeControlPlanePayload(request.body);
    if (unsafe.length > 0) return reply.code(400).send(workerIngestRejection(unsafe));
    const workerId = decodeURIComponent(request.params.workerId);
    try {
      const heartbeat = parseWorkerHeartbeat({
        ...fixtureWorkerHeartbeat,
        ...request.body,
        worker_id: safeString(request.body?.worker_id) ?? workerId,
        execution_enabled: false,
        queue_apply_enabled: false,
        token_printed: false,
      });
      if (heartbeat.worker_id !== workerId) {
        return reply.code(400).send({ ok: false, error: "worker_id_mismatch", token_printed: false });
      }
      controlPlaneHeartbeats.set(workerId, heartbeat);
      return reply.code(202).send({
        ok: true,
        heartbeat,
        stored_safe_json_only: true,
        raw_logs_included: false,
        raw_prompts_included: false,
        token_printed: false,
      });
    } catch (error) {
      return reply.code(400).send({ ok: false, error: "invalid_worker_heartbeat", message: error instanceof Error ? error.message : String(error), token_printed: false });
    }
  });

  app.get("/api/operator-approvals", async () => ({
    approvals: [...operatorApprovalRequests.values()].map((request) => ({
      request,
      state: operatorApprovalStates.get(request.approval_request_id) ?? fixtureOperatorApprovalState,
      gate: {
        ...fixtureOperatorApprovalGate,
        approval_request_id: request.approval_request_id,
      },
    })),
    execution_enabled: false,
    remote_execution_enabled: false,
    arbitrary_command_enabled: false,
    token_printed: false,
  }));

  app.post<{ Body: Record<string, unknown> }>(
    "/api/operator-approvals/request-preview",
    async (request, reply) => {
      const unsafe = findUnsafeControlPlanePayload(request.body);
      if (unsafe.length > 0 || safeString(request.body?.shell_command)) {
        return reply.code(400).send(workerIngestRejection([...unsafe, "raw_shell_command_forbidden"]));
      }
      try {
        const approval = parseOperatorApprovalRequest({
          ...fixtureOperatorApprovalRequest,
          ...request.body,
          requested_mode: safeString(request.body?.requested_mode) ?? "preview",
          max_parallel_repo_mutations: 1,
          resource_gate_required: true,
          human_review_required: true,
          finalizer_required: true,
          failure_budget_required: true,
          evidence_retention_required: true,
          audit_required: true,
          token_printed: false,
        });
        operatorApprovalRequests.set(approval.approval_request_id, approval);
        const state: OperatorApprovalState = {
          ...fixtureOperatorApprovalState,
          approval_request_id: approval.approval_request_id,
          approval_state: "pending",
          consumed: false,
          execution_enabled: false,
          remote_execution_enabled: false,
          arbitrary_command_enabled: false,
          token_printed: false,
        };
        operatorApprovalStates.set(approval.approval_request_id, state);
        return reply.code(202).send({
          ok: true,
          approval_request: approval,
          approval_state: state,
          approval_gate: { ...fixtureOperatorApprovalGate, approval_request_id: approval.approval_request_id },
          execution_started: false,
          token_printed: false,
        });
      } catch (error) {
        return reply.code(400).send({ ok: false, error: "invalid_operator_approval_request", message: error instanceof Error ? error.message : String(error), token_printed: false });
      }
    },
  );

  app.post<{ Params: { approvalId: string }; Body: Record<string, unknown> }>(
    "/api/operator-approvals/:approvalId/approve-preview",
    async (request, reply) => {
      return resolveOperatorApprovalPreview(
        decodeURIComponent(request.params.approvalId),
        "approved",
        request.body,
        operatorApprovalRequests,
        operatorApprovalStates,
        reply,
      );
    },
  );

  app.post<{ Params: { approvalId: string }; Body: Record<string, unknown> }>(
    "/api/operator-approvals/:approvalId/reject-preview",
    async (request, reply) => {
      return resolveOperatorApprovalPreview(
        decodeURIComponent(request.params.approvalId),
        "rejected",
        request.body,
        operatorApprovalRequests,
        operatorApprovalStates,
        reply,
      );
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
    const lease = await refreshWorkerActiveLease(store, workerId, new Date(now), addStoredEvent);
    await addStoredEvent(coreEvent("worker.heartbeat", { worker_id: workerId }));
    return { ok: true, worker: presentWorker(store.getWorker(workerId)!, store), heartbeat, lease };
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

  app.post<{ Body: Record<string, unknown> }>("/v1/master-goals", async (request, reply) => {
    const parsed = parsePlanningMasterGoalInput(request.body, store);
    if (!parsed.ok) return reply.code(parsed.status ?? 400).send(parsed.response);
    await store.upsertPlanningMasterGoal(parsed.masterGoal);
    await addStoredEvent(coreEvent("goal.created", { project_id: parsed.masterGoal.project_id, master_goal_id: parsed.masterGoal.master_goal_id, title: parsed.masterGoal.title }));
    return reply.code(201).send({ ok: true, master_goal: parsed.masterGoal });
  });

  app.get<{ Params: { projectId: string } }>("/v1/projects/:projectId/master-goals", async (request, reply) => {
    const projectId = decodeURIComponent(request.params.projectId);
    if (!store.getProject(projectId)) return reply.code(404).send({ ok: false, error: "project_not_found" });
    return { master_goals: store.listPlanningMasterGoals(projectId) };
  });

  app.get<{ Params: { masterGoalId: string } }>("/v1/master-goals/:masterGoalId", async (request, reply) => {
    const masterGoal = store.getPlanningMasterGoal(decodeURIComponent(request.params.masterGoalId));
    if (!masterGoal) return reply.code(404).send({ ok: false, error: "master_goal_not_found" });
    return { master_goal: masterGoal };
  });

  app.post<{ Body: Record<string, unknown> }>("/v1/planning-sessions", async (request, reply) => {
    const parsed = parsePlanningSessionInput(request.body, store);
    if (!parsed.ok) return reply.code(parsed.status ?? 400).send(parsed.response);
    await store.upsertPlanningSession(parsed.session);
    for (const proposal of parsed.proposals) {
      await store.upsertTaskProposal(proposal);
    }
    await addStoredEvent(coreEvent("plan.updated", {
      project_id: parsed.session.project_id,
      master_goal_id: parsed.session.master_goal_id,
      planning_session_id: parsed.session.planning_session_id,
      proposal_count: parsed.proposals.length,
    }));
    return reply.code(201).send({ ok: true, planning_session: parsed.session, proposals: parsed.proposals });
  });

  app.get<{ Querystring: { project_id?: string; master_goal_id?: string; status?: string } }>("/v1/task-proposals", async (request, reply) => {
    if (request.query.status && !PROPOSAL_STATUSES.includes(request.query.status as PlanningProposalStatus))
      return reply.code(400).send({ ok: false, error: "invalid_proposal_status" });
    return {
      proposals: store.listTaskProposals({
        projectId: request.query.project_id,
        masterGoalId: request.query.master_goal_id,
        status: request.query.status,
      }),
    };
  });

  app.get<{ Params: { masterGoalId: string } }>("/v1/master-goals/:masterGoalId/proposals", async (request, reply) => {
    const masterGoalId = decodeURIComponent(request.params.masterGoalId);
    if (!store.getPlanningMasterGoal(masterGoalId)) return reply.code(404).send({ ok: false, error: "master_goal_not_found" });
    return { proposals: store.listTaskProposals({ masterGoalId }) };
  });

  app.get<{ Params: { proposalId: string } }>("/v1/task-proposals/:proposalId", async (request, reply) => {
    const proposal = store.getTaskProposal(decodeURIComponent(request.params.proposalId));
    if (!proposal) return reply.code(404).send({ ok: false, error: "proposal_not_found" });
    return { proposal };
  });

  app.patch<{ Params: { proposalId: string }; Body: Record<string, unknown> }>("/v1/task-proposals/:proposalId", async (request, reply) => {
    const proposal = store.getTaskProposal(decodeURIComponent(request.params.proposalId));
    if (!proposal) return reply.code(404).send({ ok: false, error: "proposal_not_found" });
    const status = safeString(request.body.status) ?? proposal.status;
    if (!PROPOSAL_STATUSES.includes(status as PlanningProposalStatus))
      return reply.code(400).send({ ok: false, error: "invalid_proposal_status" });
    const now = new Date().toISOString();
    const reviewStatus = safeString(request.body.review_status);
    const updated: StoredTaskProposal = {
      ...proposal,
      status: status as PlanningProposalStatus,
      policy_decision: safeString(request.body.policy_decision) ?? proposal.policy_decision,
      review_status: reviewStatus ?? proposal.review_status ?? status,
      review_reason: safeLongString(request.body.review_reason) ?? proposal.review_reason,
      reviewed_by: safeString(request.body.reviewed_by) ?? proposal.reviewed_by,
      reviewed_at: reviewStatus || status !== proposal.status ? now : proposal.reviewed_at,
      approved_by: safeString(request.body.approved_by) ?? proposal.approved_by,
      approved_at: status === "approved" ? (proposal.approved_at ?? now) : proposal.approved_at,
      superseded_by: safeString(request.body.superseded_by) ?? proposal.superseded_by,
      dependencies: safeStringArray(request.body.dependencies) ?? proposal.dependencies,
      updated_at: now,
    };
    await store.upsertTaskProposal(updated);
    return { ok: true, proposal: updated };
  });

  app.post<{ Params: { proposalId: string }; Body: Record<string, unknown> }>("/v1/task-proposals/:proposalId/convert", async (request, reply) => {
    const proposal = store.getTaskProposal(decodeURIComponent(request.params.proposalId));
    if (!proposal) return reply.code(404).send({ ok: false, error: "proposal_not_found" });
    const conversionPolicy = validateProposalConversion(proposal, store.listTaskProposals({ projectId: proposal.project_id }));
    if (!conversionPolicy.ok)
      return reply.code(409).send({ ok: false, error: conversionPolicy.error, reasons: conversionPolicy.reasons });
    const project = store.getProject(proposal.project_id);
    if (!project) return reply.code(404).send({ ok: false, error: "project_not_found" });
    const taskId = safeString(request.body.task_id) ?? `task_${proposal.proposal_id}`;
    if (store.getTask(taskId)) return reply.code(409).send({ ok: false, error: "task_already_exists" });
    const now = new Date().toISOString();
    const requiredCapabilities = proposal.normalized_required_capabilities && proposal.normalized_required_capabilities.length > 0
      ? proposal.normalized_required_capabilities
      : proposal.required_capabilities;
    const task: StoredTask = {
      task_id: taskId,
      project_id: proposal.project_id,
      title: proposal.title,
      body: proposal.body,
      prompt_summary: proposal.prompt_summary ?? proposal.body,
      status: "queued",
      risk: proposal.risk,
      source: "planner",
      task_type: proposal.task_type,
      source_proposal_id: proposal.proposal_id,
      proposal_review_status: proposal.review_status ?? proposal.status,
      proposal_approved_by: proposal.approved_by,
      proposal_approved_at: proposal.approved_at,
      proposal_policy_decision: proposal.policy_decision,
      allowed_paths: proposal.expected_files,
      validation: proposal.evidence_requirements,
      required_capabilities: requiredCapabilities,
      planner_metadata: {
        adapter: proposal.created_by,
        decision: "continue",
        reason: proposal.rationale,
        task_type: proposal.task_type,
        source_proposal_id: proposal.proposal_id,
        proposal_review_status: proposal.review_status ?? proposal.status,
        proposal_policy_decision: proposal.policy_decision,
        proposal_approved_by: proposal.approved_by,
        proposal_approved_at: proposal.approved_at,
        allowed_paths: proposal.expected_files,
        blocked_paths: [],
        validation: proposal.evidence_requirements,
        stop_criteria_status: [],
        created_at: now,
        raw_response_included: false,
        secrets_included: false,
      },
      created_at: now,
      updated_at: now,
    };
    await store.upsertTask(task);
    const updatedProposal: StoredTaskProposal = {
      ...proposal,
      status: "converted",
      review_status: "converted",
      converted_task_id: task.task_id,
      updated_at: now,
    };
    await store.upsertTaskProposal(updatedProposal);
    await recordTaskEvent(task, "task.created", undefined, "Task converted from proposal.", addStoredEvent, store);
    return reply.code(201).send({ ok: true, proposal: updatedProposal, task: withTaskEvents(task, store) });
  });

  app.get<{ Querystring: { project_id?: string; status?: string } }>("/v1/campaigns", async (request, reply) => {
    if (request.query.status && !CAMPAIGN_STATUSES.includes(request.query.status as CampaignStatus))
      return reply.code(400).send({ ok: false, error: "invalid_campaign_status" });
    return { campaigns: store.listCampaigns({ projectId: request.query.project_id, status: request.query.status }) };
  });

  app.post<{ Body: Record<string, unknown> }>("/v1/campaigns", { preHandler: requireWorkerAuth }, async (request, reply) => {
    const parsed = parseCampaignImportInput(request.body, store);
    if (!parsed.ok) return reply.code(parsed.status ?? 400).send(parsed.response);
    await store.upsertCampaign(parsed.campaign);
    for (const step of parsed.steps) await store.upsertCampaignStep(step);
    await recordCampaignEvent(parsed.campaign, "campaign.created", "Campaign created.", addStoredEvent, { step_count: parsed.steps.length });
    return reply.code(201).send({ ok: true, campaign: parsed.campaign, steps: parsed.steps });
  });

  app.get<{ Params: { campaignId: string } }>("/v1/campaigns/:campaignId", async (request, reply) => {
    const campaign = store.getCampaign(decodeURIComponent(request.params.campaignId));
    if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
    return { campaign, steps: store.listCampaignSteps({ campaignId: campaign.campaign_id }) };
  });

  app.get<{ Params: { campaignId: string } }>("/v1/campaigns/:campaignId/control/matrix", async (request, reply) => {
    const campaign = store.getCampaign(decodeURIComponent(request.params.campaignId));
    if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
    return {
      ok: true,
      schema: "skybridge.queue_control_action_matrix.v1",
      campaign_id: campaign.campaign_id,
      action_matrix: queueControlActionMatrix(),
      token_printed: false,
    };
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/control/preview", async (request, reply) => {
    const campaign = store.getCampaign(decodeURIComponent(request.params.campaignId));
    if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
    const response = evaluateQueueControlIntent(campaign, request.body, "preview");
    return reply.code(response.ok ? 200 : 409).send(response);
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/control/apply", { preHandler: requireWorkerAuth }, async (request, reply) => {
    const campaign = store.getCampaign(decodeURIComponent(request.params.campaignId));
    if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
    const response = evaluateQueueControlIntent(campaign, request.body, "apply");
    if (!response.ok) return reply.code(response.allowed ? 400 : 403).send(response);
    const action = safeString(request.body.action);
    const reason = safeString(request.body.reason) ?? "";
    const now = new Date().toISOString();
    const nextStatus: CampaignStatus = action === "safe_pause" ? "paused" : "held";
    const updatedCampaign: StoredCampaign = { ...campaign, status: nextStatus, updated_at: now };
    await store.upsertCampaign(updatedCampaign);
    const auditRecord = queueControlAuditRecord(updatedCampaign, request.body, response, reason, now);
    await store.addAuditRecord(auditRecord);
    return {
      ...response,
      audit_event_id: auditRecord.audit_id,
      campaign: updatedCampaign,
      token_printed: false,
    };
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/import-goal-pack", { preHandler: requireWorkerAuth }, async (request, reply) => {
    const campaignId = decodeURIComponent(request.params.campaignId);
    const parsed = parseCampaignImportInput({ ...request.body, campaign_id: campaignId }, store);
    if (!parsed.ok) return reply.code(parsed.status ?? 400).send(parsed.response);
    await store.upsertCampaign(parsed.campaign);
    for (const step of parsed.steps) await store.upsertCampaignStep(step);
    await recordCampaignEvent(parsed.campaign, "campaign.imported", "Campaign goal pack imported.", addStoredEvent, { step_count: parsed.steps.length });
    return reply.code(201).send({ ok: true, campaign: parsed.campaign, steps: parsed.steps });
  });

  app.get<{ Params: { campaignId: string } }>("/v1/campaigns/:campaignId/steps", async (request, reply) => {
    const campaignId = decodeURIComponent(request.params.campaignId);
    if (!store.getCampaign(campaignId)) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
    return { steps: store.listCampaignSteps({ campaignId }) };
  });

  app.get<{ Params: { campaignId: string; stepId: string } }>("/v1/campaigns/:campaignId/steps/:stepId", async (request, reply) => {
    const step = store.getCampaignStep(decodeURIComponent(request.params.stepId));
    if (!step || step.campaign_id !== decodeURIComponent(request.params.campaignId)) return reply.code(404).send({ ok: false, error: "campaign_step_not_found" });
    return { step };
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/start", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return updateCampaignState(request.params.campaignId, "running", request.body, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/pause", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return updateCampaignState(request.params.campaignId, "paused", request.body, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/hold", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return updateCampaignState(request.params.campaignId, "held", request.body, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/resume", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return updateCampaignState(request.params.campaignId, "running", request.body, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/advance-preview", async (request, reply) => {
    const campaign = store.getCampaign(decodeURIComponent(request.params.campaignId));
    if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
    return { ok: true, gate: evaluateCampaignAdvanceGate(campaign, store, request.body) };
  });

  app.post<{ Params: { campaignId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/advance", { preHandler: requireWorkerAuth }, async (request, reply) => {
    const campaign = store.getCampaign(decodeURIComponent(request.params.campaignId));
    if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
    if (request.body.confirm_advance !== true) return reply.code(400).send({ ok: false, error: "missing_confirm_advance" });
    const gate = evaluateCampaignAdvanceGate(campaign, store, request.body);
    if (gate.decision !== "advance") {
      await recordCampaignEvent(campaign, "campaign.step.advance_blocked", "Campaign advance blocked.", addStoredEvent, gate);
      return reply.code(409).send({ ok: false, error: "campaign_advance_blocked", gate });
    }
    const advisoryGate = safeRecord(request.body.gate_result);
    if (advisoryGate && safeString(advisoryGate.final_decision) && safeString(advisoryGate.final_decision) !== "advance") {
      await recordCampaignEvent(campaign, "campaign.step.advance_blocked", "Campaign advance blocked by advisory gate.", addStoredEvent, advisoryGate);
      return reply.code(409).send({ ok: false, error: "campaign_gate_not_advance", gate: advisoryGate });
    }
    if (!gate.next_step_id) return reply.code(409).send({ ok: false, error: "campaign_next_step_missing", gate });
    const now = new Date().toISOString();
    const step = store.getCampaignStep(gate.next_step_id);
    if (!step) return reply.code(409).send({ ok: false, error: "campaign_next_step_missing", gate });
    const persistedGate = advisoryGate ?? gate;
    const updatedStep: StoredCampaignStep = { ...step, status: "ready", last_gate_result: persistedGate, updated_at: now };
    const updatedCampaign: StoredCampaign = { ...campaign, status: "paused", current_step_id: updatedStep.campaign_step_id, updated_at: now };
    await store.upsertCampaignStep(updatedStep);
    await store.upsertCampaign(updatedCampaign);
    await recordCampaignEvent(updatedCampaign, "campaign.step.gate_previewed", "Campaign step gate previewed.", addStoredEvent, persistedGate);
    if (advisoryGate) {
      await recordCampaignEvent(updatedCampaign, "campaign.step.hermes_gate_evaluated", "Campaign Hermes gate evaluated.", addStoredEvent, advisoryGate);
    }
    await recordCampaignEvent(updatedCampaign, "campaign.step.advance_allowed", "Campaign step advance allowed.", addStoredEvent, persistedGate);
    await recordCampaignEvent(updatedCampaign, "campaign.step.advanced", "Campaign advanced to next step.", addStoredEvent, { from_step_id: campaign.current_step_id, to_step_id: updatedStep.campaign_step_id, gate: persistedGate });
    await recordCampaignEvent(updatedCampaign, "campaign.step.ready", "Campaign step marked ready.", addStoredEvent, persistedGate);
    return { ok: true, campaign: updatedCampaign, step: updatedStep, gate: persistedGate };
  });

  app.post<{ Params: { campaignId: string; stepId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/steps/:stepId/complete", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return finishCampaignStep(request.params.campaignId, request.params.stepId, "completed", request.body, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string; stepId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/steps/:stepId/fail", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return finishCampaignStep(request.params.campaignId, request.params.stepId, "failed", request.body, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string; stepId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/steps/:stepId/attach-evidence", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return attachCampaignEvidence(request.params.campaignId, request.params.stepId, request.body, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string; stepId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/steps/:stepId/execute-preview", async (request, reply) => {
    return previewCampaignStepExecution(request.params.campaignId, request.params.stepId, request.body, store, reply);
  });

  app.post<{ Params: { campaignId: string; stepId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/steps/:stepId/execute", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return executeCampaignStep(request.params.campaignId, request.params.stepId, request.body, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string; stepId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/steps/:stepId/link-task", { preHandler: requireWorkerAuth }, async (request, reply) => {
    const taskId = safeString(request.body.task_id);
    if (!taskId) return reply.code(400).send({ ok: false, error: "missing_task_id" });
    return attachCampaignEvidence(request.params.campaignId, request.params.stepId, {
      linked_task_ids: [taskId],
      evidence_summary: { summary: `Campaign step linked to task ${taskId}.`, created_at: new Date().toISOString(), task_id: taskId },
    }, store, addStoredEvent, reply);
  });

  app.post<{ Params: { campaignId: string; stepId: string }; Body: Record<string, unknown> }>("/v1/campaigns/:campaignId/steps/:stepId/attach-execution-evidence", { preHandler: requireWorkerAuth }, async (request, reply) => {
    return attachCampaignEvidence(request.params.campaignId, request.params.stepId, request.body, store, addStoredEvent, reply);
  });

  app.post<{ Body: Record<string, unknown> }>("/v1/drafts/submit-preview", async (request, reply) => {
    const preview = buildDraftSubmitPreview(request.body, store);
    return reply.code(preview.ok ? 200 : preview.statusCode).send(preview.response);
  });

  app.post<{ Body: Record<string, unknown> }>("/v1/drafts/submit", async (request, reply) => {
    const preview = buildDraftSubmitPreview(request.body, store);
    if (!preview.ok) return reply.code(preview.statusCode).send(preview.response);
    if (
      request.body.confirm_submit !== true ||
      safeString(request.body.confirmation_text) !== DRAFT_SUBMIT_CONFIRMATION_TEXT
    ) {
      return reply.code(400).send(
        draftSubmitEnvelope("skybridge.draft_submit_result.v1", preview.context, {
          ok: false,
          review_status: "blocked",
          review_reason: "missing_exact_confirmation",
          task_created: false,
          campaign_created: false,
          next_safe_action: "enter_exact_confirmation_text_before_submit",
        }),
      );
    }
    const result = await submitReviewedDraft(preview.context, store, addStoredEvent);
    return reply.code(result.statusCode).send(result.response);
  });

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
    const nowDate = new Date();
    if (isActiveLease(task.lease)) {
      if (isExpiredLease(task.lease, nowDate)) {
        const expiredLease = markExpiredLease(task, nowDate);
        const updatedTask: StoredTask = { ...task, lease: expiredLease, updated_at: nowDate.toISOString() };
        await store.upsertTask(updatedTask);
        await recordTaskEvent(updatedTask, "task.updated", workerId, "Task claim blocked by expired lease.", addStoredEvent, store, {
          lease_id: expiredLease?.lease_id,
          lease_status: expiredLease?.lease_status,
          stale_reason: expiredLease?.stale_reason,
        });
        return reply.code(409).send({ ok: false, error: "task_stale_lease", lease: expiredLease });
      }
      return reply.code(409).send({ ok: false, error: "task_active_lease_exists", lease: task.lease });
    }
    const previousLease = task.lease as TaskLease | undefined;
    const currentAttempt = previousLease ? previousLease.current_attempt : 0;
    const maxAttempts = previousLease ? previousLease.max_attempts : DEFAULT_TASK_MAX_ATTEMPTS;
    if (currentAttempt >= maxAttempts && task.status !== "queued") {
      return reply.code(409).send({ ok: false, error: "task_max_attempts_exceeded", lease: task.lease });
    }
    const now = nowDate.toISOString();
    const lease = buildTaskLease(task, workerId, nowDate);
    const updated: StoredTask = {
      ...task,
      status: "claimed",
      assigned_worker_id: workerId,
      claim: { claim_id: `claim_${nanoid()}`, task_id: task.task_id, worker_id: workerId, claimed_at: now },
      lease,
      updated_at: now,
    };
    await store.upsertTask(updated);
    await recordTaskEvent(updated, "task.claimed", workerId, "Task claimed.", addStoredEvent, store, {
      lease_id: lease.lease_id,
      lease_expires_at: lease.lease_expires_at,
      current_attempt: lease.current_attempt,
      max_attempts: lease.max_attempts,
    });
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

  app.post<{ Params: { taskId: string }; Body: Record<string, unknown> }>(
    "/v1/tasks/:taskId/evidence-repair",
    { preHandler: requireWorkerAuth },
    async (request, reply) => {
      const task = store.getTask(decodeURIComponent(request.params.taskId));
      if (!task) return reply.code(404).send({ ok: false, error: "task_not_found" });
      const evidenceSummary = safeEvidenceSummary(request.body.evidence_summary, task.result?.evidence_summary);
      if (!evidenceSummary) return reply.code(400).send({ ok: false, error: "invalid_evidence_summary" });
      const workerId = safeString(request.body.worker_id) ?? task.assigned_worker_id;
      const updated: StoredTask = {
        ...task,
        result: {
          ...task.result,
          summary: safeString(request.body.summary) ?? task.result?.summary,
          result_url: safeString(request.body.result_url) ?? task.result?.result_url,
          pr_url: safeString(request.body.pr_url) ?? task.result?.pr_url,
          error_summary: task.result?.error_summary,
          evidence_summary: evidenceSummary,
        },
        updated_at: new Date().toISOString(),
      };
      await store.upsertTask(updated);
      if (updated.goal_id) await updateGoalProgress(updated.goal_id, store);
      await recordTaskEvent(
        updated,
        "task.evidence_repaired",
        workerId,
        "Task evidence repaired.",
        addStoredEvent,
        store,
        updated.result ? { ...updated.result } : {},
      );
      return { ok: true, task: withTaskEvents(updated, store) };
    },
  );

  app.post<{ Params: { taskId: string }; Body: Record<string, unknown> }>(
    "/v1/tasks/:taskId/hygiene-metadata",
    { preHandler: requireWorkerAuth },
    async (request, reply) => {
      const task = store.getTask(decodeURIComponent(request.params.taskId));
      if (!task) return reply.code(404).send({ ok: false, error: "task_not_found", token_printed: false });

      const projectId = safeString(request.body.project_id);
      if (!projectId || projectId !== task.project_id) {
        return reply.code(400).send({ ok: false, error: "project_id_mismatch", token_printed: false });
      }

      const operation = safeString(request.body.operation);
      if (!operation || !HYGIENE_METADATA_OPERATIONS.includes(operation as typeof HYGIENE_METADATA_OPERATIONS[number])) {
        return reply.code(400).send({ ok: false, error: "invalid_hygiene_operation", token_printed: false });
      }

      const requestedStatus = safeString(request.body.status) ?? safeString(request.body.requested_status);
      if (requestedStatus && ["queued", "claimed", "running"].includes(requestedStatus)) {
        return reply.code(400).send({ ok: false, error: "status_transition_forbidden", token_printed: false });
      }
      if (
        "assigned_worker_id" in request.body ||
        "worker_id" in request.body ||
        "claim" in request.body ||
        "lease" in request.body
      ) {
        return reply.code(400).send({ ok: false, error: "worker_or_lease_mutation_forbidden", token_printed: false });
      }
      if (["queued", "claimed", "running"].includes(task.status)) {
        return reply.code(409).send({ ok: false, error: "active_task_hygiene_metadata_forbidden", token_printed: false });
      }

      const now = new Date().toISOString();
      const reason = safeLongString(request.body.reason) ?? "goal_317_hygiene_metadata_only";
      const policy = safeString(request.body.policy) ?? "goal_317_fixed_metadata_only";
      const existingMetadata = safeRecord(task.hygiene_metadata) ?? {};
      const operationRecord = {
        operation,
        applied_at: now,
        policy,
        reason,
        metadata_only: true,
        no_status_transition: true,
        no_worker_assignment_change: true,
        no_claim_created: true,
        no_lease_created: true,
        no_requeue: true,
        no_codex_invocation: true,
        excluded_from_requeue: operation === "mark_excluded_from_requeue" ? true : undefined,
      };
      const history = Array.isArray(existingMetadata.history) ? existingMetadata.history.slice(0, 25) : [];
      const updated: StoredTask = {
        ...task,
        status: task.status,
        assigned_worker_id: task.assigned_worker_id,
        claim: task.claim,
        lease: task.lease,
        hygiene_metadata: {
          ...existingMetadata,
          goal_317_last_operation: operation,
          goal_317_updated_at: now,
          excluded_from_worker_scheduling:
            operation === "mark_excluded_from_requeue" ||
            operation === "mark_keep_blocked" ||
            operation === "mark_archived_by_operator_policy" ||
            existingMetadata.excluded_from_worker_scheduling === true,
          history: [...history, operationRecord],
        },
        updated_at: now,
      };

      await store.upsertTask(updated);
      await recordTaskEvent(updated, "task.updated", undefined, "Task hygiene metadata updated.", addStoredEvent, store, {
        operation,
        metadata_only: true,
        no_status_transition: true,
        no_worker_assignment_change: true,
        no_claim_created: true,
        no_lease_created: true,
        no_requeue: true,
        no_codex_invocation: true,
      });
      return { ok: true, task: withTaskEvents(updated, store), token_printed: false };
    },
  );

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

  app.post<{ Params: { taskId: string }; Body: Record<string, unknown> }>(
    "/v1/tasks/:taskId/lease-recovery",
    { preHandler: requireWorkerAuth },
    async (request, reply) => {
      const task = store.getTask(decodeURIComponent(request.params.taskId));
      if (!task) return reply.code(404).send({ ok: false, error: "task_not_found" });
      const action = safeString(request.body.action);
      const reason = safeLongString(request.body.reason);
      const requestedLeaseId = safeString(request.body.lease_id);
      const workerId = safeString(request.body.worker_id) ?? task.assigned_worker_id;
      if (!action || !["release-stale", "mark-abandoned", "requeue-safe"].includes(action)) {
        return reply.code(400).send({ ok: false, error: "invalid_lease_recovery_action" });
      }
      if (!reason) return reply.code(400).send({ ok: false, error: "missing_recovery_reason" });
      if (task.task_id === "task_proposal-59a0236fb69800cd") {
        return reply.code(409).send({ ok: false, error: "historical_blocked_task_not_recoverable" });
      }
      if (!task.lease) return reply.code(409).send({ ok: false, error: "task_has_no_lease" });
      if (requestedLeaseId && requestedLeaseId !== task.lease.lease_id) {
        return reply.code(409).send({ ok: false, error: "lease_id_mismatch", lease: task.lease });
      }
      const now = new Date();
      const expired = isExpiredLease(task.lease, now);
      const taskInactive = !["queued", "claimed", "running"].includes(task.status);
      if (action !== "requeue-safe" && task.lease.lease_status !== "active" && task.lease.lease_status !== "expired") {
        return reply.code(409).send({ ok: false, error: "lease_not_recoverable", lease: task.lease });
      }
      if (action !== "requeue-safe" && !expired && !taskInactive && task.lease.lease_status !== "expired") {
        return reply.code(409).send({ ok: false, error: "lease_not_stale", lease: task.lease });
      }
      if (action === "requeue-safe") {
        const blockedType = ["deploy", "production", "secret", "secrets", "github-settings", "branch-protection", "server-config", "server-root-config"].includes(task.task_type ?? "");
        if (task.risk !== "low" || blockedType || task.status === "completed" || task.status === "cancelled") {
          return reply.code(409).send({ ok: false, error: "task_not_safe_to_requeue" });
        }
      }
      const recoveredLease: TaskLease = {
        ...task.lease,
        lease_status: action === "mark-abandoned" ? "abandoned" : "released",
        released_at: now.toISOString(),
        stale_reason: `${action}:${reason}`,
      };
      const updated: StoredTask = {
        ...task,
        status: action === "requeue-safe" ? "queued" : task.status,
        assigned_worker_id: action === "requeue-safe" ? undefined : task.assigned_worker_id,
        claim: action === "requeue-safe" ? undefined : task.claim,
        lease: recoveredLease,
        updated_at: now.toISOString(),
      };
      await store.upsertTask(updated);
      await recordTaskEvent(updated, action === "requeue-safe" ? "task.requeued" : "task.updated", workerId, `Task lease recovery: ${action}.`, addStoredEvent, store, {
        lease_id: recoveredLease.lease_id,
        lease_status: recoveredLease.lease_status,
        stale_reason: recoveredLease.stale_reason,
        recovery_action: action,
        recovery_reason: reason,
      });
      return { ok: true, action, task: withTaskEvents(updated, store) };
    },
  );

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

  app.get("/v1/manual-tasks/providers", async () => manualTaskProviderList());
  app.post<{ Body: ManualTaskRunInput }>(
    "/v1/manual-tasks/run-next/mock",
    async (request) => runManualTaskMock(request.body),
  );
  app.post<{ Body: ManualTaskRunInput }>(
    "/v1/manual-tasks/run-next/hermes-preview",
    async (request) => runManualTaskHermesPreview(request.body),
  );
  app.post<{ Body: ManualTaskRunInput }>(
    "/v1/manual-tasks/run-next/skybridge-hermes",
    async (request) => runManualTaskSkyBridgeHermes(request.body),
  );

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

type QueueControlMode = "read" | "preview" | "apply";
type QueueControlActionClass =
  | "read_only"
  | "preview"
  | "heartbeat_only"
  | "safe_stop_pause"
  | "armed_execution"
  | "forbidden";

interface QueueControlMatrixEntry {
  action: string;
  class: QueueControlActionClass;
  allowed_modes: QueueControlMode[];
  apply_allowed: boolean;
  reason_required: boolean;
  human_approval_required: boolean;
  requires_arm_lease: boolean;
  blockers: string[];
  warnings: string[];
  summary: string;
  token_printed: false;
}

function queueControlActionMatrix(): QueueControlMatrixEntry[] {
  const readOnly = ["refresh_status", "report", "preflight"].map((action) => ({
    action,
    class: "read_only" as const,
    allowed_modes: ["read" as const],
    apply_allowed: false,
    reason_required: false,
    human_approval_required: false,
    requires_arm_lease: false,
    blockers: [],
    warnings: [],
    summary: "Read-only queue-control action.",
    token_printed: false as const,
  }));
  const safe = ["safe_pause", "stop_queue", "emergency_stop"].map((action) => ({
    action,
    class: "safe_stop_pause" as const,
    allowed_modes: ["preview" as const, "apply" as const],
    apply_allowed: true,
    reason_required: true,
    human_approval_required: false,
    requires_arm_lease: false,
    blockers: [],
    warnings: ["audit_required", "does_not_start_worker"],
    summary: "Low-risk queue stop or pause action.",
    token_printed: false as const,
  }));
  const preview = ["resume_preview", "start_one_preview", "start_queue_preview"].map((action) => ({
    action,
    class: "preview" as const,
    allowed_modes: ["preview" as const],
    apply_allowed: false,
    reason_required: false,
    human_approval_required: false,
    requires_arm_lease: false,
    blockers: [],
    warnings: ["preview_only_no_mutation"],
    summary: "Preview only; no campaign mutation or task creation.",
    token_printed: false as const,
  }));
  const armed = ["start_one_apply", "start_queue_apply"].map((action) => ({
    action,
    class: "armed_execution" as const,
    allowed_modes: [],
    apply_allowed: false,
    reason_required: true,
    human_approval_required: true,
    requires_arm_lease: true,
    blockers: ["execution_apply_deferred_until_worker_service_mode"],
    warnings: [],
    summary: "Armed execution is modeled but forbidden until a later worker service goal.",
    token_printed: false as const,
  }));
  const forbidden = ["start_all", "arbitrary_shell"].map((action) => ({
    action,
    class: "forbidden" as const,
    allowed_modes: [],
    apply_allowed: false,
    reason_required: true,
    human_approval_required: true,
    requires_arm_lease: false,
    blockers: ["forbidden_action"],
    warnings: [],
    summary: "Forbidden queue-control action.",
    token_printed: false as const,
  }));
  return [...readOnly, ...safe, ...preview, ...armed, ...forbidden];
}

function queueControlStateHash(campaign: StoredCampaign): string {
  return createHash("sha256")
    .update([
      campaign.campaign_id,
      campaign.current_step_id ?? "",
      campaign.status,
      campaign.updated_at,
    ].join("|"))
    .digest("hex")
    .slice(0, 16);
}

function evaluateQueueControlIntent(
  campaign: StoredCampaign,
  body: Record<string, unknown>,
  mode: QueueControlMode,
) {
  const action = safeString(body.action) ?? "";
  const matrixEntry = queueControlActionMatrix().find((entry) => entry.action === action);
  const blockers = [...(matrixEntry?.blockers ?? [])];
  const warnings = [...(matrixEntry?.warnings ?? [])];
  const stateHash = queueControlStateHash(campaign);
  const targetRevision = safeString(body.target_revision);
  if (!matrixEntry) blockers.push("unknown_action");
  if (!targetRevision) blockers.push("target_revision_required");
  else if (targetRevision !== stateHash) blockers.push("target_revision_mismatch");
  if (matrixEntry && !matrixEntry.allowed_modes.includes(mode)) blockers.push("mode_not_allowed");
  if (mode === "apply" && matrixEntry && !matrixEntry.apply_allowed) blockers.push("apply_forbidden_in_goal_192");
  if (mode === "apply" && matrixEntry?.reason_required && !safeString(body.reason)) blockers.push("reason_required");
  if (["start_one_apply", "start_queue_apply", "start_all", "arbitrary_shell"].includes(action)) {
    blockers.push("no_execution_enablement_in_goal_192");
  }
  const allowed = Boolean(matrixEntry) && blockers.length === 0;
  return {
    schema: "skybridge.queue_control_action_response.v1",
    ok: allowed,
    mode,
    action: action || "unknown",
    allowed,
    blockers,
    warnings,
    state_hash: stateHash,
    token_printed: false as const,
  };
}

function queueControlAuditRecord(
  campaign: StoredCampaign,
  body: Record<string, unknown>,
  response: ReturnType<typeof evaluateQueueControlIntent>,
  reason: string,
  now: string,
): StoredAuditRecord {
  const auditId = `audit_queue_control_${nanoid(12)}`;
  return {
    audit_id: auditId,
    time: now,
    action: `queue_control.${response.action}`,
    actor: safeString(body.actor) ?? "operator",
    source_adapter: `skybridge/${safeString(body.source) ?? "server"}`,
    safety_decision: response.allowed ? "queue_control_safe_action_applied" : "queue_control_blocked",
    immutable_event_id: auditId,
    redaction_policy_version: "packages/event-schema/src/redaction-rules.json",
    raw_payload_included: false,
    queue_control: {
      schema: "skybridge.queue_control_audit_event.v1",
      audit_event_id: auditId,
      action: response.action,
      source: safeString(body.source) ?? "server",
      mode: response.mode,
      actor: safeString(body.actor) ?? "operator",
      campaign_id: campaign.campaign_id,
      current_step_id: campaign.current_step_id ?? "",
      target_revision: safeString(body.target_revision) ?? "",
      reason,
      blockers: response.blockers,
      warnings: response.warnings,
      created_at: now,
      token_printed: false,
    },
  } as StoredAuditRecord;
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

function manualTaskProviderList() {
  const config = getServerHermesConfig();
  return {
    schema: "skybridge.manual_task_provider_list.v1",
    default_provider_id: "mock" as const,
    providers: [
      manualTaskProviderRecord("mock", "enabled", true, false, false, "mock_default"),
      manualTaskProviderRecord(
        "skybridge_server_hermes",
        config.configured ? "configured_disabled_until_requested" : "disabled_missing_server_config",
        config.configured,
        config.configured,
        config.configured,
        config.reason,
      ),
      manualTaskProviderRecord(
        "hermes_deepseek",
        "deprecated_preview_no_network",
        false,
        false,
        false,
        "deprecated_local_direct_provider_preview_only",
      ),
    ],
    server_mediated_provider_id: "skybridge_server_hermes",
    local_direct_provider_id: "hermes_deepseek",
    local_direct_deprecated: true,
    client_secret_required: false,
    live_call_disabled_by_default: true as const,
    token_printed: false as const,
  };
}

function manualTaskProviderRecord(
  providerId: ManualTaskProviderId,
  status: string,
  configured: boolean,
  networkEnabled: boolean,
  cloudHermesEnabled: boolean,
  reason: string,
): ManualTaskProviderRecord {
  return {
    schema: "skybridge.manual_task_provider.v1",
    provider_id: providerId,
    status,
    configured,
    deterministic: providerId === "mock",
    network_enabled: networkEnabled,
    hermes_live_call_enabled: false,
    server_mediated_llm_inference_enabled:
      providerId === "skybridge_server_hermes" && configured,
    cloud_hermes_provider_enabled:
      providerId === "skybridge_server_hermes" && cloudHermesEnabled,
    remote_llm_inference_enabled: false,
    disabled_by_default: providerId !== "mock",
    deprecated: providerId === "hermes_deepseek" ? true : undefined,
    preview_only: providerId === "hermes_deepseek" ? true : undefined,
    ci_disabled: process.env.CI === "true" || process.env.GITHUB_ACTIONS === "true",
    config_values_redacted: true,
    raw_request_persisted: false,
    raw_response_persisted: false,
    reason,
    token_printed: false,
  };
}

function runManualTaskMock(input: ManualTaskRunInput | undefined): ManualTaskResultRecord {
  const started = Date.now();
  const prompt = manualTaskInputPreview(input);
  const preview = `Mock reply ${sha256Text(prompt).slice(0, 12)}: recorded sanitized server manual task; classification=${commandTextDetected(prompt) ? "command_text_detected_no_execution" : "safe_question"}.`;
  return manualTaskResult({
    providerId: "mock",
    providerStatus: "mock_default",
    status: "succeeded",
    resultPreview: preview,
    durationMs: Date.now() - started,
    taskId: safeString(input?.task_id),
  });
}

function runManualTaskHermesPreview(input: ManualTaskRunInput | undefined): ManualTaskResultRecord {
  const started = Date.now();
  const prompt = manualTaskInputPreview(input);
  const preview = `Hermes local-direct preview ${sha256Text(prompt).slice(0, 12)}: deprecated preview-only provider; no network call performed.`;
  return manualTaskResult({
    providerId: "hermes_deepseek",
    providerStatus: "deprecated_preview_no_network",
    status: "succeeded",
    resultPreview: preview,
    durationMs: Date.now() - started,
    taskId: safeString(input?.task_id),
  });
}

async function runManualTaskSkyBridgeHermes(input: ManualTaskRunInput | undefined): Promise<ManualTaskResultRecord> {
  const started = Date.now();
  const config = getServerHermesConfig();
  if (!config.configured || !config.apiBase || !config.apiKey) {
    return manualTaskResult({
      providerId: "skybridge_server_hermes",
      providerStatus: "disabled_missing_server_config",
      status: "blocked",
      resultPreview: `SkyBridge server Hermes blocked: ${config.reason}.`,
      durationMs: Date.now() - started,
      errorSummary: config.reason,
      taskId: safeString(input?.task_id),
      serverMediated: false,
      cloudHermesEnabled: false,
    });
  }
  const hermesConfig = {
    ...config,
    apiBase: config.apiBase,
    apiKey: config.apiKey,
  };

  try {
    const capabilities = await callHermesJson(hermesConfig, "/v1/capabilities", { method: "GET" });
    const prompt = buildManualTaskHermesPrompt(manualTaskInputPreview(input));
    const response = await callHermesJson(hermesConfig, "/v1/responses", {
      method: "POST",
      body: {
        input: prompt,
        max_response_chars: config.maxResponseChars,
        metadata: {
          caller: "skybridge_manual_task_queue",
          output_execution_enabled: false,
        },
      },
    });
    const content = extractHermesResponseText(response) ?? "Hermes returned no text content.";
    const preview = safePreview(content, config.maxResponseChars);
    return manualTaskResult({
      providerId: "skybridge_server_hermes",
      providerStatus: `cloud_hermes_${safePreview(extractHermesCapabilityStatus(capabilities), 60)}`,
      status: "succeeded",
      resultPreview: preview,
      durationMs: Date.now() - started,
      taskId: safeString(input?.task_id),
      liveCallPerformed: true,
      serverMediated: true,
      cloudHermesEnabled: true,
    });
  } catch (error) {
    const summary = safeErrorSummary(error);
    return manualTaskResult({
      providerId: "skybridge_server_hermes",
      providerStatus: "cloud_hermes_error",
      status: "failed",
      resultPreview: `SkyBridge server Hermes failed safely: ${summary}.`,
      durationMs: Date.now() - started,
      errorSummary: summary,
      taskId: safeString(input?.task_id),
      liveCallPerformed: false,
      serverMediated: true,
      cloudHermesEnabled: true,
    });
  }
}

function manualTaskResult(input: {
  providerId: ManualTaskProviderId;
  providerStatus: string;
  status: "succeeded" | "failed" | "blocked";
  resultPreview: string;
  durationMs: number;
  taskId?: string;
  errorSummary?: string;
  liveCallPerformed?: boolean;
  serverMediated?: boolean;
  cloudHermesEnabled?: boolean;
}): ManualTaskResultRecord {
  const preview = safePreview(input.resultPreview, 240);
  return {
    schema: "skybridge.manual_task_result.v1",
    task_id: input.taskId,
    provider_id: input.providerId,
    provider_status: input.providerStatus,
    status: input.status,
    result_preview: preview,
    result_hash: sha256Text(preview),
    duration_ms: Math.max(0, input.durationMs),
    error_summary: safePreview(input.errorSummary ?? "", 200),
    server_mediated_llm_inference_enabled: input.serverMediated === true,
    cloud_hermes_provider_enabled: input.cloudHermesEnabled === true,
    live_call_performed: input.liveCallPerformed === true,
    remote_llm_inference_enabled: false,
    output_executed: false,
    command_executed: false,
    workunit_created: false,
    task_created: false,
    task_claim_created: false,
    task_pr_created: false,
    remote_execution_enabled: false,
    arbitrary_command_enabled: false,
    queue_apply_enabled: false,
    raw_request_persisted: false,
    raw_response_persisted: false,
    token_printed: false,
  };
}

function getServerHermesConfig(): ServerHermesConfig {
  const apiBase = process.env.HERMES_API_BASE?.trim().replace(/\/+$/, "");
  const tokenFile = process.env.HERMES_API_KEY_FILE?.trim() ?? process.env.HERMES_TOKEN_FILE?.trim();
  let apiKey = process.env.HERMES_API_KEY?.trim();
  if (!apiKey && tokenFile && existsSync(tokenFile)) {
    apiKey = readFileSync(tokenFile, "utf8").split(/\r?\n/).map((line) => line.trim()).find(Boolean);
  }
  const timeoutMs = Number.parseInt(process.env.HERMES_TIMEOUT_MS ?? "", 10);
  const maxResponseChars = Number.parseInt(process.env.HERMES_MAX_RESPONSE_CHARS ?? "", 10);
  const boundedTimeoutMs = Number.isFinite(timeoutMs) && timeoutMs > 0 ? Math.min(timeoutMs, 120_000) : 60_000;
  const boundedMaxChars = Number.isFinite(maxResponseChars) && maxResponseChars > 0 ? Math.min(maxResponseChars, 8000) : 2000;
  const missing = [
    apiBase ? "" : "HERMES_API_BASE",
    apiKey ? "" : tokenFile ? "HERMES_API_KEY_FILE_VALUE" : "HERMES_API_KEY_OR_FILE",
  ].filter(Boolean);
  return {
    configured: missing.length === 0,
    apiBase,
    apiKey,
    timeoutMs: boundedTimeoutMs,
    maxResponseChars: boundedMaxChars,
    reason: missing.length === 0 ? "server_configured_secret_redacted" : `missing_${missing.join("_")}`,
  };
}

async function callHermesJson(
  config: ServerHermesConfig & { apiBase: string; apiKey: string },
  path: "/v1/capabilities" | "/v1/responses",
  options: { method: "GET" } | { method: "POST"; body: Record<string, unknown> },
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
  try {
    const response = await fetch(`${config.apiBase}${path}`, {
      method: options.method,
      headers: {
        authorization: `Bearer ${config.apiKey}`,
        "content-type": "application/json",
      },
      body: options.method === "POST" ? JSON.stringify(options.body) : undefined,
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`hermes_http_${response.status}`);
    return await response.json() as unknown;
  } finally {
    clearTimeout(timeout);
  }
}

function buildManualTaskHermesPrompt(inputPreview: string): string {
  return [
    "You are answering a SkyBridge Manual Task Queue request through the SkyBridge server Hermes adapter.",
    "Do not execute commands or claim that a command ran.",
    "Do not request or reveal secrets.",
    "Return a concise safe answer for a human operator.",
    "",
    "Sanitized manual task input preview:",
    inputPreview,
  ].join("\n");
}

function manualTaskInputPreview(input: ManualTaskRunInput | undefined): string {
  return safePreview(safeString(input?.input_preview) ?? safeString(input?.question) ?? "No manual task input provided.", 200);
}

function commandTextDetected(value: string): boolean {
  return /(cmd|command|shell|powershell|pwsh|bash|curl|wget)\s*[:=]|[;&|`$<>]/i.test(value);
}

function extractHermesResponseText(input: unknown): string | undefined {
  if (typeof input === "string") return input;
  const record = safeRecord(input);
  if (!record) return undefined;
  const direct = safeString(record.output_text) ?? safeString(record.text) ?? safeString(record.content);
  if (direct) return direct;
  const output = Array.isArray(record.output) ? record.output : undefined;
  const textParts = output
    ?.flatMap((item) => {
      const itemRecord = safeRecord(item);
      const content = Array.isArray(itemRecord?.content) ? itemRecord.content : [];
      return content.map((part) => {
        const partRecord = safeRecord(part);
        return safeString(partRecord?.text);
      });
    })
    .filter((value): value is string => !!value);
  return textParts && textParts.length > 0 ? textParts.join(" ") : undefined;
}

function extractHermesCapabilityStatus(input: unknown): string {
  const record = safeRecord(input);
  return safeString(record?.status) ?? safeString(record?.model) ?? "capabilities_ok";
}

function safeErrorSummary(error: unknown): string {
  if (error instanceof Error && error.name === "AbortError") return "timeout";
  if (error instanceof Error) return safePreview(error.message, 120);
  return "unknown_error";
}

function safePreview(input: string, maxLength: number): string {
  const redacted = input
    .replace(/authorization\s*[:=]\s*bearer\s+\S+/gi, "authorization=[REDACTED]")
    .replace(/bearer\s+[A-Za-z0-9_.-]{12,}/gi, "bearer [REDACTED]")
    .replace(/sk-[A-Za-z0-9_-]{20,}/gi, "[REDACTED]")
    .replace(/gh[pousr]_[A-Za-z0-9_]{20,}/gi, "[REDACTED]")
    .replace(/(token|password|secret|cookie|api[_-]?key)\s*[:=]\s*\S+/gi, "$1=[REDACTED]")
    .replace(/\s+/g, " ")
    .trim();
  if (redacted.length <= maxLength) return redacted;
  return `${redacted.slice(0, Math.max(0, maxLength - 3))}...`;
}

function sha256Text(input: string): string {
  return createHash("sha256").update(input, "utf8").digest("hex");
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

function safeRecord(input: unknown): Record<string, unknown> | undefined {
  return input && typeof input === "object" && !Array.isArray(input)
    ? input as Record<string, unknown>
    : undefined;
}

function controlPlaneWorkerView(
  worker: WorkerRegistration,
  pairing: WorkerPairingPreview | undefined,
  heartbeat: ControlPlaneWorkerHeartbeat | undefined,
) {
  return {
    identity: {
      schema: "skybridge.worker_identity.v1",
      worker_id: worker.worker_id,
      device_id_hash: worker.device_id_hash,
      display_name: worker.display_name,
      repo: worker.repo,
      branch: worker.branch,
      commit: worker.commit,
      token_printed: false,
    },
    capabilities: {
      schema: "skybridge.worker_capability_summary.v1",
      capabilities: worker.capabilities,
      resource_policy_summary: worker.resource_policy_summary,
      resident_enabled: worker.resident_enabled,
      execution_enabled: false,
      queue_apply_enabled: false,
      remote_execution_enabled: false,
      arbitrary_command_enabled: false,
      token_printed: false,
    },
    connection_state: {
      schema: "skybridge.worker_connection_state.v1",
      worker_id: worker.worker_id,
      paired: pairing?.paired ?? worker.paired,
      pairing_state: pairing?.pairing_state ?? worker.pairing_state,
      resident_enabled: worker.resident_enabled,
      execution_enabled: false,
      queue_apply_enabled: false,
      remote_execution_enabled: false,
      arbitrary_command_enabled: false,
      token_printed: false,
    },
    registration: worker,
    pairing_preview: pairing,
    heartbeat,
    token_printed: false,
  };
}

function workerIngestRejection(reasons: string[]) {
  return {
    schema: "skybridge.worker_ingest_rejection.v1",
    ok: false,
    error: "unsafe_worker_ingest_rejected",
    reasons: [...new Set(reasons)],
    token_printed: false,
  };
}

function localAuthRejection(reasons: string[]) {
  return {
    schema: "skybridge.local_auth_rejection.v1",
    ok: false,
    accepted: false,
    error: "local_auth_gate_rejected",
    reasons: [...new Set(reasons)],
    execution_enabled: false,
    queue_apply_enabled: false,
    remote_execution_enabled: false,
    arbitrary_command_enabled: false,
    token_printed: false,
  };
}

function localAuthSafeMetadata(route: string) {
  return {
    schema: "skybridge.local_auth_gate.v1",
    route,
    accepted: true,
    fixture_authenticated: true,
    public_safe_fixture_endpoint: false,
    safe_metadata_only: true,
    allowed_read_scope: ["safe_metadata", "status", "preview"],
    auth_does_not_enable_execution: true,
    release_gate_required: true,
    resource_gate_required: true,
    failure_gate_required: true,
    evidence_gate_required: true,
    audit_gate_required: true,
    human_review_gate_required: true,
    execution_enabled: false,
    queue_apply_enabled: false,
    remote_execution_enabled: false,
    arbitrary_command_enabled: false,
    token_printed: false,
  };
}

function evaluateLocalAuthPreviewRequest(input: {
  origin?: string;
  fixtureAuth?: string;
  payload?: Record<string, unknown>;
}) {
  const reasons: string[] = [];
  const origin = input.origin ?? "";
  if (!isAllowedLoopbackOrigin(origin)) reasons.push("remote_origin_forbidden");
  if (!input.fixtureAuth) reasons.push("unauthenticated_preview_request");
  if (input.fixtureAuth && !["fixture-hash", "session-fixture-hash"].includes(input.fixtureAuth)) {
    reasons.push("invalid_fixture_auth");
  }
  reasons.push(...findUnsafeControlPlanePayload(input.payload ?? {}));
  if (containsExecutionRequest(input.payload ?? {})) reasons.push("execution_request_forbidden");
  if (reasons.length > 0) return localAuthRejection(reasons);
  return localAuthSafeMetadata("local-auth-preview");
}

function isAllowedLoopbackOrigin(origin: string): boolean {
  if (origin === "repo-local-dev-fixture") return true;
  try {
    const parsed = new URL(origin);
    return ["localhost", "127.0.0.1", "::1"].includes(parsed.hostname);
  } catch {
    return false;
  }
}

function containsExecutionRequest(input: unknown): boolean {
  if (!input || typeof input !== "object") return false;
  for (const [key, value] of Object.entries(input)) {
    const lower = key.toLowerCase();
    if (
      [
        "execute",
        "execution_enabled",
        "remote_execution_enabled",
        "queue_apply",
        "queue_apply_enabled",
        "run_apply",
        "start_all",
        "start_queue",
        "claim_task",
        "shell_command",
        "raw_shell_command",
        "command_text",
      ].includes(lower)
    ) {
      return true;
    }
    if (typeof value === "object" && containsExecutionRequest(value)) return true;
    if (typeof value === "string" && /(?:pwsh|powershell|bash|cmd\.exe|start-all|start-queue|resume\s+-Apply)/i.test(value)) {
      return true;
    }
  }
  return false;
}

function findUnsafeControlPlanePayload(input: unknown): string[] {
  const reasons: string[] = [];
  visitUnsafePayload(input, [], reasons);
  return [...new Set(reasons)];
}

function visitUnsafePayload(input: unknown, path: string[], reasons: string[]): void {
  if (input === true && path.at(-1) === "token_printed") {
    reasons.push("token_printed_true_forbidden");
    return;
  }
  if (typeof input === "string") {
    if (/Bearer\s+[A-Za-z0-9._~+/-]+=*/i.test(input)) reasons.push("bearer_token_forbidden");
    if (/-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----/i.test(input)) reasons.push("private_key_forbidden");
    if (/Authorization\s*:/i.test(input)) reasons.push("authorization_header_forbidden");
    if (/Cookie\s*:/i.test(input)) reasons.push("cookie_forbidden");
    return;
  }
  if (Array.isArray(input)) {
    input.forEach((item, index) => visitUnsafePayload(item, [...path, String(index)], reasons));
    return;
  }
  if (!input || typeof input !== "object") return;
  for (const [key, value] of Object.entries(input)) {
    const lower = key.toLowerCase();
    if (/^(raw_)?(log|logs|stdout|stderr|prompt|prompts|transcript|transcripts|worker_log|worker_logs|ci_log|ci_logs|github_log|github_logs|diff|diffs)$/.test(lower)) {
      reasons.push(`${lower}_forbidden`);
      continue;
    }
    if (/authorization/.test(lower)) {
      reasons.push("authorization_header_forbidden");
      continue;
    }
    if (/cookie/.test(lower)) {
      reasons.push("cookie_forbidden");
      continue;
    }
    if (/private.*key|token|secret/.test(lower) && lower !== "token_printed") {
      reasons.push(`${lower}_forbidden`);
      continue;
    }
    if (/env|environment/.test(lower) && (lower.includes("dump") || lower === "env" || lower === "environment")) {
      reasons.push("environment_dump_forbidden");
      continue;
    }
    visitUnsafePayload(value, [...path, lower], reasons);
  }
}

async function resolveOperatorApprovalPreview(
  approvalId: string,
  decision: "approved" | "rejected",
  body: Record<string, unknown> | undefined,
  requests: Map<string, OperatorApprovalRequest>,
  states: Map<string, OperatorApprovalState>,
  reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
) {
  const unsafe = findUnsafeControlPlanePayload(body ?? {});
  if (unsafe.length > 0) return reply.code(400).send(workerIngestRejection(unsafe));
  const request = requests.get(approvalId);
  if (!request) return reply.code(404).send({ ok: false, error: "approval_not_found", token_printed: false });
  const current = states.get(approvalId);
  if (current?.consumed || current?.approval_state === "consumed") {
    return reply.code(409).send({ ok: false, error: "approval_already_consumed", token_printed: false });
  }
  const now = new Date();
  const expiresAt = Date.parse(request.expires_at);
  const state: OperatorApprovalState = {
    schema: "skybridge.operator_approval_state.v1",
    approval_request_id: approvalId,
    approval_state: Number.isFinite(expiresAt) && expiresAt <= now.getTime() ? "expired" : decision,
    decision_reason: safeString(body?.decision_reason) ?? `${decision}_preview_only`,
    consumed: false,
    execution_enabled: false,
    remote_execution_enabled: false,
    arbitrary_command_enabled: false,
    token_printed: false,
  };
  states.set(approvalId, state);
  return {
    ok: true,
    approval_state: state,
    decision: {
      schema: "skybridge.operator_approval_decision.v1",
      approval_request_id: approvalId,
      decision,
      decision_reason: state.decision_reason,
      decided_by: safeString(body?.decided_by) ?? "local-operator",
      decided_at: now.toISOString(),
      execution_started: false,
      token_printed: false,
    },
    approval_gate: {
      ...fixtureOperatorApprovalGate,
      approval_request_id: approvalId,
    },
    execution_started: false,
    token_printed: false,
  };
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

function safeOptionalBoolean(input: unknown): boolean | undefined {
  return typeof input === "boolean" ? input : undefined;
}

function safeFalseOnlyBoolean(input: unknown): false | undefined {
  return input === false ? false : undefined;
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

function parsePlanningMasterGoalInput(input: Record<string, unknown> | undefined, store: EventStore):
  | { ok: true; masterGoal: StoredPlanningMasterGoal }
  | { ok: false; status?: number; response: QueryErrorResponse | { ok: false; error: string } } {
  const now = new Date().toISOString();
  if (!input || typeof input !== "object") return { ok: false, response: invalidQuery("body", "Expected a master goal object.").response };
  const projectId = safeString(input.project_id);
  const title = safeString(input.title);
  if (!projectId) return { ok: false, response: invalidQuery("project_id", "Expected a project id.").response };
  if (!title) return { ok: false, response: invalidQuery("title", "Expected a bounded master goal title.").response };
  if (!store.getProject(projectId)) return { ok: false, status: 404, response: { ok: false, error: "project_not_found" } };
  const priority = safeString(input.priority) ?? "normal";
  if (!GOAL_PRIORITIES.includes(priority as GoalPriority)) return { ok: false, response: invalidQuery("priority", "Expected a valid goal priority.").response };
  return {
    ok: true,
    masterGoal: {
      master_goal_id: safeString(input.master_goal_id) ?? slugId("master_goal", title),
      project_id: projectId,
      title,
      description: safeLongString(input.description),
      source: safeString(input.source) ?? "manual",
      priority: priority as GoalPriority,
      constraints: safeStringArray(input.constraints) ?? [],
      acceptance_criteria: safeStringArray(input.acceptance_criteria) ?? [],
      stop_conditions: safeStringArray(input.stop_conditions) ?? [],
      created_at: now,
      updated_at: now,
    },
  };
}

function parsePlanningSessionInput(input: Record<string, unknown> | undefined, store: EventStore):
  | { ok: true; session: StoredPlanningSession; proposals: StoredTaskProposal[] }
  | { ok: false; status?: number; response: QueryErrorResponse | { ok: false; error: string } } {
  const now = new Date().toISOString();
  if (!input || typeof input !== "object") return { ok: false, response: invalidQuery("body", "Expected a planning session object.").response };
  const masterGoalId = safeString(input.master_goal_id);
  const projectId = safeString(input.project_id);
  if (!masterGoalId) return { ok: false, response: invalidQuery("master_goal_id", "Expected a master goal id.").response };
  if (!projectId) return { ok: false, response: invalidQuery("project_id", "Expected a project id.").response };
  const masterGoal = store.getPlanningMasterGoal(masterGoalId);
  if (!masterGoal) return { ok: false, status: 404, response: { ok: false, error: "master_goal_not_found" } };
  if (masterGoal.project_id !== projectId) return { ok: false, response: invalidQuery("project_id", "Project does not match master goal.").response };
  const plannerAdapter = safePlannerAdapterAuditMetadata(input.planner_adapter);
  if (!plannerAdapter) return { ok: false, response: invalidQuery("planner_adapter", "Expected planner adapter metadata.").response };
  const planningSessionId = safeString(input.planning_session_id) ?? slugId("planning_session", masterGoal.title);
  const session: StoredPlanningSession = {
    planning_session_id: planningSessionId,
    master_goal_id: masterGoalId,
    project_id: projectId,
    planner_adapter: plannerAdapter,
    created_at: now,
    updated_at: now,
  };
  const rawProposals = Array.isArray(input.proposals) ? input.proposals : [];
  const proposals: StoredTaskProposal[] = [];
  for (const rawProposal of rawProposals.slice(0, 20)) {
    if (!rawProposal || typeof rawProposal !== "object" || Array.isArray(rawProposal)) continue;
    const parsed = parseTaskProposalInput(rawProposal as Record<string, unknown>, masterGoal, planningSessionId, plannerAdapter.provider);
    if (parsed) proposals.push(parsed);
  }
  return { ok: true, session, proposals };
}

function parseTaskProposalInput(
  input: Record<string, unknown>,
  masterGoal: StoredPlanningMasterGoal,
  planningSessionId: string,
  createdBy: string,
): StoredTaskProposal | undefined {
  const now = new Date().toISOString();
  const title = safeString(input.title);
  const dedupeKey = safeString(input.dedupe_key);
  const risk = safeString(input.risk) ?? "low";
  if (!title || !dedupeKey || !TASK_RISKS.includes(risk as TaskRisk)) return undefined;
  const status = safeString(input.status) ?? "proposed";
  if (!PROPOSAL_STATUSES.includes(status as PlanningProposalStatus)) return undefined;
  const dependencies = safeStringArray(input.dependencies) ?? safeStringArray(input.depends_on) ?? [];
  return {
    proposal_id: safeString(input.proposal_id) ?? slugId("proposal", title),
    master_goal_id: masterGoal.master_goal_id,
    planning_session_id: planningSessionId,
    project_id: masterGoal.project_id,
    title,
    body: safeLongString(input.body),
    prompt_summary: safeString(input.prompt_summary),
    dedupe_key: dedupeKey,
    expected_files: safePathArray(input.expected_files) ?? [],
      acceptance_criteria: safeStringArray(input.acceptance_criteria) ?? [],
      evidence_requirements: safeStringArray(input.evidence_requirements) ?? [],
      required_capabilities: safeStringArray(input.required_capabilities) ?? ["codex"],
      original_required_capabilities: safeStringArray(input.original_required_capabilities),
      normalized_required_capabilities: safeStringArray(input.normalized_required_capabilities),
      capability_normalization_reason: safeString(input.capability_normalization_reason),
      risk: risk as TaskRisk,
    task_type: safeString(input.task_type) ?? "docs",
    depends_on: safeStringArray(input.depends_on) ?? dependencies,
    dependencies,
    rationale: safeString(input.rationale) ?? "Rule-based planner proposal.",
    stop_condition: safeString(input.stop_condition),
    status: status as PlanningProposalStatus,
    policy_decision: safeString(input.policy_decision),
    review_status: safeString(input.review_status) ?? status,
    review_reason: safeLongString(input.review_reason),
    reviewed_by: safeString(input.reviewed_by),
    reviewed_at: safeString(input.reviewed_at),
    approved_by: safeString(input.approved_by),
    approved_at: safeString(input.approved_at),
    superseded_by: safeString(input.superseded_by),
    created_by: safeString(input.created_by) ?? createdBy,
    converted_task_id: safeString(input.converted_task_id),
    created_at: now,
    updated_at: now,
  };
}

function safePlannerAdapterAuditMetadata(input: unknown): PlannerAdapterAuditMetadata | undefined {
  if (!input || typeof input !== "object" || Array.isArray(input)) return undefined;
  const record = redactUnsafePayload(input) as Record<string, unknown>;
  const provider = safeString(record.provider);
  const plannerMode = safeString(record.planner_mode);
  if (!provider || !plannerMode) return undefined;
  return {
    provider,
    model: safeString(record.model),
    runtime_mode: safeString(record.runtime_mode),
    planner_mode: plannerMode,
    tool_execution_mode: safeString(record.tool_execution_mode),
    prompt_version: safeString(record.prompt_version) ?? "v1",
    input_state_hash: safeString(record.input_state_hash) ?? "unknown",
    session_id: safeString(record.session_id),
    raw_response_included: false,
    secrets_included: false,
  };
}

type DraftSubmitDraft = TaskDraft | CampaignDraft;

interface DraftSubmitContext {
  draft: DraftSubmitDraft;
  template: TaskTemplate;
  submittedBy: string;
  allowedPaths: string[];
  blockedPaths: string[];
  validation: string[];
  requiredCapabilities: string[];
}

type DraftSubmitPreviewBuild =
  | {
      ok: true;
      statusCode: 200;
      context: DraftSubmitContext;
      response: Record<string, unknown>;
    }
  | {
      ok: false;
      statusCode: number;
      context: DraftSubmitContext;
      response: Record<string, unknown>;
    };

function extractDraftSubmitDraft(input: unknown): DraftSubmitDraft | undefined {
  const record = safeRecord(input);
  if (!record) return undefined;
  const preview = safeRecord(record.preview);
  const candidate = safeRecord(record.draft) ?? safeRecord(preview?.draft) ?? record;
  if (!candidate) return undefined;
  if (candidate.draft_type === "task") {
    const parsed = TaskDraftSchema.safeParse(candidate);
    return parsed.success ? parsed.data : undefined;
  }
  if (candidate.draft_type === "campaign") {
    const parsed = CampaignDraftSchema.safeParse(candidate);
    return parsed.success ? parsed.data : undefined;
  }
  return undefined;
}

function emptyDraftSubmitContext(input: Record<string, unknown> | undefined): DraftSubmitContext {
  const draftType = safeString(input?.draft_type) === "campaign" ? "campaign" : "task";
  const fallbackDraft = {
    schema: draftType === "campaign" ? "skybridge.campaign_draft.v1" : "skybridge.task_draft.v1",
    draft_id: safeString(input?.draft_id) ?? "unknown_draft",
    draft_type: draftType,
    template_id: safeString(input?.template_id) ?? "unknown_template",
    project_id: safeString(input?.project_id) ?? "unknown_project",
    title: safeString(input?.title) ?? "Unknown draft",
    summary: safeString(input?.summary) ?? "Draft validation failed before safe mapping.",
    risk: safeString(input?.risk) ?? "blocked",
    required_capabilities: [],
    allowed_paths: [],
    blocked_paths: [".env", "secrets/**", "deploy/**", ".git/**"],
    validation: ["Fix draft validation errors before submit."],
    runner_id: safeString(input?.runner_id) ?? "not-selected",
    evidence_schema: [],
    planner_id: "unknown-planner",
    input_preview: "not_persisted",
    input_hash: "unknown_input_hash",
    inputs: {},
    raw_prompt_persisted: false,
    raw_response_persisted: false,
    task_created: false,
    campaign_created: false,
    claim_created: false,
    execution_started: false,
    codex_run_called: false,
    matlab_run_called: false,
    arbitrary_shell_enabled: false,
    token_printed: false,
  } as DraftSubmitDraft;
  const fallbackTemplate = {
    schema: "skybridge.task_template.v1",
    template_id: fallbackDraft.template_id,
    version: "unknown",
    title: "Unknown template",
    description: "Template validation failed.",
    category: "blocked",
    draft_type: draftType,
    risk_class: "high",
    required_capabilities: [],
    optional_capabilities: [],
    input_schema_summary: ["blocked"],
    allowed_paths: [],
    blocked_paths: fallbackDraft.blocked_paths,
    validation_rules: [],
    runner_id: fallbackDraft.runner_id,
    evidence_schema: [],
    output_paths: [],
    execution_supported: false,
    draft_only: true,
    task_creation_supported: false,
    campaign_creation_supported: false,
    claim_supported: false,
    codex_run_supported: false,
    matlab_run_supported: false,
    arbitrary_shell_enabled: false,
    token_printed: false,
  } as TaskTemplate;
  return {
    draft: fallbackDraft,
    template: fallbackTemplate,
    submittedBy: safeString(input?.submitted_by) ?? "local-operator",
    allowedPaths: [],
    blockedPaths: fallbackDraft.blocked_paths,
    validation: fallbackDraft.validation,
    requiredCapabilities: [],
  };
}

function draftSubmitEnvelope(
  schema: "skybridge.draft_review.v1" | "skybridge.draft_submit_preview.v1" | "skybridge.draft_submit_result.v1",
  context: DraftSubmitContext,
  overrides: Partial<{
    ok: boolean;
    review_status: "ready_for_submit_preview" | "ready_for_confirmation" | "submitted" | "blocked";
    review_reason: string;
    created_task_id: string;
    created_campaign_id: string;
    created_campaign_step_ids: string[];
    task_created: boolean;
    campaign_created: boolean;
    next_safe_action: string;
  }> = {},
): Record<string, unknown> {
  return {
    schema,
    ok: overrides.ok ?? true,
    draft_id: context.draft.draft_id,
    draft_type: context.draft.draft_type,
    template_id: context.draft.template_id,
    project_id: context.draft.project_id,
    title: context.draft.title,
    risk: context.template.risk_class,
    required_capabilities: context.requiredCapabilities,
    allowed_paths: context.allowedPaths,
    blocked_paths: context.blockedPaths,
    runner_id: context.template.runner_id,
    evidence_schema: context.template.evidence_schema,
    review_status: overrides.review_status ?? "ready_for_confirmation",
    review_reason: overrides.review_reason ?? "draft_validated_create_queued_records_only_no_execution",
    submitted_by: context.submittedBy,
    ...(overrides.created_task_id ? { created_task_id: overrides.created_task_id } : {}),
    ...(overrides.created_campaign_id ? { created_campaign_id: overrides.created_campaign_id } : {}),
    ...(overrides.created_campaign_step_ids ? { created_campaign_step_ids: overrides.created_campaign_step_ids } : {}),
    task_created: overrides.task_created ?? false,
    campaign_created: overrides.campaign_created ?? false,
    claim_created: false,
    execution_started: false,
    codex_run_called: false,
    matlab_run_called: false,
    worker_loop_started: false,
    arbitrary_shell_enabled: false,
    project_control_unpause: false,
    raw_prompt_persisted: false,
    raw_response_persisted: false,
    token_printed: false,
    next_safe_action: overrides.next_safe_action ?? "confirm_submit_or_hold_for_review",
  };
}

function sameStringSet(left: string[], right: string[]): boolean {
  const rightSet = new Set(right);
  return left.length === right.length && left.every((item) => rightSet.has(item));
}

function allInSet(values: string[], allowed: string[]): boolean {
  const allowedSet = new Set(allowed);
  return values.every((value) => allowedSet.has(value));
}

function validationSummaries(template: TaskTemplate): string[] {
  return template.validation_rules.map((rule) => rule.summary);
}

function draftHasReportRequested(draft: DraftSubmitDraft): boolean {
  const inputs = safeRecord(draft.inputs) ?? {};
  const outputs = safeStringArray(inputs.outputs) ?? [];
  return outputs.some((item) => /report|报告/i.test(item)) || /report|报告/i.test(draft.title) || /report|报告/i.test(draft.summary);
}

function buildDraftSubmitPreview(input: Record<string, unknown> | undefined, store: EventStore): DraftSubmitPreviewBuild {
  const record = safeRecord(input);
  const draft = extractDraftSubmitDraft(input);
  const context = draft
    ? {
        draft,
        template: (getTaskTemplate(draft.template_id) as TaskTemplate | undefined) ?? emptyDraftSubmitContext(draft as unknown as Record<string, unknown>).template,
        submittedBy: safeString(record?.submitted_by) ?? "local-operator",
        allowedPaths: draft.allowed_paths,
        blockedPaths: draft.blocked_paths,
        validation: draft.validation,
        requiredCapabilities: draft.required_capabilities,
      }
    : emptyDraftSubmitContext(record);
  const blockers: string[] = [];
  const unsafePayload = findUnsafeControlPlanePayload(input ?? {});
  blockers.push(...unsafePayload);
  if (!draft) blockers.push("invalid_or_missing_draft");
  if (draft?.draft_type !== "task" && draft?.draft_type !== "campaign") blockers.push("unsupported_draft_type");
  const template = draft ? getTaskTemplate(draft.template_id) : undefined;
  if (draft && !template) blockers.push("unknown_template_id");
  if (draft && ["blocked-request.v1", "needs-clarification.v1"].includes(draft.template_id)) blockers.push("draft_not_submittable");
  if (draft && !store.getProject(draft.project_id)) blockers.push("project_not_found");
  const previewBlockers = safeStringArray(record?.blockers) ?? [];
  if (previewBlockers.length > 0) blockers.push(...previewBlockers);
  if (record?.unsafe_request_detected === true) blockers.push("unsafe_request_detected");

  if (draft) {
    for (const [field, value] of Object.entries({
      raw_prompt_persisted: draft.raw_prompt_persisted,
      raw_response_persisted: draft.raw_response_persisted,
      task_created: draft.task_created,
      campaign_created: draft.campaign_created,
      claim_created: draft.claim_created,
      execution_started: draft.execution_started,
      codex_run_called: draft.codex_run_called,
      matlab_run_called: draft.matlab_run_called,
      arbitrary_shell_enabled: draft.arbitrary_shell_enabled,
      token_printed: draft.token_printed,
    })) {
      if (value !== false) blockers.push(`${field}_must_be_false`);
    }
  }

  if (draft && template) {
    context.template = template;
    context.allowedPaths = draft.allowed_paths.filter((path) => template.allowed_paths.includes(path));
    context.blockedPaths = [...new Set([...template.blocked_paths, ...draft.blocked_paths])];
    context.validation = validationSummaries(template);
    context.requiredCapabilities = [
      ...new Set(draft.required_capabilities.filter((capability) =>
        [...template.required_capabilities, ...template.optional_capabilities].includes(capability)
      )),
    ];
    if (template.draft_type !== draft.draft_type) blockers.push("template_draft_type_mismatch");
    if (draft.runner_id !== template.runner_id) blockers.push("runner_id_mismatch");
    if (!sameStringSet(draft.evidence_schema, template.evidence_schema)) blockers.push("evidence_schema_mismatch");
    if (!allInSet(template.required_capabilities, draft.required_capabilities)) blockers.push("missing_required_template_capability");
    if (!allInSet(draft.allowed_paths, template.allowed_paths)) blockers.push("allowed_paths_outside_template_policy");
    if (!allInSet(template.blocked_paths, draft.blocked_paths)) blockers.push("blocked_paths_missing_template_policy");
    if (template.execution_supported !== false || template.claim_supported !== false || template.codex_run_supported !== false || template.matlab_run_supported !== false || template.arbitrary_shell_enabled !== false) {
      blockers.push("template_forbidden_execution_flag_enabled");
    }
  }

  const uniqueBlockers = [...new Set(blockers)];
  if (uniqueBlockers.length > 0) {
    const response = {
      ...draftSubmitEnvelope("skybridge.draft_submit_preview.v1", context, {
        ok: false,
        review_status: "blocked",
        review_reason: uniqueBlockers.join(";"),
        next_safe_action: uniqueBlockers.includes("project_not_found")
          ? "create_or_select_existing_project_before_submit"
          : "fix_or_reject_draft_before_submit",
      }),
      blockers: uniqueBlockers,
    };
    return {
      ok: false,
      statusCode: uniqueBlockers.includes("project_not_found") ? 404 : uniqueBlockers.includes("unknown_template_id") ? 400 : 409,
      context,
      response,
    };
  }

  return {
    ok: true,
    statusCode: 200,
    context,
    response: draftSubmitEnvelope("skybridge.draft_submit_preview.v1", context),
  };
}

async function submitReviewedDraft(
  context: DraftSubmitContext,
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
): Promise<{ statusCode: number; response: Record<string, unknown> }> {
  if (context.draft.draft_type === "task") {
    return submitTaskDraft(context, store, addStoredEvent);
  }
  return submitCampaignDraft(context, store, addStoredEvent);
}

async function submitTaskDraft(
  context: DraftSubmitContext,
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
): Promise<{ statusCode: number; response: Record<string, unknown> }> {
  const draft = context.draft;
  const now = new Date().toISOString();
  const suffix = draft.input_hash.slice(0, 12);
  const taskId = `draft_task_${suffix}`;
  if (store.getTask(taskId)) {
    return {
      statusCode: 409,
      response: draftSubmitEnvelope("skybridge.draft_submit_result.v1", context, {
        ok: false,
        review_status: "blocked",
        review_reason: "draft_task_already_exists",
        next_safe_action: "review_existing_draft_task_or_change_draft_id",
      }),
    };
  }
  const task: StoredTask = {
    task_id: taskId,
    project_id: draft.project_id,
    title: draft.title,
    body: `Draft review submission for ${draft.template_id}. ${draft.summary}`,
    prompt_summary: draft.summary,
    status: "queued",
    risk: context.template.risk_class as TaskRisk,
    source: "manual",
    task_type: context.template.category,
    allowed_paths: context.allowedPaths,
    blocked_paths: context.blockedPaths,
    validation: context.validation,
    required_capabilities: context.requiredCapabilities,
    planner_metadata: {
      adapter: draft.planner_id,
      decision: "continue",
      reason: "draft_review_submit_queued_only_no_execution",
      task_type: context.template.category,
      template_id: context.template.template_id,
      runner_id: context.template.runner_id,
      evidence_schema: context.template.evidence_schema,
      allowed_paths: context.allowedPaths,
      blocked_paths: context.blockedPaths,
      validation: context.validation,
      expected_files: context.allowedPaths,
      expected_outputs: context.template.output_paths,
      stop_criteria_status: ["hold_for_mg329_worker_runner"],
      source_run_id: draft.draft_id,
      created_at: now,
      raw_response_included: false,
      secrets_included: false,
    },
    created_at: now,
    updated_at: now,
  };
  await store.upsertTask(task);
  await recordTaskEvent(task, "task.created", undefined, "Draft reviewed and submitted as queued task.", addStoredEvent, store, {
    source: "draft_review",
    template_id: context.template.template_id,
    runner_id: context.template.runner_id,
    evidence_schema: context.template.evidence_schema,
    raw_prompt_persisted: false,
    raw_response_persisted: false,
    claim_created: false,
    execution_started: false,
    token_printed: false,
  });
  await recordDraftSubmitAudit(context, "draft.submit.task", taskId, store);
  return {
    statusCode: 201,
    response: draftSubmitEnvelope("skybridge.draft_submit_result.v1", context, {
      review_status: "submitted",
      review_reason: "queued_task_created_no_execution",
      created_task_id: task.task_id,
      task_created: true,
      campaign_created: false,
      next_safe_action: "hold_for_mg329_worker_runner",
    }),
  };
}

function campaignStepDefinitionSlugs(draft: DraftSubmitDraft): string[] {
  const steps = [
    "prepare-parameter-grid",
    "run-matlab-sweep",
    "aggregate-results",
  ];
  if (draftHasReportRequested(draft) || draft.required_capabilities.includes("codex")) {
    steps.push("generate-analysis-report");
  }
  steps.push("hold-for-operator-review");
  return steps;
}

function titleFromSlug(slug: string): string {
  return slug
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

async function submitCampaignDraft(
  context: DraftSubmitContext,
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
): Promise<{ statusCode: number; response: Record<string, unknown> }> {
  const draft = context.draft;
  const now = new Date().toISOString();
  const suffix = draft.input_hash.slice(0, 12);
  const campaignId = `draft_campaign_${suffix}`;
  if (store.getCampaign(campaignId)) {
    return {
      statusCode: 409,
      response: draftSubmitEnvelope("skybridge.draft_submit_result.v1", context, {
        ok: false,
        review_status: "blocked",
        review_reason: "draft_campaign_already_exists",
        next_safe_action: "review_existing_draft_campaign_or_change_draft_id",
      }),
    };
  }
  const stepSlugs = campaignStepDefinitionSlugs(draft);
  const steps: StoredCampaignStep[] = stepSlugs.map((slug, index) => ({
    campaign_step_id: `${campaignId}:${slug}`,
    campaign_id: campaignId,
    project_id: draft.project_id,
    goal_id: slug,
    title: titleFromSlug(slug),
    order: index + 1,
    status: index === 0 ? "ready" : "pending",
    dependencies: index === 0 ? [] : [stepSlugs[index - 1]!],
    metadata: {
      source: "draft_review",
      draft_id: draft.draft_id,
      template_id: context.template.template_id,
      runner_id: context.template.runner_id,
      evidence_schema: context.template.evidence_schema,
      allowed_paths: context.allowedPaths,
      blocked_paths: context.blockedPaths,
      validation: context.validation,
      draft_submission_only: true,
      execution_started: false,
      codex_run_called: false,
      matlab_run_called: false,
      token_printed: false,
    },
    advance_gate: {
      requires_human_approval: true,
      requires_clean_worktree: true,
      requires_no_active_tasks: true,
      requires_no_stale_leases: true,
      allow_project_control_running: false,
    },
    evidence_summary: {
      summary: "Draft submission metadata only; worker runner deferred to MG329.",
      created_at: now,
    },
    linked_task_ids: [],
    linked_pr_urls: [],
    created_at: now,
    updated_at: now,
  }));
  const campaign: StoredCampaign = {
    campaign_id: campaignId,
    project_id: draft.project_id,
    title: draft.title,
    description: `Draft review submission for ${draft.template_id}. ${draft.summary}`,
    source: "draft_review",
    status: "draft",
    current_step_id: steps[0]?.campaign_step_id,
    created_at: now,
    updated_at: now,
    created_by: context.submittedBy,
    safety_policy: {
      queued_only: true,
      execution_started: false,
      claim_created: false,
      codex_run_called: false,
      matlab_run_called: false,
      worker_loop_started: false,
      project_control_unpause: false,
      token_printed: false,
    },
    metadata: {
      draft_id: draft.draft_id,
      template_id: context.template.template_id,
      runner_id: context.template.runner_id,
      evidence_schema: context.template.evidence_schema,
      allowed_paths: context.allowedPaths,
      blocked_paths: context.blockedPaths,
      validation: context.validation,
      raw_prompt_persisted: false,
      raw_response_persisted: false,
      token_printed: false,
    },
  };
  await store.upsertCampaign(campaign);
  for (const step of steps) await store.upsertCampaignStep(step);
  await recordCampaignEvent(campaign, "campaign.created", "Draft reviewed and submitted as draft campaign.", addStoredEvent, {
    source: "draft_review",
    template_id: context.template.template_id,
    runner_id: context.template.runner_id,
    step_count: steps.length,
    claim_created: false,
    execution_started: false,
    codex_run_called: false,
    matlab_run_called: false,
    token_printed: false,
  });
  await recordDraftSubmitAudit(context, "draft.submit.campaign", campaignId, store);
  return {
    statusCode: 201,
    response: draftSubmitEnvelope("skybridge.draft_submit_result.v1", context, {
      review_status: "submitted",
      review_reason: "draft_campaign_created_no_execution",
      created_campaign_id: campaign.campaign_id,
      created_campaign_step_ids: steps.map((step) => step.campaign_step_id),
      task_created: false,
      campaign_created: true,
      next_safe_action: "hold_for_mg329_worker_runner",
    }),
  };
}

async function recordDraftSubmitAudit(
  context: DraftSubmitContext,
  action: string,
  createdRecordId: string,
  store: EventStore,
): Promise<void> {
  await store.addAuditRecord({
    audit_id: `audit_${action.replace(/\./g, "_")}_${context.draft.input_hash.slice(0, 12)}`,
    time: new Date().toISOString(),
    action,
    actor: context.submittedBy,
    source_adapter: "skybridge/draft-submit-api",
    run_id: context.draft.draft_id,
    safety_decision: `created_${createdRecordId}_queued_only_no_execution`,
    immutable_event_id: context.draft.draft_id,
    redaction_policy_version: "packages/event-schema/src/redaction-rules.json",
    raw_payload_included: false,
  });
}

function parseCampaignImportInput(input: Record<string, unknown> | undefined, store: EventStore):
  | { ok: true; campaign: StoredCampaign; steps: StoredCampaignStep[] }
  | { ok: false; status?: number; response: QueryErrorResponse | { ok: false; error: string; reasons?: string[] } } {
  if (!input || typeof input !== "object") return { ok: false, response: invalidQuery("body", "Expected a campaign object.").response };
  const now = new Date().toISOString();
  const projectId = safeString(input.project_id) ?? "skybridge-agent-hub";
  if (!store.getProject(projectId)) return { ok: false, status: 404, response: { ok: false, error: "project_not_found" } };
  const title = safeString(input.title);
  const campaignId = safeString(input.campaign_id) ?? slugId("campaign", title ?? "campaign");
  if (!title) return { ok: false, response: invalidQuery("title", "Campaign title is required.").response };
  const rawGoals = Array.isArray(input.goals) ? input.goals : Array.isArray(input.steps) ? input.steps : [];
  if (rawGoals.length === 0) return { ok: false, response: { ok: false, error: "campaign_requires_steps" } };
  const errors: string[] = [];
  const seenGoalIds = new Set<string>();
  const seenOrders = new Set<number>();
  const steps: StoredCampaignStep[] = [];
  for (const rawGoal of rawGoals) {
    if (!rawGoal || typeof rawGoal !== "object") { errors.push("goal entry must be an object"); continue; }
    const goal = rawGoal as Record<string, unknown>;
    const goalId = safeString(goal.goal_id);
    const goalTitle = safeString(goal.title);
    const order = Number(goal.order);
    if (!goalId) errors.push("goal_id is required");
    if (!goalTitle) errors.push(`title is required for ${goalId ?? "unknown goal"}`);
    if (!Number.isInteger(order) || order < 1) errors.push(`order must be a positive integer for ${goalId ?? "unknown goal"}`);
    if (goalId && seenGoalIds.has(goalId)) errors.push(`duplicate goal_id: ${goalId}`);
    if (Number.isInteger(order) && seenOrders.has(order)) errors.push(`duplicate order: ${order}`);
    if (goalId) seenGoalIds.add(goalId);
    if (Number.isInteger(order)) seenOrders.add(order);
    const dependencies = safeStringArray(goal.dependencies) ?? safeStringArray(goal.requires) ?? [];
    const markdownPath = safeString(goal.markdown_path);
    const markdownBody = safeLongString(goal.markdown_body);
    const metadata = safeRecord(goal.metadata) ?? {};
    const stepId = safeString(goal.campaign_step_id) ?? `${campaignId}:${goalId ?? slugId("goal", goalTitle ?? "step")}`;
    steps.push({
      campaign_step_id: stepId,
      campaign_id: campaignId,
      project_id: projectId,
      goal_id: goalId ?? stepId,
      title: goalTitle ?? stepId,
      order: Number.isInteger(order) ? order : 9999,
      status: "pending",
      dependencies,
      markdown_path: markdownPath,
      markdown_hash: safeString(goal.markdown_hash) ?? (markdownBody ? createHash("sha256").update(markdownBody).digest("hex") : undefined),
      metadata,
      advance_gate: safeRecord(goal.advance_gate),
      linked_task_ids: safeStringArray(goal.linked_task_ids) ?? [],
      linked_pr_urls: safeStringArray(goal.linked_pr_urls) ?? [],
      created_at: now,
      updated_at: now,
    });
  }
  const goalIds = new Set(steps.map((step) => step.goal_id));
  for (const step of steps) {
    for (const dependency of step.dependencies) {
      if (!goalIds.has(dependency)) errors.push(`dependency ${dependency} for ${step.goal_id} does not refer to a campaign goal`);
    }
  }
  if (errors.length > 0) return { ok: false, response: { ok: false, error: "invalid_campaign_goal_pack", reasons: errors } };
  const sortedSteps = steps.sort((a, b) => a.order - b.order);
  const firstStep = sortedSteps[0];
  if (firstStep) firstStep.status = "ready";
  const status = safeString(input.status) ?? "draft";
  if (!CAMPAIGN_STATUSES.includes(status as CampaignStatus)) return { ok: false, response: { ok: false, error: "invalid_campaign_status" } };
  const campaign: StoredCampaign = {
    campaign_id: campaignId,
    project_id: projectId,
    title,
    description: safeLongString(input.description),
    source: safeString(input.source) ?? "goal-pack",
    status: status as CampaignStatus,
    current_step_id: firstStep?.campaign_step_id,
    created_at: now,
    updated_at: now,
    created_by: safeString(input.created_by) ?? "operator",
    imported_from: safeString(input.imported_from),
    goal_pack_hash: safeString(input.goal_pack_hash),
    safety_policy: safeRecord(input.safety_policy),
    metadata: safeRecord(input.metadata),
  };
  return { ok: true, campaign, steps: sortedSteps };
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

async function recordCampaignEvent(
  campaign: StoredCampaign,
  type: Extract<SkyBridgeEventType, `campaign.${string}`>,
  message: string,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
  payload: Record<string, unknown> = {},
): Promise<void> {
  await addStoredEvent(coreEvent(type, {
    campaign_id: campaign.campaign_id,
    project_id: campaign.project_id,
    status: campaign.status,
    message,
    ...payload,
  }));
}

function campaignStepDone(status: CampaignStepStatus): boolean {
  return ["completed", "recovered", "skipped"].includes(status);
}

function campaignActiveTaskCount(projectId: string, store: EventStore): number {
  return store
    .listTasks({ projectId })
    .filter((task) => ["queued", "claimed", "running"].includes(task.status))
    .length;
}

function campaignStaleLeaseCount(projectId: string, store: EventStore, now = new Date()): number {
  return store
    .listTasks({ projectId })
    .filter((task) => task.lease?.lease_status === "active" && isExpiredLease(task.lease, now))
    .length;
}

function chooseCampaignCandidateStep(campaign: StoredCampaign, steps: StoredCampaignStep[]): StoredCampaignStep | undefined {
  const current = campaign.current_step_id ? steps.find((step) => step.campaign_step_id === campaign.current_step_id) : undefined;
  if (current && !campaignStepDone(current.status)) return current;
  return steps
    .filter((step) => !campaignStepDone(step.status) && !["failed", "held"].includes(step.status))
    .sort((a, b) => a.order - b.order)
    .at(0);
}

function evaluateCampaignAdvanceGate(campaign: StoredCampaign, store: EventStore, input: Record<string, unknown> | undefined = {}) {
  const now = new Date();
  const project = store.getProject(campaign.project_id);
  const control = project ? controlStateForProject(project) : undefined;
  const steps = store.listCampaignSteps({ campaignId: campaign.campaign_id }).sort((a, b) => a.order - b.order);
  const candidate = chooseCampaignCandidateStep(campaign, steps);
  const blockers: string[] = [];
  const warnings: string[] = [];
  const activeTasks = campaignActiveTaskCount(campaign.project_id, store);
  const staleLeases = campaignStaleLeaseCount(campaign.project_id, store, now);
  const failedUnrecovered = store.listTasks({ projectId: campaign.project_id }).filter((task) =>
    task.status === "failed" &&
    task.result?.evidence_summary?.recovered !== true &&
    task.result?.evidence_summary?.recovery_status !== "recovered"
  ).length;

  if (!candidate) {
    const incomplete = steps.some((step) => !campaignStepDone(step.status));
    return {
      decision: incomplete ? "hold" : "advance",
      reason: incomplete ? "No advanceable campaign step found." : "Campaign has no remaining incomplete steps.",
      current_step_id: campaign.current_step_id,
      next_step_id: undefined,
      blockers: incomplete ? ["no_advanceable_step"] : [],
      warnings,
      hygiene: { active_tasks: activeTasks, stale_leases: staleLeases, failed_unrecovered: failedUnrecovered },
      hermes_gate_enabled: false,
      hermes_gate_advisory: null,
    };
  }

  const gate = { ...(candidate.advance_gate ?? {}), ...(safeRecord(input) ?? {}) };
  const dependencies = candidate.dependencies ?? [];
  for (const dependencyId of dependencies) {
    const dependency = steps.find((step) => step.goal_id === dependencyId || step.campaign_step_id === dependencyId);
    if (!dependency || !campaignStepDone(dependency.status)) blockers.push(`dependency_not_complete:${dependencyId}`);
  }

  if ((gate.requires_no_active_tasks ?? true) && activeTasks > 0) blockers.push("active_tasks_present");
  if ((gate.requires_no_stale_leases ?? true) && staleLeases > 0) blockers.push("stale_leases_present");
  if (!(gate.allow_project_control_running === true) && control?.state === "running") blockers.push("project_control_running");
  if (candidate.status === "failed") blockers.push("current_step_failed");
  if (input?.worktree_dirty === true || input?.repo_dirty === true) blockers.push("worktree_dirty");
  if (gate.requires_parent_pr_merged === true && input?.parent_pr_merged !== true) blockers.push("parent_pr_not_merged");
  if (campaign.status === "failed" || campaign.status === "aborted") blockers.push(`campaign_${campaign.status}`);

  if (failedUnrecovered > 0) warnings.push("failed_unrecovered_tasks_present");
  if (store.listTasks({ projectId: campaign.project_id }).some((task) => task.status === "blocked")) warnings.push("blocked_tasks_present");
  if (store.listTaskProposals({ projectId: campaign.project_id }).some((proposal) => proposal.status === "approved")) warnings.push("approved_unconverted_proposals_present");
  if (!store.listWorkers().some((worker) => presentWorker(worker, store).status === "online")) warnings.push("worker_offline");

  const needsHuman = gate.requires_human_approval === true && gate.human_approved !== true;
  return {
    decision: blockers.length > 0 ? "hold" : needsHuman ? "ask_human" : "advance",
    reason: blockers.length > 0
      ? "Campaign advance is blocked by deterministic policy."
      : needsHuman
        ? "Campaign step requires human approval before advance."
        : "Campaign advance gates passed.",
    current_step_id: campaign.current_step_id,
    next_step_id: candidate.campaign_step_id,
    next_goal_id: candidate.goal_id,
    blockers,
    warnings,
    hygiene: { active_tasks: activeTasks, stale_leases: staleLeases, failed_unrecovered: failedUnrecovered },
    dependencies,
    hermes_gate_enabled: false,
    hermes_gate_advisory: null,
  };
}

async function updateCampaignState(
  campaignIdParam: string,
  status: CampaignStatus,
  body: Record<string, unknown>,
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
  reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
) {
  const campaign = store.getCampaign(decodeURIComponent(campaignIdParam));
  if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
  const now = new Date().toISOString();
  const updated: StoredCampaign = {
    ...campaign,
    status,
    updated_at: now,
    metadata: {
      ...(campaign.metadata ?? {}),
      last_reason: safeString(body.reason),
    },
  };
  await store.upsertCampaign(updated);
  const eventType = status === "running"
    ? "campaign.started"
    : status === "paused"
      ? "campaign.paused"
      : status === "held"
        ? "campaign.held"
        : status === "completed"
          ? "campaign.completed"
          : status === "failed"
            ? "campaign.failed"
            : "campaign.paused";
  await recordCampaignEvent(updated, eventType, `Campaign ${status}.`, addStoredEvent, { reason: safeString(body.reason) });
  return { ok: true, campaign: updated, steps: store.listCampaignSteps({ campaignId: updated.campaign_id }) };
}

async function finishCampaignStep(
  campaignIdParam: string,
  stepIdParam: string,
  status: Extract<CampaignStepStatus, "completed" | "failed">,
  body: Record<string, unknown>,
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
  reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
) {
  const campaignId = decodeURIComponent(campaignIdParam);
  const campaign = store.getCampaign(campaignId);
  if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
  const step = store.getCampaignStep(decodeURIComponent(stepIdParam));
  if (!step || step.campaign_id !== campaignId) return reply.code(404).send({ ok: false, error: "campaign_step_not_found" });
  const evidenceSummary = safeRecord(body.evidence_summary);
  const linkedTaskIds = safeStringArray(body.linked_task_ids) ?? step.linked_task_ids ?? [];
  const linkedPrUrls = safeStringArray(body.linked_pr_urls) ?? step.linked_pr_urls ?? [];
  const reason = safeString(body.reason);
  if (status === "completed" && !evidenceSummary && linkedTaskIds.length === 0 && linkedPrUrls.length === 0)
    return reply.code(400).send({ ok: false, error: "campaign_step_completion_requires_evidence" });
  if (status === "failed" && !reason) return reply.code(400).send({ ok: false, error: "campaign_step_failure_requires_reason" });
  const now = new Date().toISOString();
  const updatedStep: StoredCampaignStep = {
    ...step,
    status,
    evidence_summary: evidenceSummary ?? step.evidence_summary,
    linked_task_ids: linkedTaskIds,
    linked_pr_urls: linkedPrUrls,
    decision_summary: reason ?? safeString(body.decision_summary) ?? step.decision_summary,
    completed_at: now,
    updated_at: now,
  };
  const updatedCampaign: StoredCampaign = {
    ...campaign,
    status: status === "failed" ? "held" : campaign.status,
    updated_at: now,
  };
  await store.upsertCampaignStep(updatedStep);
  await store.upsertCampaign(updatedCampaign);
  await recordCampaignEvent(
    updatedCampaign,
    status === "failed" ? "campaign.step.failed" : "campaign.step.completed",
    `Campaign step ${status}.`,
    addStoredEvent,
    {
      campaign_step_id: updatedStep.campaign_step_id,
      goal_id: updatedStep.goal_id,
      reason,
      linked_task_ids: linkedTaskIds,
      linked_pr_urls: linkedPrUrls,
    },
  );
  if (status === "failed") {
    await recordCampaignEvent(updatedCampaign, "campaign.held", "Campaign held after failed step.", addStoredEvent, { campaign_step_id: updatedStep.campaign_step_id });
  }
  return { ok: true, campaign: updatedCampaign, step: updatedStep };
}

async function attachCampaignEvidence(
  campaignIdParam: string,
  stepIdParam: string,
  body: Record<string, unknown>,
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
  reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
) {
  const campaignId = decodeURIComponent(campaignIdParam);
  const campaign = store.getCampaign(campaignId);
  if (!campaign) return reply.code(404).send({ ok: false, error: "campaign_not_found" });
  const step = store.getCampaignStep(decodeURIComponent(stepIdParam));
  if (!step || step.campaign_id !== campaignId) return reply.code(404).send({ ok: false, error: "campaign_step_not_found" });
  const evidenceSummary = safeRecord(body.evidence_summary);
  const linkedTaskIds = safeStringArray(body.linked_task_ids) ?? step.linked_task_ids ?? [];
  const linkedPrUrls = safeStringArray(body.linked_pr_urls) ?? step.linked_pr_urls ?? [];
  if (!evidenceSummary && linkedTaskIds.length === 0 && linkedPrUrls.length === 0)
    return reply.code(400).send({ ok: false, error: "campaign_step_evidence_required" });
  const now = new Date().toISOString();
  const updatedStep: StoredCampaignStep = {
    ...step,
    evidence_summary: evidenceSummary ?? step.evidence_summary,
    linked_task_ids: linkedTaskIds,
    linked_pr_urls: linkedPrUrls,
    updated_at: now,
  };
  await store.upsertCampaignStep(updatedStep);
  await recordCampaignEvent(campaign, "campaign.step.evidence_attached", "Campaign step evidence attached.", addStoredEvent, {
    campaign_step_id: updatedStep.campaign_step_id,
    goal_id: updatedStep.goal_id,
    linked_task_ids: linkedTaskIds,
    linked_pr_urls: linkedPrUrls,
  });
  return { ok: true, campaign, step: updatedStep };
}

function safeCampaignExecutionFiles(input: Record<string, unknown>, step: StoredCampaignStep): string[] {
  const explicit = safePathArray(input.expected_files);
  if (explicit && explicit.length > 0) return explicit;
  const goalId = step.goal_id.toLowerCase();
  if (goalId === "super-187-bootstrap-campaign-mvp-hardening") {
    return [
      "docs/dev/CAMPAIGN_STEP_EXECUTOR_PILOT.md",
      "docs/dev/BOOTSTRAP_CAMPAIGN_MVP.md",
      "docs/dev/PROGRESS.md",
      "docs/orchestrator/SELF_BOOTSTRAP_SUPERVISOR.md",
      "docs/orchestrator/WORKER_PROFILE_RUNBOOK.md",
    ];
  }
  return [`docs/dev/${goalId}.md`];
}

function validateCampaignExecutionPaths(taskType: string, files: string[]): string | undefined {
  if (files.length === 0) return "expected_files_required";
  for (const file of files) {
    if (/(^|\/)(\.env|id_rsa|secrets?|tokens?|private-key)/i.test(file) || /^(deploy\/|\.github\/settings|server-root|\/opt\/|[A-Z]:\/Users\/.*\/\.skybridge)/i.test(file))
      return `unsafe_expected_file:${file}`;
    if (taskType === "docs" && !file.startsWith("docs/")) return `docs_task_file_outside_docs:${file}`;
    if (taskType === "local-smoke" && !/^scripts\/powershell\/smoke-[^/]+\.ps1$/i.test(file)) return `local_smoke_file_not_safe:${file}`;
    if (taskType === "refactor" && !file.startsWith("docs/") && !file.startsWith("scripts/powershell/") && !file.startsWith("apps/server/src/") && !file.startsWith("packages/event-schema/src/"))
      return `refactor_file_outside_allowed_paths:${file}`;
  }
  return undefined;
}

function buildCampaignExecutionPreview(campaignIdParam: string, stepIdParam: string, body: Record<string, unknown>, store: EventStore) {
  const campaignId = decodeURIComponent(campaignIdParam);
  const stepId = decodeURIComponent(stepIdParam);
  const campaign = store.getCampaign(campaignId);
  if (!campaign) return { status: 404, payload: { ok: false, error: "campaign_not_found" } };
  const step = store.getCampaignStep(stepId);
  if (!step || step.campaign_id !== campaignId) return { status: 404, payload: { ok: false, error: "campaign_step_not_found" } };
  const steps = store.listCampaignSteps({ campaignId }).sort((a, b) => a.order - b.order);
  const project = store.getProject(campaign.project_id);
  const control = project ? controlStateForProject(project) : undefined;
  const blockers: string[] = [];
  const retry = body.retry_attempt === true;
  const taskType = (safeString(body.task_type) ?? "docs").toLowerCase();
  const files = safeCampaignExecutionFiles(body, step);
  const pathError = validateCampaignExecutionPaths(taskType, files);
  const activeTasks = campaignActiveTaskCount(campaign.project_id, store);
  const staleLeases = campaignStaleLeaseCount(campaign.project_id, store);
  if (campaign.current_step_id && campaign.current_step_id !== step.campaign_step_id) blockers.push("step_not_current");
  if (["running", "failed", "aborted"].includes(campaign.status)) blockers.push(`campaign_status_${campaign.status}`);
  if (!["ready", "running", "needs_human"].includes(step.status)) blockers.push(`step_not_ready:${step.status}`);
  if (campaignStepDone(step.status) && !retry) blockers.push("step_already_done");
  for (const dependencyId of step.dependencies ?? []) {
    const dependency = steps.find((candidate) => candidate.goal_id === dependencyId || candidate.campaign_step_id === dependencyId);
    if (!dependency || !campaignStepDone(dependency.status)) blockers.push(`dependency_not_complete:${dependencyId}`);
  }
  if (activeTasks > 0) blockers.push("active_tasks_present");
  if (staleLeases > 0) blockers.push("stale_leases_present");
  if (control?.state === "running") blockers.push("project_control_running");
  if (body.repo_dirty === true || body.worktree_dirty === true) blockers.push("worktree_dirty");
  if (safeString(body.markdown_hash) && step.markdown_hash && safeString(body.markdown_hash) !== step.markdown_hash && body.acknowledge_markdown_hash_mismatch !== true) blockers.push("markdown_hash_mismatch");
  if (pathError) blockers.push(pathError);
  const linkedTaskIds = step.linked_task_ids ?? [];
  if (linkedTaskIds.length > 0 && !retry) blockers.push("duplicate_linked_task");
  for (const linkedTaskId of linkedTaskIds) {
    const linkedTask = store.getTask(linkedTaskId);
    if (linkedTask && ["queued", "claimed", "running"].includes(linkedTask.status)) blockers.push(`linked_active_task:${linkedTaskId}`);
    if (linkedTask?.result?.pr_url && ["queued", "claimed", "running", "failed"].includes(linkedTask.status)) blockers.push(`linked_open_or_unresolved_pr:${linkedTaskId}`);
  }
  const allowedTypes = safeStringArray(step.metadata?.allowed_task_types) ?? [];
  const blockedTypes = safeStringArray(step.metadata?.blocked_task_types) ?? [];
  if (allowedTypes.length > 0 && !allowedTypes.map((item) => item.toLowerCase()).includes(taskType)) blockers.push(`task_type_not_allowed:${taskType}`);
  if (blockedTypes.map((item) => item.toLowerCase()).includes(taskType)) blockers.push(`blocked_task_type:${taskType}`);
  const requiredCapabilities = taskType === "local-smoke" ? ["codex", "powershell", "windows"] : ["codex", "git", "gh"];
  const markdownBody = safeLongString(body.markdown_body) ?? safeLongString(body.body) ?? `Campaign step markdown unavailable in server preview. Use local CLI to include the full markdown body for ${step.goal_id}.`;
  const markdownPath = safeString(body.markdown_path) ?? step.markdown_path;
  const markdownHash = safeString(body.markdown_hash) ?? step.markdown_hash;
  const taskId = safeString(body.task_id) ?? `campaign-step-${step.goal_id.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 14)}`;
  const task = {
    task_id: taskId,
    project_id: campaign.project_id,
    title: `Campaign step execution: ${step.title}`,
    body: `This task is executing a campaign step. Do not advance the campaign yourself unless explicitly instructed by SkyBridge gate.\n\nCampaign: ${campaign.campaign_id}\nStep: ${step.campaign_step_id}\nGoal: ${step.goal_id}\nSource markdown: ${markdownPath ?? "-"}\nMarkdown hash: ${markdownHash ?? "-"}\n\nSafety boundaries:\n- Do not change production deployment, server root config, secrets, GitHub settings, or branch protection.\n- Do not execute Super 184B.\n- Keep work bounded to the expected files.\n\nExpected files:\n${files.map((file) => `- ${file}`).join("\n")}\n\nFull Super Goal markdown:\n\n${markdownBody}`,
    prompt_summary: `Execute campaign step ${step.goal_id} from ${campaign.campaign_id}; do not advance campaign metadata.`,
    risk: "low",
    source: "custom",
    task_type: taskType,
    allowed_paths: files,
    blocked_paths: ["deploy/**", ".env", "**/.env", "**/*token*", "**/*secret*", ".github/settings/**"],
    validation: ["pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/validate-powershell.ps1", "just check"],
    required_capabilities: requiredCapabilities,
    planner_metadata: {
      adapter: "campaign-step-executor",
      decision: "continue",
      reason: "Campaign step execution task generated from imported Super Goal markdown.",
      task_type: taskType,
      allowed_paths: files,
      expected_files: files,
      blocked_paths: ["deploy/**", ".env", "**/.env", "**/*token*", "**/*secret*", ".github/settings/**"],
      validation: ["validate-powershell.ps1", "just check"],
      stop_criteria_status: ["completed", "recovered", "blocked", "failed"],
      source_run_id: `${campaign.campaign_id}:${step.campaign_step_id}`,
      source_campaign_id: campaign.campaign_id,
      source_campaign_step_id: step.campaign_step_id,
      source_goal_id: step.goal_id,
      markdown_path: markdownPath,
      markdown_hash: markdownHash,
      expected_outputs: safeStringArray(step.metadata?.expected_outputs) ?? [],
      created_at: new Date().toISOString(),
      raw_response_included: false,
      secrets_included: false,
    },
  };
  return {
    status: 200,
    payload: {
      ok: blockers.length === 0,
      campaign_id: campaign.campaign_id,
      step_id: step.campaign_step_id,
      goal_id: step.goal_id,
      markdown_path: markdownPath,
      markdown_hash: markdownHash,
      blockers: [...new Set(blockers)],
      expected_files: files,
      task,
      would_create_task: blockers.length === 0,
    },
  };
}

async function previewCampaignStepExecution(
  campaignIdParam: string,
  stepIdParam: string,
  body: Record<string, unknown>,
  store: EventStore,
  reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
) {
  const preview = buildCampaignExecutionPreview(campaignIdParam, stepIdParam, body, store);
  return reply.code(preview.status).send(preview.payload);
}

async function executeCampaignStep(
  campaignIdParam: string,
  stepIdParam: string,
  body: Record<string, unknown>,
  store: EventStore,
  addStoredEvent: (event: StoredEvent) => Promise<void>,
  reply: { code: (statusCode: number) => { send: (payload: unknown) => unknown } },
) {
  if (body.apply !== true && body.confirm_execute !== true) return reply.code(400).send({ ok: false, error: "missing_confirm_execute" });
  const preview = buildCampaignExecutionPreview(campaignIdParam, stepIdParam, body, store);
  if (preview.status !== 200) return reply.code(preview.status).send(preview.payload);
  const payload = preview.payload as { ok: boolean; blockers: string[]; task: Record<string, unknown>; campaign_id: string; step_id: string };
  if (!payload.ok) return reply.code(409).send({ ok: false, error: "campaign_step_execute_blocked", preview: payload });
  const parsed = parseTaskInput(payload.task, store);
  if (!parsed.ok) return reply.code(parsed.status ?? 400).send(parsed.response);
  await store.upsertTask(parsed.task);
  await recordTaskEvent(parsed.task, "task.created", undefined, "Campaign step execution task created.", addStoredEvent, store);
  const attachResult = await attachCampaignEvidence(payload.campaign_id, payload.step_id, {
    linked_task_ids: [parsed.task.task_id],
    evidence_summary: {
      summary: `Campaign step execution task created: ${parsed.task.task_id}. Worker execution has not been started by this endpoint.`,
      created_at: new Date().toISOString(),
      task_id: parsed.task.task_id,
    },
  }, store, addStoredEvent, reply);
  return { ok: true, task: withTaskEvents(parsed.task, store), link: attachResult, preview: payload };
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
  const now = new Date();
  if (status === "running" && isActiveLease(task.lease)) {
    if (isExpiredLease(task.lease, now)) {
      const expiredLease = markExpiredLease(task, now);
      const updatedTask: StoredTask = { ...task, lease: expiredLease, updated_at: now.toISOString() };
      await store.upsertTask(updatedTask);
      await recordTaskEvent(updatedTask, "task.updated", workerId, "Task start blocked by expired lease.", addStoredEvent, store, {
        lease_id: expiredLease?.lease_id,
        stale_reason: expiredLease?.stale_reason,
      });
      return reply.code(409).send({ ok: false, error: "task_stale_lease", lease: expiredLease });
    }
    if (workerId && task.lease.worker_id !== workerId) {
      return reply.code(409).send({ ok: false, error: "task_lease_worker_mismatch", lease: task.lease });
    }
  }
  const updated: StoredTask = {
    ...task,
    status,
    assigned_worker_id: workerId,
    lease: status === "running" ? refreshTaskLease(task, workerId, now) : task.lease,
    updated_at: now.toISOString(),
  };
  await store.upsertTask(updated);
  await recordTaskEvent(updated, eventType, workerId, `Task ${status}.`, addStoredEvent, store, updated.lease ? {
    lease_id: updated.lease.lease_id,
    lease_status: updated.lease.lease_status,
    lease_expires_at: updated.lease.lease_expires_at,
  } : {});
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
  const now = new Date();
  const updated: StoredTask = {
    ...task,
    status,
    assigned_worker_id: workerId,
    lease: releaseTaskLease(task, workerId, now),
    result: {
      summary: safeString(body.summary),
      result_url: safeString(body.result_url),
      pr_url: safeString(body.pr_url),
      error_summary: safeString(body.error_summary),
      evidence_summary: safeEvidenceSummary(body.evidence_summary),
    },
    updated_at: now.toISOString(),
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
    {
      ...(updated.result ? { ...updated.result } : {}),
      ...(updated.lease ? {
        lease_id: updated.lease.lease_id,
        lease_status: updated.lease.lease_status,
        released_at: updated.lease.released_at,
      } : {}),
    },
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
    .filter((value) => !/[<>:"|?]/.test(value))
    .map((value) => value.replace(/\\/g, "/"))
    .slice(0, 50);
}

function safeEvidencePathArray(input: unknown): string[] | undefined {
  if (!Array.isArray(input) || !input.every((item) => typeof item === "string" && item.length <= 240)) {
    return undefined;
  }
  return input
    .filter((value) => !/[<>:"|?]/.test(value))
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
    template_id: safeString(record.template_id),
    runner_id: safeString(record.runner_id),
    evidence_schema: safeStringArray(record.evidence_schema) ?? [],
    allowed_paths: safePathArray(record.allowed_paths) ?? [],
    blocked_paths: safePathArray(record.blocked_paths) ?? [],
    validation: safeStringArray(record.validation) ?? [],
    expected_files: safePathArray(record.expected_files) ?? [],
    stop_criteria_status: safeStringArray(record.stop_criteria_status) ?? [],
    source_run_id: safeString(record.source_run_id),
    source_campaign_id: safeString(record.source_campaign_id),
    source_campaign_step_id: safeString(record.source_campaign_step_id),
    source_goal_id: safeString(record.source_goal_id),
    created_at: safeIsoString(record.created_at) ?? new Date().toISOString(),
    markdown_path: safeString(record.markdown_path),
    markdown_hash: safeString(record.markdown_hash),
    expected_outputs: safeStringArray(record.expected_outputs) ?? [],
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
  const source = input as Record<string, unknown>;
  const record = redactUnsafePayload(input) as Record<string, unknown>;
  const summary = safeString(record.summary);
  if (!summary) return fallback;
  return {
    schema: safeString(record.schema),
    task_id: safeString(record.task_id),
    goal_id: safeString(record.goal_id),
    worker_id: safeString(record.worker_id),
    template_id: safeString(record.template_id),
    runner_id: safeString(record.runner_id),
    pr_url: safeString(record.pr_url),
    commit_sha: safeString(record.commit_sha),
    changed_files: safeEvidencePathArray(record.changed_files) ?? [],
    existing_outputs: safeEvidencePathArray(source.existing_outputs) ?? [],
    expected_outputs_missing: safeEvidencePathArray(source.expected_outputs_missing) ?? [],
    report_validation_errors: safeStringArray(record.report_validation_errors) ?? [],
    validation_status: safeString(record.validation_status),
    ci_status: safeString(record.ci_status),
    risk_status: safeString(record.risk_status),
    recovered: record.recovered === true,
    recovery_status: safeString(record.recovery_status),
    input_manifest_path: safeString(record.input_manifest_path),
    input_summary_path: safeString(record.input_summary_path),
    input_metrics_path: safeString(record.input_metrics_path),
    input_manifest_exists: safeOptionalBoolean(record.input_manifest_exists),
    input_summary_exists: safeOptionalBoolean(record.input_summary_exists),
    input_metrics_exists: safeOptionalBoolean(record.input_metrics_exists),
    output_report_path: safeString(source.output_report_path),
    report_exists: safeOptionalBoolean(record.report_exists),
    report_size_bytes: safeOptionalInteger(record.report_size_bytes, 0, 1_000_000_000),
    fallback_report_used: safeOptionalBoolean(record.fallback_report_used),
    codex_invoked: safeOptionalBoolean(record.codex_invoked),
    codex_exit_code: safeOptionalInteger(record.codex_exit_code, -1, 100_000),
    codex_failure_category: safeString(record.codex_failure_category),
    raw_codex_log_included: safeFalseOnlyBoolean(source.raw_codex_log_included),
    raw_prompt_included: safeFalseOnlyBoolean(source.raw_prompt_included),
    raw_stdout_included: safeFalseOnlyBoolean(source.raw_stdout_included),
    raw_stderr_included: safeFalseOnlyBoolean(source.raw_stderr_included),
    matlab_run_called: safeOptionalBoolean(record.matlab_run_called),
    arbitrary_shell_enabled: safeOptionalBoolean(record.arbitrary_shell_enabled),
    worker_loop_started: safeOptionalBoolean(record.worker_loop_started),
    project_control_unpaused: safeOptionalBoolean(record.project_control_unpaused),
    pr_created: safeOptionalBoolean(record.pr_created),
    token_printed: safeFalseOnlyBoolean(source.token_printed),
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
