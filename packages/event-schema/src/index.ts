import { z } from "zod";
import redactionRules from "./redaction-rules.json" with { type: "json" };

export const SKYBRIDGE_EVENT_SCHEMA_VERSION =
  "skybridge.agent_event.v1" as const;

export const SkyBridgeEventTypeSchema = z.enum([
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
  "worker.registered",
  "worker.heartbeat",
  "worker.offline",
  "project.created",
  "project.control_updated",
  "goal.created",
  "task.created",
  "task.claimed",
  "task.started",
  "task.completed",
  "task.failed",
  "task.blocked",
  "task.requeued",
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
]);

export const SkyBridgeSeveritySchema = z.enum([
  "debug",
  "info",
  "warning",
  "error",
  "critical",
]);
export const SkyBridgeSourcePlatformSchema = z.enum([
  "codex",
  "opencode",
  "hermes",
  "skybridge",
  "custom",
]);

export const SkyBridgeSourceSchema = z.object({
  platform: SkyBridgeSourcePlatformSchema,
  adapter: z.string().min(1),
  node_id: z.string().optional(),
  agent_id: z.string().optional(),
  cwd: z.string().optional(),
});

export const SkyBridgeCorrelationSchema = z.object({
  session_id: z.string().optional(),
  run_id: z.string().optional(),
  turn_id: z.string().optional(),
  step_id: z.string().optional(),
  tool_call_id: z.string().optional(),
});

export const SkyBridgeEventSchema = z.object({
  schema: z
    .literal(SKYBRIDGE_EVENT_SCHEMA_VERSION)
    .default(SKYBRIDGE_EVENT_SCHEMA_VERSION),
  event_id: z.string().optional(),
  time: z.string().datetime(),
  type: SkyBridgeEventTypeSchema,
  severity: SkyBridgeSeveritySchema.default("info"),
  source: SkyBridgeSourceSchema,
  correlation: SkyBridgeCorrelationSchema.optional(),
  payload: z.record(z.unknown()).default({}),
});

export type SkyBridgeEventType = z.infer<typeof SkyBridgeEventTypeSchema>;
export type SkyBridgeSeverity = z.infer<typeof SkyBridgeSeveritySchema>;
export type SkyBridgeSourcePlatform = z.infer<
  typeof SkyBridgeSourcePlatformSchema
>;
export type SkyBridgeSource = z.infer<typeof SkyBridgeSourceSchema>;
export type SkyBridgeCorrelation = z.infer<typeof SkyBridgeCorrelationSchema>;
export type SkyBridgeEvent = z.infer<typeof SkyBridgeEventSchema>;
export type SkyBridgeEventInput = {
  event_id?: string;
  time?: string;
  type: SkyBridgeEventType;
  severity?: SkyBridgeSeverity;
  source: SkyBridgeSource;
  correlation?: SkyBridgeCorrelation;
  payload?: Record<string, unknown>;
};

export const AdapterRoleSchema = z.enum([
  "planner",
  "executor",
  "scm_ci_provider",
  "notification_provider",
  "runtime_provider",
]);

export const AdapterStabilitySchema = z.enum([
  "stable",
  "experimental",
  "fixture-backed",
  "dogfooding",
]);

export type AdapterRole = z.infer<typeof AdapterRoleSchema>;
export type AdapterStability = z.infer<typeof AdapterStabilitySchema>;

export interface AdapterCapability {
  id: string;
  role: AdapterRole;
  label: string;
  provider: string;
  stability: AdapterStability;
  optional: boolean;
  dogfooding: boolean;
  capabilities: string[];
  event_families: string[];
  notes: string;
}

export interface ProviderStatus {
  provider: string;
  role: AdapterRole;
  status: "available" | "configured" | "degraded" | "missing" | "placeholder";
  configured: boolean;
  required_env?: string[];
  credential_values_exposed: false;
  message?: string;
}

export interface WorkOrder {
  work_order_id: string;
  title: string;
  description: string;
  kind: "docs" | "code" | "test" | "ops" | "manual";
  task_type?: string;
  risk: "low" | "medium" | "high";
  planner_adapter: string;
  created_at: string;
  constraints: string[];
  acceptance: string[];
  suggested_files: string[];
  allowed_paths?: string[];
  blocked_paths?: string[];
  validation?: string[];
  stop_criteria?: string[];
}

