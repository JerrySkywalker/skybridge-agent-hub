import { z } from "zod";
import redactionRules from "./redaction-rules.json" with { type: "json" };
import taskTemplateRegistryData from "./task-template-registry.json" with { type: "json" };
export * from "./control-plane.js";
export * from "./reliability.js";

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
  "task.updated",
  "task.requeued",
  "task.evidence_repaired",
  "campaign.created",
  "campaign.imported",
  "campaign.started",
  "campaign.paused",
  "campaign.held",
  "campaign.completed",
  "campaign.failed",
  "campaign.step.ready",
  "campaign.step.started",
  "campaign.step.completed",
  "campaign.step.recovered",
  "campaign.step.failed",
  "campaign.step.held",
  "campaign.step.skipped",
  "campaign.step.gate_previewed",
  "campaign.step.hermes_gate_evaluated",
  "campaign.step.advance_allowed",
  "campaign.step.advance_blocked",
  "campaign.step.advanced",
  "campaign.step.evidence_attached",
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
export const ManualTaskStatusSchema = z.enum([
  "queued",
  "running",
  "succeeded",
  "failed",
  "blocked",
  "cancelled",
]);
export const ManualTaskProviderSchema = z.object({
  schema: z.literal("skybridge.manual_task_provider.v1"),
  provider_id: z.enum(["mock", "hermes_deepseek", "skybridge_server_hermes"]),
  status: z.string().min(1).optional(),
  configured: z.boolean().optional(),
  deterministic: z.boolean(),
  network_enabled: z.boolean(),
  hermes_live_call_enabled: z.literal(false),
  server_mediated_llm_inference_enabled: z.boolean().optional(),
  cloud_hermes_provider_enabled: z.boolean().optional(),
  remote_llm_inference_enabled: z.literal(false).optional(),
  disabled_by_default: z.boolean().optional(),
  deprecated: z.boolean().optional(),
  preview_only: z.boolean().optional(),
  ci_disabled: z.boolean().optional(),
  config_values_redacted: z.literal(true).optional(),
  raw_request_persisted: z.literal(false),
  raw_response_persisted: z.literal(false),
  reason: z.string().optional(),
  token_printed: z.literal(false),
});
export const ManualTaskSchema = z.object({
  schema: z.literal("skybridge.manual_task.v1"),
  task_id: z.string().min(1),
  status: ManualTaskStatusSchema,
  input_preview: z.string().max(200),
  input_hash: z.string().min(12),
  result_preview: z.string().max(240).optional(),
  result_hash: z.string().min(12).optional(),
  provider_id: z.enum(["mock", "hermes_deepseek", "skybridge_server_hermes"]).optional(),
  provider_status: z.string().optional(),
  duration_ms: z.number().nonnegative().optional(),
  error_summary: z.string().max(240).optional(),
  server_mediated_llm_inference_enabled: z.boolean().optional(),
  cloud_hermes_provider_enabled: z.boolean().optional(),
  live_call_performed: z.boolean().optional(),
  remote_llm_inference_enabled: z.boolean().optional(),
  command_text_detected: z.boolean(),
  prompt_body_persisted: z.literal(false),
  output_executed: z.literal(false).optional(),
  command_executed: z.literal(false).optional(),
  created_at: z.string().datetime(),
  updated_at: z.string().datetime(),
  token_printed: z.literal(false),
});
export const ManualTaskResultSchema = z.object({
  schema: z.literal("skybridge.manual_task_result.v1"),
  task_id: z.string().optional(),
  provider: ManualTaskProviderSchema.optional(),
  provider_id: z.enum(["mock", "hermes_deepseek", "skybridge_server_hermes"]).optional(),
  provider_status: z.string().optional(),
  status: z.enum(["succeeded", "failed", "blocked"]),
  result_preview: z.string().max(240).optional(),
  result_hash: z.string().min(12).optional(),
  duration_ms: z.number().nonnegative().optional(),
  error_summary: z.string().max(240).optional(),
  server_mediated_llm_inference_enabled: z.boolean().optional(),
  cloud_hermes_provider_enabled: z.boolean().optional(),
  live_call_performed: z.boolean().optional(),
  remote_llm_inference_enabled: z.boolean().optional(),
  output_executed: z.literal(false),
  command_executed: z.literal(false).optional(),
  workunit_created: z.literal(false).optional(),
  task_created: z.literal(false).optional(),
  task_claim_created: z.literal(false).optional(),
  remote_execution_enabled: z.literal(false).optional(),
  arbitrary_command_enabled: z.literal(false).optional(),
  task_pr_created: z.literal(false).optional(),
  queue_apply_enabled: z.literal(false).optional(),
  token_printed: z.literal(false),
});
export const ManualTaskQueueSchema = z.object({
  schema: z.literal("skybridge.manual_task_queue.v1"),
  queue_id: z.string().min(1),
  provider: ManualTaskProviderSchema,
  provider_status: z.string().optional(),
  tasks: z.array(ManualTaskSchema),
  state_machine: z.array(ManualTaskStatusSchema),
  execution_enabled: z.literal(false),
  worker_execution_started: z.literal(false),
  workunit_created: z.literal(false),
  task_created: z.literal(false),
  task_claim_created: z.literal(false),
  task_pr_created: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  remote_llm_inference_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  host_mutation_performed: z.literal(false),
  prompt_body_persisted: z.literal(false),
  transcript_body_persisted: z.literal(false),
  raw_request_persisted: z.literal(false).optional(),
  raw_response_persisted: z.literal(false).optional(),
  raw_logs_persisted: z.literal(false),
  updated_at: z.string().datetime(),
  token_printed: z.literal(false),
});
export const ManualTaskProviderListSchema = z.object({
  schema: z.literal("skybridge.manual_task_provider_list.v1"),
  default_provider_id: z.literal("mock"),
  providers: z.array(ManualTaskProviderSchema),
  live_call_disabled_by_default: z.literal(true),
  token_printed: z.literal(false),
});
export const ManualTaskProviderReportSchema = z.object({
  schema: z.literal("skybridge.manual_task_provider_report.v1"),
  status: z.string().min(1),
  default_provider_id: z.literal("mock"),
  provider_list: ManualTaskProviderListSchema,
  hermes_disabled_by_default: z.literal(true),
  no_hermes_live_call_in_ci: z.literal(true),
  raw_request_persisted: z.literal(false),
  raw_response_persisted: z.literal(false),
  output_executed: z.literal(false),
  worker_execution_started: z.literal(false),
  workunit_created: z.literal(false),
  task_created: z.literal(false),
  task_claim_created: z.literal(false),
  task_pr_created: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const ToolProviderTypeSchema = z.enum([
  "direct",
  "hermes",
  "mcp",
  "disabled",
  "future",
]);
export const ToolProviderStatusSchema = z.enum([
  "available",
  "unavailable",
  "disabled",
  "future",
  "warning",
  "blocked",
]);
export const ToolProviderToolStatusSchema = z.enum([
  "detected",
  "missing",
  "disabled",
  "future",
  "warning",
  "blocked",
]);
export const ToolProviderSchema = z.object({
  provider_id: z.string().min(1),
  provider_type: ToolProviderTypeSchema,
  display_name: z.string().min(1),
  status: ToolProviderStatusSchema,
  tools: z.array(z.string().min(1)),
  default_for_tools: z.array(z.string().min(1)),
  execution_enabled: z.literal(false),
  notes: z.array(z.string()),
  warnings: z.array(z.string()),
  blockers: z.array(z.string()),
});
export const ToolProviderToolSchema = z.object({
  tool_id: z.string().min(1),
  display_name: z.string().min(1),
  provider_id: z.string().min(1),
  detection_method: z.string().min(1),
  executable_path_safe: z.string(),
  version_summary_safe: z.string(),
  status: ToolProviderToolStatusSchema,
  can_preview: z.boolean(),
  can_execute_now: z.literal(false),
  requires_exact_confirmation: z.literal(true),
  requires_template: z.literal(true),
  requires_allowlist: z.literal(true),
  warnings: z.array(z.string()),
  blockers: z.array(z.string()),
});
export const ToolProviderInventorySchema = z.object({
  schema: z.literal("skybridge.tool_provider.v1"),
  generated_at: z.string().datetime(),
  host_os: z.string().min(1),
  host_name_safe: z.string().min(1),
  project_id: z.string().min(1),
  provider_inventory: z.string().min(1),
  providers: z.array(ToolProviderSchema),
  tools: z.array(ToolProviderToolSchema),
  defaults: z.record(z.string()),
  disabled_capabilities: z.array(z.string()),
  warnings: z.array(z.string()),
  blockers: z.array(z.string()),
  execution_allowed: z.literal(false),
  task_created: z.literal(false),
  task_claimed: z.literal(false),
  execution_started: z.literal(false),
  codex_run_called: z.literal(false),
  matlab_run_called: z.literal(false),
  hermes_run_called: z.literal(false),
  mcp_run_called: z.literal(false),
  worker_loop_started: z.literal(false),
  project_control_unpaused: z.literal(false),
  token_printed: z.literal(false),
});

export const SingleGoalLoopModeSchema = z.enum(["fixture", "live"]);
export const SingleGoalLoopSafetyFlagsSchema = z.object({
  codex_run_called: z.literal(false),
  matlab_run_called: z.literal(false),
  hermes_run_called: z.literal(false),
  mcp_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  worker_loop_started: z.literal(false),
  project_control_unpaused: z.literal(false),
  token_printed: z.literal(false),
});
export const SingleGoalLoopEvidenceSchema = SingleGoalLoopSafetyFlagsSchema.extend({
  schema: z.literal("skybridge.single_goal_loop_evidence.v1"),
  campaign_id: z.string().min(1),
  step_id: z.string().min(1),
  task_id: z.string().min(1),
  worker_id: z.string().min(1),
  template_id: z.literal("safe-local-smoke.v1"),
  runner_id: z.literal("safe-local-smoke-runner.v1"),
  provider_inventory_checked: z.literal(true),
  direct_provider_available: z.literal(true),
  task_claimed_count: z.literal(1),
  execution_started: z.literal(true),
  execution_completed: z.literal(true),
  execution_failed: z.literal(false),
  changed_files: z.array(z.string()),
});
export const SingleGoalLoopSchema = SingleGoalLoopSafetyFlagsSchema.extend({
  schema: z.literal("skybridge.single_goal_loop.v1"),
  generated_at: z.string().datetime(),
  mode: SingleGoalLoopModeSchema,
  project_id: z.string().min(1),
  campaign_id: z.string().min(1),
  step_id: z.string().min(1),
  task_id: z.string().min(1),
  worker_id: z.string().min(1),
  provider_inventory_checked: z.boolean(),
  direct_provider_available: z.boolean(),
  template_id: z.literal("safe-local-smoke.v1"),
  runner_id: z.literal("safe-local-smoke-runner.v1"),
  preview_only: z.boolean(),
  apply_confirmed: z.boolean(),
  task_created: z.boolean(),
  task_claimed: z.boolean(),
  execution_started: z.boolean(),
  execution_completed: z.boolean(),
  execution_failed: z.boolean(),
  evidence_attached: z.boolean(),
  step_completed: z.boolean(),
  campaign_completed: z.boolean(),
  blockers: z.array(z.string()),
  warnings: z.array(z.string()),
  safety_flags: SingleGoalLoopSafetyFlagsSchema,
  task_created_count: z.number().int().min(0).max(1).optional(),
  task_claimed_count: z.number().int().min(0).max(1).optional(),
  execution_completed_count: z.number().int().min(0).max(1).optional(),
  evidence: SingleGoalLoopEvidenceSchema.optional(),
  report_json_path: z.string().optional(),
  report_markdown_path: z.string().optional(),
});

export const MultiGoalLoopModeSchema = z.enum(["fixture", "live"]);
export const MultiGoalLoopStepStateSchema = z.enum(["pending", "ready", "running", "completed", "failed", "held", "blocked"]);
export const MultiGoalLoopSafetyFlagsSchema = z.object({
  codex_run_called: z.boolean(),
  matlab_run_called: z.boolean(),
  hermes_run_called: z.literal(false),
  mcp_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  worker_loop_started: z.literal(false),
  project_control_unpaused: z.literal(false),
  token_printed: z.literal(false),
});
export const MultiGoalLoopStepSchema = z.object({
  step_id: z.string().min(1),
  order: z.number().int().min(1),
  state: MultiGoalLoopStepStateSchema,
  template_id: z.string().min(1),
  runner_id: z.string().min(1),
  task_id: z.string().min(1),
  dependencies: z.array(z.string()),
  dependency_status: z.enum(["ready", "blocked", "complete"]),
  provider_required: z.string().min(1),
  provider_available: z.boolean(),
  can_preview: z.boolean(),
  can_apply_next: z.boolean(),
  evidence_attached: z.boolean(),
  completed: z.boolean(),
  failed: z.boolean(),
  held: z.boolean(),
  blockers: z.array(z.string()),
  warnings: z.array(z.string()),
});
export const MultiGoalLoopEvidenceSchema = MultiGoalLoopSafetyFlagsSchema.extend({
  schema: z.literal("skybridge.multi_goal_loop_evidence.v1"),
  campaign_id: z.string().min(1),
  step_id: z.string().min(1),
  task_id: z.string().min(1),
  worker_id: z.string().min(1),
  template_id: z.string().min(1),
  runner_id: z.string().min(1),
  provider_inventory_checked: z.literal(true),
  direct_provider_available: z.literal(true),
  task_claimed_count: z.literal(1),
  execution_started: z.literal(true),
  execution_completed: z.boolean(),
  execution_failed: z.boolean(),
  changed_files: z.array(z.string()),
  produced_artifacts_safe: z.array(z.string()),
  validation_summary_safe: z.string().min(1),
});
export const MultiGoalLoopSchema = MultiGoalLoopSafetyFlagsSchema.extend({
  schema: z.literal("skybridge.multi_goal_loop.v1"),
  generated_at: z.string().datetime(),
  mode: MultiGoalLoopModeSchema,
  project_id: z.string().min(1),
  campaign_id: z.string().min(1),
  worker_id: z.string().min(1),
  current_step_id: z.string(),
  next_step_id: z.string(),
  steps: z.array(MultiGoalLoopStepSchema).length(3),
  provider_inventory_checked: z.boolean(),
  direct_provider_available: z.boolean(),
  preview_only: z.boolean(),
  apply_confirmed: z.boolean(),
  max_steps: z.literal(1),
  selected_step_count: z.number().int().min(0).max(1),
  selected_task_count: z.number().int().min(0).max(1),
  task_created_count: z.number().int().min(0).max(1),
  task_claimed_count: z.number().int().min(0).max(1),
  execution_started_count: z.number().int().min(0).max(1),
  execution_completed_count: z.number().int().min(0).max(1),
  execution_failed_count: z.number().int().min(0).max(1),
  evidence_attached_count: z.number().int().min(0).max(1),
  step_completed_count: z.number().int().min(0).max(1),
  campaign_completed: z.boolean(),
  campaign_held: z.boolean(),
  blockers: z.array(z.string()),
  warnings: z.array(z.string()),
  safety_flags: MultiGoalLoopSafetyFlagsSchema,
  evidence: MultiGoalLoopEvidenceSchema.optional(),
  report_json_path: z.string().optional(),
  report_markdown_path: z.string().optional(),
});
export const ManualTaskAuditSchema = z.object({
  schema: z.literal("skybridge.manual_task_audit.v1"),
  action: z.enum(["add-question", "clear-completed"]),
  accepted: z.boolean().optional(),
  task: ManualTaskSchema.optional(),
  cleared: z.number().optional(),
  remaining: z.number().optional(),
  prompt_body_persisted: z.literal(false).optional(),
  token_printed: z.literal(false),
});
export type ManualTaskStatus = z.infer<typeof ManualTaskStatusSchema>;
export type ManualTaskProvider = z.infer<typeof ManualTaskProviderSchema>;
export type ManualTask = z.infer<typeof ManualTaskSchema>;
export type ManualTaskResult = z.infer<typeof ManualTaskResultSchema>;
export type ManualTaskQueue = z.infer<typeof ManualTaskQueueSchema>;
export type ManualTaskProviderList = z.infer<typeof ManualTaskProviderListSchema>;
export type ManualTaskProviderReport = z.infer<typeof ManualTaskProviderReportSchema>;
export type ToolProviderType = z.infer<typeof ToolProviderTypeSchema>;
export type ToolProviderStatus = z.infer<typeof ToolProviderStatusSchema>;
export type ToolProviderToolStatus = z.infer<typeof ToolProviderToolStatusSchema>;
export type ToolProvider = z.infer<typeof ToolProviderSchema>;
export type ToolProviderTool = z.infer<typeof ToolProviderToolSchema>;
export type ToolProviderInventory = z.infer<typeof ToolProviderInventorySchema>;
export type SingleGoalLoopMode = z.infer<typeof SingleGoalLoopModeSchema>;
export type SingleGoalLoopSafetyFlags = z.infer<typeof SingleGoalLoopSafetyFlagsSchema>;
export type SingleGoalLoopEvidence = z.infer<typeof SingleGoalLoopEvidenceSchema>;
export type SingleGoalLoop = z.infer<typeof SingleGoalLoopSchema>;
export type MultiGoalLoopMode = z.infer<typeof MultiGoalLoopModeSchema>;
export type MultiGoalLoopStepState = z.infer<typeof MultiGoalLoopStepStateSchema>;
export type MultiGoalLoopSafetyFlags = z.infer<typeof MultiGoalLoopSafetyFlagsSchema>;
export type MultiGoalLoopStep = z.infer<typeof MultiGoalLoopStepSchema>;
export type MultiGoalLoopEvidence = z.infer<typeof MultiGoalLoopEvidenceSchema>;
export type MultiGoalLoop = z.infer<typeof MultiGoalLoopSchema>;
export type ManualTaskAudit = z.infer<typeof ManualTaskAuditSchema>;

export const ChatToTaskDraftTypeSchema = z.enum([
  "task",
  "campaign",
  "clarifying_question",
]);
export const ChatToTaskSessionSchema = z.object({
  schema: z.literal("skybridge.chat_to_task_session.v1"),
  session_id: z.string().min(1),
  project_id: z.string().min(1),
  planner_id: z.string().min(1),
  input_preview: z.string().max(240),
  input_hash: z.string().min(12),
  raw_prompt_persisted: z.literal(false),
  raw_response_persisted: z.literal(false),
  task_created: z.literal(false),
  campaign_created: z.literal(false),
  claim_created: z.literal(false),
  execution_started: z.literal(false),
  codex_run_called: z.literal(false),
  matlab_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  token_printed: z.literal(false),
});
const ChatToTaskDraftCommonSchema = z.object({
  draft_id: z.string().min(1),
  template_id: z.string().min(1),
  project_id: z.string().min(1),
  title: z.string().min(1),
  summary: z.string().min(1),
  risk: z.string().min(1),
  required_capabilities: z.array(z.string()),
  allowed_paths: z.array(z.string()),
  blocked_paths: z.array(z.string()),
  validation: z.array(z.string()),
  runner_id: z.string().min(1),
  evidence_schema: z.array(z.string()),
  planner_id: z.string().min(1),
  input_preview: z.string().max(240),
  input_hash: z.string().min(12),
  raw_prompt_persisted: z.literal(false),
  raw_response_persisted: z.literal(false),
  task_created: z.literal(false),
  campaign_created: z.literal(false),
  claim_created: z.literal(false),
  execution_started: z.literal(false),
  codex_run_called: z.literal(false),
  matlab_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  token_printed: z.literal(false),
});
export const TaskDraftSchema = ChatToTaskDraftCommonSchema.extend({
  schema: z.literal("skybridge.task_draft.v1"),
  draft_type: z.literal("task"),
  inputs: z.record(z.unknown()).default({}),
});
export const CampaignDraftSchema = ChatToTaskDraftCommonSchema.extend({
  schema: z.literal("skybridge.campaign_draft.v1"),
  draft_type: z.literal("campaign"),
  inputs: z.record(z.unknown()).default({}),
});
export const TaskDraftClarifyingQuestionSchema = ChatToTaskDraftCommonSchema.extend({
  schema: z.literal("skybridge.task_draft_clarifying_question.v1"),
  draft_type: z.literal("clarifying_question"),
  questions: z.array(z.string()).min(1),
  blocked: z.boolean().default(false),
});
export const TaskDraftPreviewSchema = z.object({
  schema: z.literal("skybridge.task_draft_preview.v1"),
  ok: z.boolean(),
  status: z.enum(["preview", "needs_clarification", "blocked"]),
  draft_id: z.string().min(1),
  draft_type: ChatToTaskDraftTypeSchema,
  template_id: z.string().min(1),
  project_id: z.string().min(1),
  planner_id: z.string().min(1),
  session: ChatToTaskSessionSchema,
  draft: z.union([
    TaskDraftSchema,
    CampaignDraftSchema,
    TaskDraftClarifyingQuestionSchema,
  ]),
  command_text_detected: z.boolean(),
  unsafe_request_detected: z.boolean(),
  blockers: z.array(z.string()),
  warnings: z.array(z.string()),
  next_safe_action: z.string().min(1),
  input_preview: z.string().max(240),
  input_hash: z.string().min(12),
  raw_prompt_persisted: z.literal(false),
  raw_response_persisted: z.literal(false),
  task_created: z.literal(false),
  campaign_created: z.literal(false),
  claim_created: z.literal(false),
  execution_started: z.literal(false),
  codex_run_called: z.literal(false),
  matlab_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  token_printed: z.literal(false),
});
export type ChatToTaskDraftType = z.infer<typeof ChatToTaskDraftTypeSchema>;
export type ChatToTaskSession = z.infer<typeof ChatToTaskSessionSchema>;
export type TaskDraft = z.infer<typeof TaskDraftSchema>;
export type CampaignDraft = z.infer<typeof CampaignDraftSchema>;
export type TaskDraftClarifyingQuestion = z.infer<typeof TaskDraftClarifyingQuestionSchema>;
export type TaskDraftPreview = z.infer<typeof TaskDraftPreviewSchema>;

export const DraftReviewStatusSchema = z.enum([
  "ready_for_submit_preview",
  "ready_for_confirmation",
  "submitted",
  "blocked",
]);
export const DraftSubmitDraftTypeSchema = z.enum(["task", "campaign"]);
const DraftSubmitCommonSchema = z.object({
  ok: z.boolean(),
  draft_id: z.string().min(1),
  draft_type: DraftSubmitDraftTypeSchema,
  template_id: z.string().min(1),
  project_id: z.string().min(1),
  title: z.string().min(1),
  risk: z.string().min(1),
  required_capabilities: z.array(z.string()),
  allowed_paths: z.array(z.string()),
  blocked_paths: z.array(z.string()),
  runner_id: z.string().min(1),
  evidence_schema: z.array(z.string()),
  review_status: DraftReviewStatusSchema,
  review_reason: z.string().min(1),
  submitted_by: z.string().min(1),
  created_task_id: z.string().min(1).optional(),
  created_campaign_id: z.string().min(1).optional(),
  created_campaign_step_ids: z.array(z.string().min(1)).optional(),
  task_created: z.boolean(),
  campaign_created: z.boolean(),
  claim_created: z.literal(false),
  execution_started: z.literal(false),
  codex_run_called: z.literal(false),
  matlab_run_called: z.literal(false),
  worker_loop_started: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  project_control_unpause: z.literal(false).optional(),
  raw_prompt_persisted: z.literal(false),
  raw_response_persisted: z.literal(false),
  token_printed: z.literal(false),
  next_safe_action: z.string().min(1).optional(),
});
export const DraftReviewSchema = DraftSubmitCommonSchema.extend({
  schema: z.literal("skybridge.draft_review.v1"),
  task_created: z.literal(false),
  campaign_created: z.literal(false),
});
export const DraftSubmitPreviewSchema = DraftSubmitCommonSchema.extend({
  schema: z.literal("skybridge.draft_submit_preview.v1"),
  task_created: z.literal(false),
  campaign_created: z.literal(false),
});
export const DraftSubmitResultSchema = DraftSubmitCommonSchema.extend({
  schema: z.literal("skybridge.draft_submit_result.v1"),
});
export type DraftReviewStatus = z.infer<typeof DraftReviewStatusSchema>;
export type DraftSubmitDraftType = z.infer<typeof DraftSubmitDraftTypeSchema>;
export type DraftReview = z.infer<typeof DraftReviewSchema>;
export type DraftSubmitPreview = z.infer<typeof DraftSubmitPreviewSchema>;
export type DraftSubmitResult = z.infer<typeof DraftSubmitResultSchema>;

export const WorkerTemplateRunnerModeSchema = z.enum(["preview", "apply"]);
const TemplateRunnerCommonSchema = z.object({
  ok: z.boolean(),
  mode: WorkerTemplateRunnerModeSchema,
  worker_id: z.string().min(1),
  project_id: z.string().min(1),
  task_id: z.string().min(1).nullable().optional(),
  expected_task_id: z.string().min(1).optional(),
  template_id: z.string().min(1).nullable().optional(),
  runner_id: z.string().min(1).nullable().optional(),
  evidence_schema: z.string().min(1).optional(),
  selected: z.boolean(),
  eligible: z.boolean(),
  selected_task_count: z.number().int().min(0).optional(),
  rejected_reason: z.string(),
  claim_created: z.boolean(),
  task_claimed_count: z.number().int().min(0).optional(),
  old_task_claimed: z.literal(false).optional(),
  execution_started: z.boolean(),
  execution_completed: z.boolean(),
  execution_failed: z.boolean(),
  evidence_present: z.boolean(),
  evidence: z.record(z.string(), z.unknown()).nullable().optional(),
  allowed_paths_checked: z.boolean(),
  blocked_paths_checked: z.boolean(),
  changed_files: z.array(z.string()),
  validation_status: z.string().min(1),
  result_summary: z.string(),
  final_task_state: z.string().optional(),
  cloud_worker_status: z.string().optional(),
  pr_created: z.literal(false),
  codex_run_called: z.literal(false),
  matlab_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  worker_loop_started: z.literal(false),
  unbounded_run_enabled: z.literal(false),
  project_control_unpaused: z.literal(false),
  token_printed: z.literal(false),
});
export const WorkerTemplateRunnerSchema = TemplateRunnerCommonSchema.extend({
  schema: z.literal("skybridge.worker_template_runner.v1"),
});
export const WorkerTemplateRunnerPreviewSchema = TemplateRunnerCommonSchema.extend({
  schema: z.literal("skybridge.worker_template_runner_preview.v1"),
  mode: z.literal("preview"),
  claim_created: z.literal(false),
  execution_started: z.literal(false),
  execution_completed: z.literal(false),
  execution_failed: z.literal(false),
});
export const WorkerTemplateRunnerResultSchema = TemplateRunnerCommonSchema.extend({
  schema: z.literal("skybridge.worker_template_runner_result.v1"),
  mode: z.literal("apply"),
});
export const TemplateRunnerEvidenceSchema = z.object({
  schema: z.union([
    z.literal("skybridge.template_runner_evidence.v1"),
    z.literal("skybridge.live_safe_template_task_evidence.v1"),
  ]),
  ok: z.boolean(),
  worker_id: z.string().min(1),
  project_id: z.string().min(1),
  task_id: z.string().min(1),
  template_id: z.string().min(1),
  runner_id: z.string().min(1),
  evidence_schema_id: z.string().min(1),
  evidence_path: z.string().optional(),
  started_at: z.string().optional(),
  completed_at: z.string().nullable().optional(),
  failed_at: z.string().nullable().optional(),
  changed_files: z.array(z.string()),
  allowed_paths_checked: z.literal(true).optional(),
  blocked_paths_checked: z.literal(true).optional(),
  old_task_claimed: z.literal(false).optional(),
  task_claimed_count: z.number().int().min(0).optional(),
  validation_status: z.string().min(1),
  result_summary: z.string(),
  pr_created: z.literal(false),
  codex_run_called: z.literal(false),
  matlab_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  worker_loop_started: z.literal(false),
  unbounded_run_enabled: z.literal(false),
  project_control_unpaused: z.literal(false),
  raw_logs_included: z.literal(false),
  token_printed: z.literal(false),
});
export type WorkerTemplateRunnerMode = z.infer<typeof WorkerTemplateRunnerModeSchema>;
export type WorkerTemplateRunner = z.infer<typeof WorkerTemplateRunnerSchema>;
export type WorkerTemplateRunnerPreview = z.infer<typeof WorkerTemplateRunnerPreviewSchema>;
export type WorkerTemplateRunnerResult = z.infer<typeof WorkerTemplateRunnerResultSchema>;
export type TemplateRunnerEvidence = z.infer<typeof TemplateRunnerEvidenceSchema>;

const MatlabSweepPathsSchema = z.object({
  output_dir: z.string().min(1),
  manifest_path: z.string().min(1),
  summary_path: z.string().min(1),
  metrics_path: z.string().min(1),
});
const MatlabSweepSafetySchema = z.object({
  raw_stdout_included: z.literal(false),
  raw_stderr_included: z.literal(false),
  raw_mat_files_uploaded: z.literal(false),
  codex_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  worker_loop_started: z.literal(false),
  token_printed: z.literal(false),
});
const MatlabSweepCommonSchema = MatlabSweepPathsSchema.merge(MatlabSweepSafetySchema).extend({
  task_id: z.string().min(1),
  worker_id: z.string().min(1),
  template_id: z.literal("matlab-parameter-sweep.v1"),
  runner_id: z.literal("matlab-parameter-sweep-runner.v1"),
  parameter_grid_summary: z.string().min(1),
  combination_count: z.number().int().min(0).max(16),
  completed_count: z.number().int().min(0),
  failed_count: z.number().int().min(0),
  validation_status: z.string().min(1),
  matlab_invoked: z.boolean(),
  matlab_exit_code: z.number().int().nullable(),
});
export const MatlabParameterSweepRunnerSchema = MatlabSweepCommonSchema.extend({
  schema: z.literal("skybridge.matlab_parameter_sweep_runner.v1"),
  ok: z.boolean(),
  mode: z.enum(["status", "preview", "apply", "fixture", "validate-output", "safe-summary"]),
  matlab_available: z.boolean().optional(),
  would_invoke_matlab: z.boolean().optional(),
  blockers: z.array(z.string()).default([]),
  warnings: z.array(z.string()).default([]),
});
export const MatlabSweepManifestSchema = MatlabSweepPathsSchema.merge(MatlabSweepSafetySchema).extend({
  schema: z.literal("skybridge.matlab_sweep_manifest.v1"),
  task_id: z.string().min(1),
  worker_id: z.string().min(1),
  template_id: z.literal("matlab-parameter-sweep.v1"),
  runner_id: z.literal("matlab-parameter-sweep-runner.v1"),
  parameter_grid_summary: z.string().min(1),
  combination_count: z.number().int().min(0).max(16),
  generated_at: z.string().min(1),
});
export const MatlabSweepSummarySchema = MatlabSweepSafetySchema.extend({
  schema: z.literal("skybridge.matlab_sweep_summary.v1"),
  task_id: z.string().min(1),
  worker_id: z.string().min(1),
  combination_count: z.number().int().min(0).max(16),
  completed_count: z.number().int().min(0),
  failed_count: z.number().int().min(0),
  min_score: z.number().nullable(),
  max_score: z.number().nullable(),
  mean_score: z.number().nullable(),
  validation_status: z.string().min(1),
});
export const MatlabSweepEvidenceSchema = MatlabSweepCommonSchema.extend({
  schema: z.literal("skybridge.matlab_sweep_evidence.v1"),
  ok: z.boolean(),
  expected_combination_count: z.number().int().min(0).max(16).optional(),
  manifest_exists: z.boolean().optional(),
  summary_exists: z.boolean().optional(),
  metrics_exists: z.boolean().optional(),
  started_at: z.string().nullable().optional(),
  completed_at: z.string().nullable().optional(),
  failed_at: z.string().nullable().optional(),
  allowed_paths_checked: z.literal(true),
  blocked_paths_checked: z.literal(true),
  changed_files: z.array(z.string()),
  existing_outputs: z.array(z.string()).default([]),
  expected_outputs_missing: z.array(z.string()).default([]),
  failure_category: z.string().default(""),
  result_summary: z.string().min(1),
  pr_created: z.literal(false),
  project_control_unpaused: z.literal(false),
});
export const MatlabDoctorSchema = z.object({
  schema: z.literal("skybridge.matlab_doctor.v1"),
  ok: z.boolean(),
  mode: z.enum(["status", "preview", "fixture", "apply", "safe-summary"]),
  matlab_detected: z.boolean(),
  matlab_executable: z.string(),
  matlab_executable_source: z.string().optional(),
  matlab_config_path: z.string().optional(),
  matlab_version_summary: z.string(),
  batch_supported: z.boolean(),
  fallback_supported: z.boolean(),
  run_mode: z.string().optional(),
  startup_ok: z.boolean(),
  license_ok: z.boolean(),
  license_status: z.string().min(1),
  fixed_script_visible: z.boolean(),
  output_dir: z.string().min(1),
  doctor_summary_path: z.string().min(1),
  doctor_metrics_path: z.string().min(1),
  output_write_ok: z.boolean(),
  minimal_compute_ok: z.boolean(),
  matlab_invoked: z.boolean(),
  matlab_exit_code: z.number().int().nullable().optional(),
  existing_outputs: z.array(z.string()).default([]),
  failure_category: z.string(),
  failure_summary: z.string(),
  recommended_next_action: z.string().min(1),
  blockers: z.array(z.string()).default([]),
  warnings: z.array(z.string()).default([]),
  claim_created: z.literal(false),
  execution_started: z.literal(false),
  codex_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  worker_loop_started: z.literal(false),
  project_control_unpaused: z.literal(false),
  raw_stdout_included: z.literal(false),
  raw_stderr_included: z.literal(false),
  token_printed: z.literal(false),
});
export type MatlabParameterSweepRunner = z.infer<typeof MatlabParameterSweepRunnerSchema>;
export type MatlabSweepManifest = z.infer<typeof MatlabSweepManifestSchema>;
export type MatlabSweepSummary = z.infer<typeof MatlabSweepSummarySchema>;
export type MatlabSweepEvidence = z.infer<typeof MatlabSweepEvidenceSchema>;
export type MatlabDoctor = z.infer<typeof MatlabDoctorSchema>;

const CodexAnalysisReportPathsSchema = z.object({
  input_manifest_path: z.string().min(1),
  input_summary_path: z.string().min(1),
  input_metrics_path: z.string().min(1),
  output_report_path: z.string().min(1),
});
const CodexAnalysisReportSafetySchema = z.object({
  raw_codex_log_included: z.literal(false),
  raw_prompt_included: z.literal(false),
  raw_stdout_included: z.literal(false),
  raw_stderr_included: z.literal(false),
  matlab_run_called: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  worker_loop_started: z.literal(false),
  pr_created: z.literal(false),
  token_printed: z.literal(false),
});
const CodexAnalysisReportCommonSchema = CodexAnalysisReportPathsSchema.merge(
  CodexAnalysisReportSafetySchema,
).extend({
  task_id: z.string().min(1),
  worker_id: z.string().min(1),
  template_id: z.literal("codex-analysis-report.v1"),
  runner_id: z.literal("codex-analysis-report-runner.v1"),
  input_manifest_exists: z.boolean().optional(),
  input_summary_exists: z.boolean().optional(),
  input_metrics_exists: z.boolean().optional(),
  report_exists: z.boolean(),
  report_size_bytes: z.number().int().min(0).optional(),
  fallback_report_used: z.boolean().optional(),
  native_report_attempted: z.boolean().optional(),
  native_report_valid: z.boolean().optional(),
  native_report_validation_failure_category: z.string().optional(),
  native_report_validation_failure_summary: z.string().optional(),
  native_report_validation_checks: z.array(z.string()).default([]),
  final_report_source: z
    .enum(["codex_native", "deterministic_fallback", "none"])
    .optional(),
  validation_status: z.string().min(1),
  codex_invoked: z.boolean(),
  codex_exit_code: z.number().int().nullable(),
  codex_failure_category: z.string().optional(),
});
export const CodexAnalysisReportRunnerSchema =
  CodexAnalysisReportCommonSchema.extend({
    schema: z.literal("skybridge.codex_analysis_report_runner.v1"),
    ok: z.boolean(),
    mode: z.enum([
      "status",
      "preview",
      "apply",
      "fixture",
      "validate-output",
      "safe-summary",
    ]),
    codex_available: z.boolean().optional(),
    would_invoke_codex: z.boolean().optional(),
    blockers: z.array(z.string()).default([]),
    warnings: z.array(z.string()).default([]),
  });
export const CodexAnalysisReportSummarySchema =
  CodexAnalysisReportSafetySchema.extend({
    schema: z.literal("skybridge.codex_analysis_report_summary.v1"),
    task_id: z.string().min(1),
    worker_id: z.string().min(1),
    template_id: z.literal("codex-analysis-report.v1"),
    runner_id: z.literal("codex-analysis-report-runner.v1"),
    input_count: z.number().int().min(0),
    output_report_path: z.string().min(1),
    report_exists: z.boolean(),
    synthetic_runner_validation_stated: z.boolean(),
    validation_status: z.string().min(1),
  });
export const CodexAnalysisReportEvidenceSchema =
  CodexAnalysisReportCommonSchema.extend({
    schema: z.literal("skybridge.codex_analysis_report_evidence.v1"),
    ok: z.boolean(),
    allowed_paths_checked: z.literal(true),
    blocked_paths_checked: z.literal(true),
    changed_files: z.array(z.string()),
    existing_outputs: z.array(z.string()).default([]),
    expected_outputs_missing: z.array(z.string()).default([]),
    report_validation_errors: z.array(z.string()).default([]),
    result_summary: z.string().min(1),
    project_control_unpaused: z.literal(false),
  });
export type CodexAnalysisReportRunner = z.infer<
  typeof CodexAnalysisReportRunnerSchema
>;
export type CodexAnalysisReportSummary = z.infer<
  typeof CodexAnalysisReportSummarySchema
>;
export type CodexAnalysisReportEvidence = z.infer<
  typeof CodexAnalysisReportEvidenceSchema
>;

export const TaskTemplateDraftTypeSchema = z.enum(["task", "campaign"]);
export const TaskTemplateRiskClassSchema = z.enum(["low", "medium", "high"]);
export const TaskTemplateValidationSchema = z.object({
  schema: z.literal("skybridge.task_template_validation.v1"),
  validation_id: z.string().min(1),
  summary: z.string().min(1),
  required: z.boolean().default(true),
});
export const TaskTemplateEvidenceSchema = z.object({
  schema: z.literal("skybridge.task_template_evidence_schema.v1"),
  evidence_schema_id: z.string().min(1),
  summary: z.string().min(1),
  required_fields: z.array(z.string().min(1)).min(1),
});
export const TaskTemplateSchema = z.object({
  schema: z.literal("skybridge.task_template.v1"),
  template_id: z.string().min(1),
  version: z.string().min(1),
  title: z.string().min(1),
  description: z.string().min(1),
  category: z.string().min(1),
  draft_type: TaskTemplateDraftTypeSchema,
  risk_class: TaskTemplateRiskClassSchema,
  required_capabilities: z.array(z.string().min(1)).min(1),
  optional_capabilities: z.array(z.string().min(1)).default([]),
  input_schema_summary: z.array(z.string().min(1)).min(1),
  allowed_paths: z.array(z.string().min(1)).min(1),
  blocked_paths: z.array(z.string().min(1)).min(1),
  validation_rules: z.array(TaskTemplateValidationSchema).min(1),
  runner_id: z.string().min(1),
  evidence_schema: z.array(z.string().min(1)).min(1),
  output_paths: z.array(z.string().min(1)).default([]),
  default_project_id_hint: z.string().min(1).optional(),
  execution_supported: z.literal(false),
  draft_only: z.literal(true),
  task_creation_supported: z.literal(false),
  campaign_creation_supported: z.literal(false),
  claim_supported: z.literal(false),
  codex_run_supported: z.literal(false),
  matlab_run_supported: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  token_printed: z.literal(false),
});
export const TaskTemplateRegistrySchema = z.object({
  schema: z.literal("skybridge.task_template_registry.v1"),
  registry_id: z.string().min(1),
  version: z.string().min(1),
  title: z.string().min(1),
  description: z.string().min(1),
  templates: z.array(TaskTemplateSchema).min(1),
  evidence_schemas: z.array(TaskTemplateEvidenceSchema).min(1),
  execution_supported: z.literal(false),
  draft_only: z.literal(true),
  task_creation_supported: z.literal(false),
  campaign_creation_supported: z.literal(false),
  claim_supported: z.literal(false),
  codex_run_supported: z.literal(false),
  matlab_run_supported: z.literal(false),
  arbitrary_shell_enabled: z.literal(false),
  raw_prompt_persisted: z.literal(false),
  raw_response_persisted: z.literal(false),
  token_printed: z.literal(false),
});
export type TaskTemplateDraftType = z.infer<typeof TaskTemplateDraftTypeSchema>;
export type TaskTemplateRiskClass = z.infer<typeof TaskTemplateRiskClassSchema>;
export type TaskTemplateValidation = z.infer<typeof TaskTemplateValidationSchema>;
export type TaskTemplateEvidenceSchemaDefinition = z.infer<typeof TaskTemplateEvidenceSchema>;
export type TaskTemplate = z.infer<typeof TaskTemplateSchema>;
export type TaskTemplateRegistry = z.infer<typeof TaskTemplateRegistrySchema>;
export const TASK_TEMPLATE_REGISTRY = TaskTemplateRegistrySchema.parse(taskTemplateRegistryData);
export const TASK_TEMPLATE_IDS = TASK_TEMPLATE_REGISTRY.templates.map(
  (template) => template.template_id,
);
export function listTaskTemplates(): TaskTemplate[] {
  return TASK_TEMPLATE_REGISTRY.templates;
}
export function getTaskTemplate(templateId: string): TaskTemplate | undefined {
  return TASK_TEMPLATE_REGISTRY.templates.find(
    (template) => template.template_id === templateId,
  );
}
export function assertKnownTaskTemplate(templateId: string): TaskTemplate {
  const template = getTaskTemplate(templateId);
  if (!template) {
    throw new Error(`Unknown task template: ${templateId}`);
  }
  return template;
}
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
export type PlanningProposalStatus =
  | "proposed"
  | "reviewed"
  | "approved"
  | "rejected"
  | "deferred"
  | "superseded"
  | "blocked_dependency"
  | "converted"
  | "executed";
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
  template_id?: string;
  runner_id?: string;
  evidence_schema?: string[];
  allowed_paths: string[];
  blocked_paths: string[];
  validation: string[];
  stop_criteria_status: string[];
  source_run_id?: string;
  source_proposal_id?: string;
  source_campaign_id?: string;
  source_campaign_step_id?: string;
  source_goal_id?: string;
  proposal_review_status?: string;
  proposal_policy_decision?: string;
  proposal_approved_by?: string;
  proposal_approved_at?: string;
  expected_files?: string[];
  expected_outputs?: string[];
  markdown_path?: string;
  markdown_hash?: string;
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

export interface PlanningMasterGoal {
  master_goal_id: string;
  project_id: string;
  title: string;
  description?: string;
  source: string;
  priority: GoalPriority;
  constraints: string[];
  acceptance_criteria: string[];
  stop_conditions: string[];
  created_at: string;
  updated_at: string;
}

export interface PlannerAdapterAuditMetadata {
  provider: string;
  model?: string;
  runtime_mode?: string;
  planner_mode: string;
  tool_execution_mode?: string;
  prompt_version: string;
  input_state_hash: string;
  session_id?: string;
  raw_response_included: false;
  secrets_included: false;
}

export interface PlanningSession {
  planning_session_id: string;
  master_goal_id: string;
  project_id: string;
  planner_adapter: PlannerAdapterAuditMetadata;
  created_at: string;
  updated_at: string;
}

export interface TaskProposal {
  proposal_id: string;
  master_goal_id: string;
  planning_session_id?: string;
  project_id: string;
  title: string;
  body?: string;
  prompt_summary?: string;
  dedupe_key: string;
  expected_files: string[];
  acceptance_criteria: string[];
  evidence_requirements: string[];
  required_capabilities: WorkerCapability[];
  original_required_capabilities?: WorkerCapability[];
  normalized_required_capabilities?: WorkerCapability[];
  capability_normalization_reason?: string;
  risk: TaskRisk;
  task_type: string;
  depends_on: string[];
  dependencies?: string[];
  rationale: string;
  stop_condition?: string;
  status: PlanningProposalStatus;
  policy_decision?: string;
  review_status?: string;
  review_reason?: string;
  reviewed_by?: string;
  reviewed_at?: string;
  approved_by?: string;
  approved_at?: string;
  superseded_by?: string;
  created_by: string;
  converted_task_id?: string;
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
  auth_mode?: "none" | "bearer_token";
  api_base_redacted?: string;
  allow_remote_server?: boolean;
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

export type TaskLeaseStatus = "active" | "released" | "expired" | "abandoned";

export interface TaskLease {
  lease_id: string;
  task_id: string;
  worker_id: string;
  project_id: string;
  claimed_at: string;
  lease_expires_at: string;
  heartbeat_at: string;
  lease_status: TaskLeaseStatus;
  current_attempt: number;
  max_attempts: number;
  stale_reason?: string;
  released_at?: string;
}

export interface TaskResult {
  summary?: string;
  result_url?: string;
  pr_url?: string;
  error_summary?: string;
  evidence_summary?: EvidenceSummary;
}

export interface EvidenceSummary {
  schema?: string;
  task_id?: string;
  goal_id?: string;
  worker_id?: string;
  template_id?: string;
  runner_id?: string;
  pr_url?: string;
  commit_sha?: string;
  changed_files?: string[];
  existing_outputs?: string[];
  expected_outputs_missing?: string[];
  report_validation_errors?: string[];
  validation_status?: string;
  ci_status?: string;
  risk_status?: string;
  recovered?: boolean;
  recovery_status?: string;
  input_manifest_path?: string;
  input_summary_path?: string;
  input_metrics_path?: string;
  input_manifest_exists?: boolean;
  input_summary_exists?: boolean;
  input_metrics_exists?: boolean;
  output_report_path?: string;
  report_exists?: boolean;
  report_size_bytes?: number;
  fallback_report_used?: boolean;
  native_report_attempted?: boolean;
  native_report_valid?: boolean;
  native_report_validation_failure_category?: string;
  native_report_validation_failure_summary?: string;
  native_report_validation_checks?: string[];
  final_report_source?: "codex_native" | "deterministic_fallback" | "none";
  codex_invoked?: boolean;
  codex_exit_code?: number;
  codex_failure_category?: string;
  raw_codex_log_included?: boolean;
  raw_prompt_included?: boolean;
  raw_stdout_included?: boolean;
  raw_stderr_included?: boolean;
  matlab_run_called?: boolean;
  arbitrary_shell_enabled?: boolean;
  worker_loop_started?: boolean;
  project_control_unpaused?: boolean;
  pr_created?: boolean;
  token_printed?: boolean;
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
  source_proposal_id?: string;
  proposal_review_status?: string;
  proposal_approved_by?: string;
  proposal_approved_at?: string;
  proposal_policy_decision?: string;
  planner_metadata?: PlannerAdapterMetadata;
  allowed_paths?: string[];
  blocked_paths?: string[];
  validation?: string[];
  required_capabilities: WorkerCapability[];
  assigned_worker_id?: string;
  claim?: TaskClaim;
  lease?: TaskLease;
  result?: TaskResult;
  hygiene_metadata?: Record<string, unknown>;
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

export type CampaignStatus = "draft" | "ready" | "running" | "paused" | "held" | "completed" | "failed" | "aborted";
export type CampaignStepStatus = "pending" | "ready" | "running" | "completed" | "recovered" | "failed" | "skipped" | "held" | "needs_human" | "blocked_dependency";

export interface CampaignAdvanceGate {
  requires_clean_worktree?: boolean;
  requires_no_active_tasks?: boolean;
  requires_no_stale_leases?: boolean;
  requires_parent_pr_merged?: boolean;
  requires_human_approval?: boolean;
  allow_project_control_running?: boolean;
  human_approved?: boolean;
}

export type CampaignGateDecision =
  | "advance"
  | "hold"
  | "retry"
  | "ask_human"
  | "abort";

export interface CampaignGateEvidenceReviewed {
  active_tasks: number;
  stale_leases: number;
  failed_unrecovered: number;
  blocked_tasks: number;
  approved_unconverted_proposals: number;
  current_step_status: CampaignStepStatus | string;
  linked_prs: string[];
  linked_tasks: string[];
  validation_summary?: Record<string, unknown>;
  hygiene_summary?: Record<string, unknown>;
}

export interface CampaignGateSafetyAssessment {
  safe_to_advance: boolean;
  safe_to_execute_next_step: boolean;
  requires_human_approval: boolean;
  deterministic_veto_expected: boolean;
}

export interface CampaignGateResult {
  schema: "skybridge.campaign_gate.v1";
  decision: CampaignGateDecision;
  confidence: number;
  campaign_id: string;
  current_step_id: string;
  current_goal_id: string;
  next_step_id?: string;
  next_goal_id?: string;
  reasons: string[];
  blockers: string[];
  warnings: string[];
  required_human_actions: string[];
  evidence_reviewed: CampaignGateEvidenceReviewed;
  safety_assessment: CampaignGateSafetyAssessment;
  recommended_next_action: string;
  raw_notes?: string;
  input_state_hash?: string;
  prompt_version?: string;
  generated_at?: string;
}

export interface Campaign {
  campaign_id: string;
  project_id: string;
  title: string;
  description?: string;
  source?: string;
  status: CampaignStatus;
  current_step_id?: string;
  created_at: string;
  updated_at: string;
  created_by?: string;
  imported_from?: string;
  goal_pack_hash?: string;
  safety_policy?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface CampaignStep {
  campaign_step_id: string;
  campaign_id: string;
  project_id: string;
  goal_id: string;
  title: string;
  order: number;
  status: CampaignStepStatus;
  dependencies: string[];
  markdown_path?: string;
  markdown_hash?: string;
  metadata?: Record<string, unknown>;
  advance_gate?: CampaignAdvanceGate;
  evidence_summary?: Record<string, unknown>;
  linked_master_goal_id?: string;
  linked_task_ids?: string[];
  linked_pr_urls?: string[];
  started_at?: string;
  completed_at?: string;
  decision_summary?: string;
  last_gate_result?: Record<string, unknown>;
  created_at: string;
  updated_at: string;
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