export type WorkerCapability =
  | "manual-execution"
  | "codex-exec"
  | "opencode-exec"
  | "filesystem"
  | "git"
  | "tests"
  | "docs"
  | "notifications"
  | string;

export type WorkerStatus = "online" | "stale" | "offline" | "disabled";
export type TaskStatus =
  | "queued"
  | "claimed"
  | "running"
  | "completed"
  | "failed"
  | "blocked"
  | "cancelled"
  | "stale";
export type TaskRisk = "low" | "medium" | "high";
export type GoalRisk = TaskRisk;
export type GoalPriority = "low" | "normal" | "high" | "urgent";
export type GoalStatus =
  | "draft"
  | "ready"
  | "queued"
  | "active"
  | "partially_completed"
  | "completed"
  | "failed"
  | "blocked"
  | "superseded"
  | "archived"
  | "paused"
  | "cancelled";
export type TaskSource =
  | "manual"
  | "planner"
  | "rule_based"
  | "hermes-planner"
  | "hermes"
  | "codex"
  | "opencode"
  | "custom";

export type PlannerDecisionAction =
  | "continue"
  | "repair"
  | "wait"
  | "stop"
  | "blocked";

export interface PlannerTaskSpec {
  title: string;
  task_type: string;
  risk: TaskRisk;
  prompt: string;
  allowed_paths: string[];
  blocked_paths: string[];
  validation: string[];
}

export interface PlannerAdapterMetadata {
  adapter: string;
  decision: PlannerDecisionAction;
  reason: string;
  task_type?: string;
  allowed_paths: string[];
  blocked_paths: string[];
  validation: string[];
  stop_criteria_status: string[];
  source_run_id?: string;
  created_at: string;
  raw_response_included: false;
  secrets_included: false;
}

export interface Project {
  project_id: string;
  name: string;
  repo?: string;
  description?: string;
  status: "active" | "paused" | "archived";
  control_state?: ProjectControlState;
  created_at: string;
  updated_at: string;
}

export interface ProjectControlState {
  state: "running" | "paused" | "stopped";
  stop_requested: boolean;
  max_rounds?: number;
  max_tasks?: number;
  current_worker_id?: string;
  current_task_id?: string;
  loop_task_count?: number;
  degraded_reason?: string;
  idle_since?: string;
  stop_reason?: string;
  last_error?: string;
  last_notification?: string;
  last_heartbeat?: string;
  updated_at: string;
}

export interface MasterGoal {
  goal_id: string;
  project_id: string;
  title: string;
  summary?: string;
  status: GoalStatus;
  source?: string;
  priority?: GoalPriority;
  risk?: GoalRisk;
  lifecycle?: string;
  acceptance_criteria?: string[];
  evidence_requirements?: string[];
  dedupe_key?: string;
  supersedes?: string[];
  superseded_by?: string;
  stale_reason?: string;
  blocked_reason?: string;
  planner_metadata?: PlannerAdapterMetadata;
  model_backend_metadata?: ModelBackendMetadata;
  completion_note?: string;
  evidence_summary?: EvidenceSummary;
  progress_summary?: GoalProgressSummary;
  created_at: string;
  updated_at: string;
}

export interface ModelBackendMetadata {
  adapter: string;
  backend?: string;
  model?: string;
  audit_only: true;
  raw_response_included: false;
  secrets_included: false;
}

export interface Worker {
  worker_id: string;
  name: string;
  provider: string;
  capabilities: WorkerCapability[];
  labels: string[];
  enabled: boolean;
  status: WorkerStatus;
  current_task_id?: string;
  last_seen_at?: string;
  created_at: string;
  updated_at: string;
}

export interface WorkerHeartbeat {
  heartbeat_id: string;
  worker_id: string;
  seen_at: string;
  status_note?: string;
  load?: number;
}

export interface TaskClaim {
  claim_id: string;
  task_id: string;
  worker_id: string;
  claimed_at: string;
}

export interface TaskResult {
  summary?: string;
  result_url?: string;
  pr_url?: string;
  error_summary?: string;
  evidence_summary?: EvidenceSummary;
}

export interface EvidenceSummary {
  task_id?: string;
  goal_id?: string;
  pr_url?: string;
  commit_sha?: string;
  changed_files?: string[];
  validation_status?: string;
  ci_status?: string;
  risk_status?: string;
  summary: string;
  created_at: string;
}

export interface GoalProgressSummary {
  total_tasks: number;
  queued_tasks: number;
  running_tasks: number;
  completed_tasks: number;
  failed_tasks: number;
  blocked_tasks: number;
  evidence_count: number;
  updated_at: string;
}

export interface Task {
  task_id: string;
  project_id: string;
  goal_id?: string;
  title: string;
  body?: string;
  prompt_summary?: string;
  status: TaskStatus;
  risk: TaskRisk;
  source: TaskSource;
  task_type?: string;
  planner_metadata?: PlannerAdapterMetadata;
  allowed_paths?: string[];
  blocked_paths?: string[];
  validation?: string[];
  required_capabilities: WorkerCapability[];
  assigned_worker_id?: string;
  claim?: TaskClaim;
  result?: TaskResult;
  created_at: string;
  updated_at: string;
}

export interface TaskEvent {
  task_event_id: string;
  task_id: string;
  type: Extract<SkyBridgeEventType, `task.${string}`>;
  worker_id?: string;
  time: string;
  message?: string;
  payload: Record<string, unknown>;
}

export interface PlannerDecision {
  decision_id: string;
  planner_adapter: string;
  decision: PlannerDecisionAction;
  reason: string;
  input_summary: string;
  task?: PlannerTaskSpec;
  work_orders: WorkOrder[];
  requires_human_review: boolean;
  stop_criteria_status: string[];
  created_at: string;
}

export interface ExecutionResult {
  execution_id: string;
  work_order_id: string;
  executor_adapter: string;
  status: "completed" | "failed" | "blocked" | "skipped";
  completed_at: string;
  summary: string;
  pr_number?: number;
  note?: string;
  events: SkyBridgeEvent[];
}

export interface NotificationJob {
  notification_job_id: string;
  provider: string;
  title: string;
  message: string;
  priority: "low" | "default" | "high" | "urgent";
  status: "queued" | "sent" | "skipped" | "failed";
  created_at: string;
  source_work_order_id?: string;
}

export const IterationStateSchema = z.enum([
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
]);

export type IterationState = z.infer<typeof IterationStateSchema>;

export interface IterationCheck {
  name: string;
  status: "pending" | "passed" | "failed" | "skipped";
  started_at?: string;
  completed_at?: string;
  exit_code?: number;
  summary?: string;
}

export interface IterationRun {
  iteration_id: string;
  project_id: string;
  goal_id?: string;
  repo: string;
  branch: string;
  base_branch: string;
  pr_number?: number;
  state: IterationState;
  attempts: number;
  max_attempts: number;
  last_error?: string;
  checks: IterationCheck[];
  auto_merge_enabled?: boolean;
  created_at: string;
  updated_at: string;
}

export interface RunSummary {
  run_id: string;
  session_id?: string;
  source_platform: SkyBridgeSourcePlatform;
  source_adapter: string;
  source_agent_id?: string;
  source_node_id?: string;
  status: "running" | "completed" | "failed" | "unknown";
  event_count: number;
  tool_call_count: number;
  active_tool_count: number;
  failed_tool_count: number;
  notification_count: number;
  first_seen_at: string;
  last_seen_at: string;
  last_event_type: SkyBridgeEventType;
  title?: string;
  lifecycle?: string;
  branch?: string;
  cwd?: string;
  goal?: string;
  goal_id?: string;
  latest_message_summary?: string;
}

export interface RunDetail {
  summary: RunSummary;
  events: SkyBridgeEvent[];
}

export interface SourceCapability {
  platform: SkyBridgeSourcePlatform;
  label: string;
  adapters: string[];
  event_families: string[];
  supports_remote_control: boolean;
  default_safe: boolean;
  notes: string;
}

export const ADAPTER_CAPABILITIES: AdapterCapability[] = [
  {
    id: "rule-based-planner",
    role: "planner",
    label: "Rule-Based Planner",
    provider: "skybridge",
    stability: "fixture-backed",
    optional: true,
    dogfooding: false,
    capabilities: ["docs-only-work-order", "safe-fixture-planning"],
    event_families: ["plan", "todo", "task"],
    notes:
      "Minimal planner proof that creates a low-risk docs WorkOrder without Hermes.",
  },
  {
    id: "hermes-api",
    role: "planner",
    label: "Hermes Agent",
    provider: "hermes",
    stability: "dogfooding",
    optional: true,
    dogfooding: true,
    capabilities: [
      "supervision",
      "nightly-report",
      "safe-run-smoke",
      "strict-json-planning",
      "docs-only-self-bootstrap",
    ],
    event_families: ["run", "tool", "message", "agent", "task"],
    notes:
      "Dogfooding planner/supervisor adapter; not required by SkyBridge Core.",
  },
  {
    id: "codex-exec-json",
    role: "executor",
    label: "Codex Exec",
    provider: "codex",
    stability: "dogfooding",
    optional: true,
    dogfooding: true,
    capabilities: ["bounded-execution", "jsonl-telemetry", "redacted-output"],
    event_families: [
      "session",
      "run",
      "turn",
      "tool",
      "file",
      "diff",
      "approval",
      "message",
    ],
    notes: "Dogfooding executor adapter used by local autonomous development.",
  },
  {
    id: "manual-executor",
    role: "executor",
    label: "Manual Executor",
    provider: "skybridge",
    stability: "fixture-backed",
    optional: true,
    dogfooding: false,
    capabilities: ["manual-result-registration", "pr-note-attachment"],
    event_families: ["run", "message", "task"],
    notes: "Minimal executor proof that records completed work without Codex.",
  },
  {
    id: "opencode-plugin",
    role: "executor",
    label: "OpenCode",
    provider: "opencode",
    stability: "fixture-backed",
    optional: true,
    dogfooding: false,
    capabilities: ["plugin-events", "tool-events", "todo-events"],
    event_families: [
      "session",
      "run",
      "tool",
      "file",
      "approval",
      "todo",
      "message",
      "agent",
    ],
    notes: "OpenCode event adapter foundation backed by fixtures.",
  },
  {
    id: "github-actions",
    role: "scm_ci_provider",
    label: "GitHub",
    provider: "github",
    stability: "dogfooding",
    optional: true,
    dogfooding: true,
    capabilities: ["pr-summary", "ci-status", "auto-merge-policy-dry-run"],
    event_families: ["iteration", "approval", "notification"],
    notes:
      "SCM/CI provider used for PR and CI policy; repository settings remain operator-owned.",
  },
  {
    id: "generic-scm",
    role: "scm_ci_provider",
    label: "Generic SCM",
    provider: "custom",
    stability: "experimental",
    optional: true,
    dogfooding: false,
    capabilities: ["placeholder-provider-contract"],
    event_families: ["iteration", "approval"],
    notes:
      "Placeholder proving SCM/CI is a provider boundary, not a GitHub-only core.",
  },
  {
    id: "ntfy",
    role: "notification_provider",
    label: "ntfy",
    provider: "ntfy",
    stability: "stable",
    optional: true,
    dogfooding: true,
    capabilities: ["direct-send", "skipped-placeholder", "bootstrap-fallback"],
    event_families: ["notification"],
    notes: "First notification provider; optional and replaceable.",
  },
  {
    id: "generic-notification",
    role: "notification_provider",
    label: "Generic Notification Provider",
    provider: "custom",
    stability: "experimental",
    optional: true,
    dogfooding: false,
    capabilities: ["placeholder-provider-contract"],
    event_families: ["notification"],
    notes: "Placeholder proving notification routing is provider-agnostic.",
  },
  {
    id: "sidecar",
    role: "runtime_provider",
    label: "Local Sidecar",
    provider: "skybridge",
    stability: "experimental",
    optional: true,
    dogfooding: false,
    capabilities: ["node-heartbeat", "event-forwarding"],
    event_families: ["node", "agent", "worker", "task"],
    notes:
      "Runtime worker provider boundary for future local and remote nodes.",
  },
];

export const SOURCE_CAPABILITIES: SourceCapability[] = [
  {
    platform: "codex",
    label: "Codex",
    adapters: ["codex-hook", "codex-exec-json", "codex-appserver"],
    event_families: [
      "session",
      "run",
      "turn",
      "tool",
      "file",
      "diff",
      "approval",
      "message",
      "agent",
      "notification",
    ],
    supports_remote_control: false,
    default_safe: true,
    notes:
      "Local hook and exec telemetry with command, prompt and output redaction by default.",
  },
  {
    platform: "opencode",
    label: "OpenCode",
    adapters: ["opencode-plugin"],
    event_families: [
      "session",
      "run",
      "tool",
      "file",
      "approval",
      "todo",
      "message",
      "agent",
    ],
    supports_remote_control: false,
    default_safe: true,
    notes:
      "Plugin event telemetry normalized from status, tool, file, permission and todo events.",
  },
  {
    platform: "hermes",
    label: "Hermes Agent",
    adapters: ["hermes-api"],
    event_families: ["run", "tool", "message", "agent"],
    supports_remote_control: false,
    default_safe: true,
    notes:
      "API and stream event telemetry normalized from run status and event stream samples.",
  },
  {
    platform: "skybridge",
    label: "SkyBridge",
    adapters: [
      "yolo-runner",
      "self-observation-smoke",
      "demo-dataset",
      "sidecar",
    ],
    event_families: [
      "run",
      "tool",
      "notification",
      "agent",
      "node",
      "worker",
      "project",
      "goal",
      "task",
      "approval",
      "iteration",
    ],
    supports_remote_control: false,
    default_safe: true,
    notes: "First-party runner, smoke, node and dogfooding telemetry.",
  },
  {
    platform: "custom",
    label: "Custom Agent",
    adapters: ["custom"],
    event_families: [
      "session",
      "run",
      "turn",
      "tool",
      "file",
      "diff",
      "approval",
      "message",
      "agent",
      "notification",
    ],
    supports_remote_control: false,
    default_safe: false,
    notes:
      "Bring-your-own adapter; events must be normalized and redacted before ingestion.",
  },
];

export const SharedRedactionRules = redactionRules;

export function createEvent(input: SkyBridgeEventInput): SkyBridgeEvent {
  return SkyBridgeEventSchema.parse({
    schema: SKYBRIDGE_EVENT_SCHEMA_VERSION,
    time: input.time ?? new Date().toISOString(),
    ...input,
  });
}

export function parseEvent(input: unknown): SkyBridgeEvent {
  return SkyBridgeEventSchema.parse(input);
}

export function isNotificationTrigger(
  event: Pick<SkyBridgeEvent, "type">,
): boolean {
  return (
    event.type === "run.failed" ||
    event.type === "approval.requested" ||
    event.type === "notification.requested"
  );
}

export function listAdapterCapabilities(
  role?: AdapterRole,
): AdapterCapability[] {
  return ADAPTER_CAPABILITIES.filter(
    (capability) => !role || capability.role === role,
  );
}

export function createRuleBasedPlannerDecision(input: {
  goal: string;
  now?: string;
  plannerAdapter?: string;
}): PlannerDecision {
  const now = input.now ?? new Date().toISOString();
  const normalized = input.goal.trim().replace(/\s+/g, " ");
  const summary =
    normalized.length > 160 ? `${normalized.slice(0, 157)}...` : normalized;
  const slug =
    summary
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 48) || "docs-task";
  const workOrder: WorkOrder = {
    work_order_id: `wo_docs_${slug}`,
    title: `Docs-only task: ${summary || "Review product documentation"}`,
    description:
      "Review and update documentation only. Do not change runtime code, secrets, deployment settings or GitHub settings.",
    kind: "docs",
    risk: "low",
    planner_adapter: input.plannerAdapter ?? "rule-based-planner",
    created_at: now,
    constraints: [
      "docs-only",
      "no secrets",
      "no deployment",
      "no GitHub settings mutation",
    ],
    acceptance: [
      "Documentation describes the requested goal.",
      "No runtime behavior changes are required.",
      "The change can be reviewed independently.",
    ],
    suggested_files: ["README.md", "docs/"],
    task_type: "docs",
    allowed_paths: ["README.md", "docs/"],
    blocked_paths: [".env", "config/*.secret.ps1", ".agent/", ".data/"],
    validation: ["corepack pnpm check"],
    stop_criteria: ["docs-only change is complete"],
  };

  return {
    decision_id: `pd_${slug || "docs_task"}`,
    planner_adapter: workOrder.planner_adapter,
    decision: "continue",
    reason: "A low-risk documentation task can safely advance the goal.",
    input_summary: summary,
    task: {
      title: workOrder.title,
      task_type: workOrder.task_type ?? workOrder.kind,
      risk: workOrder.risk,
      prompt: workOrder.description,
      allowed_paths: workOrder.allowed_paths ?? [],
      blocked_paths: workOrder.blocked_paths ?? [],
      validation: workOrder.validation ?? [],
    },
    work_orders: [workOrder],
    requires_human_review: false,
    stop_criteria_status: ["not_started"],
    created_at: now,
  };
}

export function createManualExecutionResult(input: {
  workOrder: WorkOrder;
  summary: string;
  prNumber?: number;
  note?: string;
  now?: string;
  executorAdapter?: string;
}): ExecutionResult {
  const now = input.now ?? new Date().toISOString();
  const event = createEvent({
    type: "run.completed",
    time: now,
    source: {
      platform: "skybridge",
      adapter: input.executorAdapter ?? "manual-executor",
    },
    correlation: { run_id: input.workOrder.work_order_id },
    payload: {
      title: input.workOrder.title,
      work_order_id: input.workOrder.work_order_id,
      planner_adapter: input.workOrder.planner_adapter,
      executor_adapter: input.executorAdapter ?? "manual-executor",
      summary: input.summary,
      pr_number: input.prNumber,
      note: input.note,
      manual_result: true,
    },
  });

  return {
    execution_id: `exec_${input.workOrder.work_order_id}`,
    work_order_id: input.workOrder.work_order_id,
    executor_adapter: input.executorAdapter ?? "manual-executor",
    status: "completed",
    completed_at: now,
    summary: input.summary,
    pr_number: input.prNumber,
    note: input.note,
    events: [event],
  };
}

export function redactForTelemetry(input: unknown): unknown {
  return redactValue(input, 0);
}

function redactValue(input: unknown, depth: number): unknown {
  if (depth > 8) return "[REDACTED:depth]";
  if (typeof input === "string") return redactString(input);
  if (Array.isArray(input))
    return input.slice(0, 100).map((item) => redactValue(item, depth + 1));
  if (!input || typeof input !== "object") return input;
  const output: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (matchesAny(key, redactionRules.secretKeyPatterns)) {
      output[key] = redactionRules.replacement;
      continue;
    }
    if (matchesAny(key, redactionRules.omitKeyPatterns)) {
      output[key] = summarizeOmitted(value);
      continue;
    }
    output[key] = redactValue(value, depth + 1);
  }
  return output;
}

function redactString(input: string): string {
  let output = input;
  for (const pattern of redactionRules.secretValuePatterns) {
    output = output.replace(
      new RegExp(pattern, "gi"),
      redactionRules.replacement,
    );
  }
  return output.length > redactionRules.maxStringLength
    ? `${output.slice(0, redactionRules.maxStringLength)}...`
    : output;
}

function summarizeOmitted(value: unknown): Record<string, unknown> {
  const text =
    typeof value === "string" ? value : JSON.stringify(value ?? null);
  return {
    omitted: true,
    length: text.length,
    reason: "unsafe_raw_payload",
  };
}

function matchesAny(input: string, patterns: string[]): boolean {
  return patterns.some((pattern) => new RegExp(pattern, "i").test(input));
}
