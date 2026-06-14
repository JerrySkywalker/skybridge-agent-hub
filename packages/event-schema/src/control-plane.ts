import { z } from "zod";

export const TOKEN_PRINTED_FALSE = false as const;

export const WorkerCapabilitySummarySchema = z.object({
  schema: z.literal("skybridge.worker_capability_summary.v1"),
  capabilities: z.array(z.string()).default([]),
  resource_policy_summary: z.string(),
  resident_enabled: z.boolean(),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerIdentitySchema = z.object({
  schema: z.literal("skybridge.worker_identity.v1"),
  worker_id: z.string().min(1),
  device_id_hash: z.string().min(1),
  display_name: z.string().min(1),
  repo: z.string().min(1),
  branch: z.string().min(1),
  commit: z.string().min(1),
  token_printed: z.literal(false),
});

export const WorkerConnectionStateSchema = z.object({
  schema: z.literal("skybridge.worker_connection_state.v1"),
  worker_id: z.string().min(1),
  paired: z.boolean(),
  pairing_state: z.enum([
    "unpaired",
    "pairing_preview",
    "paired",
    "expired",
    "revoked",
  ]),
  resident_enabled: z.boolean(),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerRegistrationSchema = z.object({
  schema: z.literal("skybridge.worker_registration.v1"),
  worker_id: z.string().min(1),
  device_id_hash: z.string().min(1),
  display_name: z.string().min(1),
  repo: z.string().min(1),
  branch: z.string().min(1),
  commit: z.string().min(1),
  capabilities: z.array(z.string()),
  resource_policy_summary: z.string(),
  resident_enabled: z.boolean(),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  paired: z.boolean(),
  pairing_state: WorkerConnectionStateSchema.shape.pairing_state,
  pairing_code_hash: z.string().min(1),
  pairing_code_raw_persisted: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerPairingPreviewSchema = z.object({
  schema: z.literal("skybridge.worker_pairing_preview.v1"),
  worker_id: z.string().min(1),
  pairing_state: WorkerConnectionStateSchema.shape.pairing_state,
  paired: z.boolean(),
  pairing_code_hash: z.string().min(1),
  pairing_code_raw_persisted: z.literal(false),
  pairing_preview_only: z.literal(true),
  expires_at: z.string().datetime(),
  resident_enabled: z.boolean(),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  operator_approval_required: z.literal(true),
  human_review_required: z.literal(true),
  token_printed: z.literal(false),
});

export const WorkerPairingTokenHashSchema = z.object({
  schema: z.literal("skybridge.worker_pairing_token_hash.v1"),
  pairing_id: z.string().min(1),
  pairing_code_hash: z.string().min(1),
  raw_pairing_code_persisted: z.literal(false),
  raw_token_persisted: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerPairingRevocationSchema = z.object({
  schema: z.literal("skybridge.worker_pairing_revocation.v1"),
  pairing_id: z.string().min(1),
  worker_id: z.string().min(1),
  revoked_at: z.string().datetime(),
  pairing_state: z.literal("revoked"),
  execution_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerPairingExpirySchema = z.object({
  schema: z.literal("skybridge.worker_pairing_expiry.v1"),
  pairing_id: z.string().min(1),
  worker_id: z.string().min(1),
  expires_at: z.string().datetime(),
  pairing_state: z.literal("expired"),
  execution_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerPairingRecordSchema = z.object({
  schema: z.literal("skybridge.worker_pairing_record.v1"),
  pairing_id: z.string().min(1),
  worker_id: z.string().min(1),
  device_id_hash: z.string().min(1),
  repo: z.string().min(1),
  display_name: z.string().min(1),
  created_at: z.string().datetime(),
  expires_at: z.string().datetime(),
  revoked_at: z.string().datetime().nullable(),
  pairing_state: z.enum(["pending", "paired", "expired", "revoked"]),
  raw_pairing_code_persisted: z.literal(false),
  pairing_code_hash: z.string().min(1),
  pairing_code_preview_last4: z.string().length(4).optional(),
  capabilities: z.array(z.string()),
  resident_enabled: z.boolean(),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerPairingStoreSchema = z.object({
  schema: z.literal("skybridge.worker_pairing_store.v1"),
  store_path_redacted: z.string().min(1),
  records: z.array(WorkerPairingRecordSchema),
  revocations: z.array(WorkerPairingRevocationSchema),
  expiries: z.array(WorkerPairingExpirySchema),
  raw_pairing_code_persisted: z.literal(false),
  raw_token_persisted: z.literal(false),
  execution_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerPairingStoreReportSchema = z.object({
  schema: z.literal("skybridge.worker_pairing_store_report.v1"),
  pairing_count: z.number().int().nonnegative(),
  paired_count: z.number().int().nonnegative(),
  expired_count: z.number().int().nonnegative(),
  revoked_count: z.number().int().nonnegative(),
  raw_pairing_code_persisted: z.literal(false),
  raw_token_persisted: z.literal(false),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const WorkerResourceGateReportSchema = z.object({
  schema: z.literal("skybridge.worker_resource_gate_report.v1"),
  resource_gate_status: z.enum(["pass", "blocked", "unknown"]),
  resource_gate_blockers: z.array(z.string()),
  active_tasks: z.number().int().nonnegative(),
  stale_leases: z.number().int().nonnegative(),
  runner_lock: z.string(),
  open_review_hold: z.boolean(),
  token_printed: z.literal(false),
});

export const WorkerQueuePreviewReportSchema = z.object({
  schema: z.literal("skybridge.worker_queue_preview_report.v1"),
  queue_preview: z.object({
    queued_workunits: z.number().int().nonnegative(),
    runnable_workunits: z.number().int().nonnegative(),
    would_create_tasks: z.literal(false),
    would_claim_tasks: z.literal(false),
    would_execute_tasks: z.literal(false),
  }),
  token_printed: z.literal(false),
});

export const WorkerResidentStatusSchema = z.object({
  schema: z.literal("skybridge.worker_resident_status.v1"),
  worker_id: z.string().min(1),
  resident_enabled: z.boolean(),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  drain_pause_state: z.boolean(),
  emergency_stop_preview_state: z.boolean(),
  token_printed: z.literal(false),
});

export const WorkerHeartbeatSchema = z.object({
  schema: z.literal("skybridge.worker_heartbeat.v1"),
  worker_id: z.string().min(1),
  device_id_hash: z.string().min(1),
  repo: z.string().min(1),
  branch: z.string().min(1),
  commit: z.string().min(1),
  resident_enabled: z.boolean(),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  resource_gate_status: z.enum(["pass", "blocked", "unknown"]),
  resource_gate_blockers: z.array(z.string()),
  active_tasks: z.number().int().nonnegative(),
  stale_leases: z.number().int().nonnegative(),
  runner_lock: z.string(),
  open_review_hold: z.boolean(),
  queue_preview: WorkerQueuePreviewReportSchema.shape.queue_preview,
  drain_pause_state: z.boolean(),
  emergency_stop_preview_state: z.boolean(),
  timestamp: z.string().datetime(),
  token_printed: z.literal(false),
});

export const WorkerIngestRejectionSchema = z.object({
  schema: z.literal("skybridge.worker_ingest_rejection.v1"),
  ok: z.literal(false),
  error: z.literal("unsafe_worker_ingest_rejected"),
  reasons: z.array(z.string()),
  token_printed: z.literal(false),
});

export const OperatorApprovalRequestSchema = z.object({
  schema: z.literal("skybridge.operator_approval_request.v1"),
  approval_request_id: z.string().min(1),
  requested_action: z.string().min(1),
  requested_mode: z.enum(["preview", "future_controlled_execution"]),
  scope: z.string().min(1),
  run_id: z.string().optional(),
  workunit_ids: z.array(z.string()),
  max_workunits: z.number().int().nonnegative(),
  max_parallel_repo_mutations: z.literal(1),
  risk: z.enum(["low", "medium", "high"]),
  resource_gate_required: z.literal(true),
  human_review_required: z.literal(true),
  finalizer_required: z.literal(true),
  failure_budget_required: z.literal(true),
  evidence_retention_required: z.literal(true),
  audit_required: z.literal(true),
  expires_at: z.string().datetime(),
  token_printed: z.literal(false),
});

export const OperatorApprovalStateSchema = z.object({
  schema: z.literal("skybridge.operator_approval_state.v1"),
  approval_request_id: z.string().min(1),
  approval_state: z.enum([
    "pending",
    "approved",
    "rejected",
    "expired",
    "consumed",
  ]),
  decision_reason: z.string(),
  consumed: z.boolean(),
  execution_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const OperatorApprovalDecisionSchema = z.object({
  schema: z.literal("skybridge.operator_approval_decision.v1"),
  approval_request_id: z.string().min(1),
  decision: z.enum(["approved", "rejected"]),
  decision_reason: z.string(),
  decided_by: z.string(),
  decided_at: z.string().datetime(),
  execution_started: z.literal(false),
  token_printed: z.literal(false),
});

export const OperatorApprovalGateSchema = z.object({
  schema: z.literal("skybridge.operator_approval_gate.v1"),
  approval_request_id: z.string().min(1),
  allowed_to_execute: z.literal(false),
  approval_does_not_execute: z.literal(true),
  resource_gate_required: z.literal(true),
  human_review_required: z.literal(true),
  finalizer_required: z.literal(true),
  generic_bounded_queue_apply_enabled: z.literal(false),
  remote_arbitrary_command_dispatch_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const OperatorApprovalConsumptionSchema = z.object({
  schema: z.literal("skybridge.operator_approval_consumption.v1"),
  approval_id: z.string().min(1),
  consumed_at: z.string().datetime(),
  consumed_preview_only: z.literal(true),
  execution_started: z.literal(false),
  can_execute_now: z.literal(false),
  token_printed: z.literal(false),
});

export const OperatorApprovalExpirySchema = z.object({
  schema: z.literal("skybridge.operator_approval_expiry.v1"),
  approval_id: z.string().min(1),
  expires_at: z.string().datetime(),
  state: z.literal("expired"),
  can_execute_now: z.literal(false),
  token_printed: z.literal(false),
});

export const OperatorApprovalAuditRecordSchema = z.object({
  schema: z.literal("skybridge.operator_approval_audit_record.v1"),
  audit_id: z.string().min(1),
  approval_id: z.string().min(1),
  event_type: z.enum([
    "approval_requested_preview",
    "approval_approved_preview",
    "approval_rejected_preview",
    "approval_expired_preview",
    "approval_consumed_preview",
    "unsafe_payload_rejected",
    "remote_execution_rejected",
    "arbitrary_command_rejected",
  ]),
  occurred_at: z.string().datetime(),
  safe_summary: z.string().min(1),
  token_printed: z.literal(false),
});

export const OperatorApprovalRecordSchema = z.object({
  schema: z.literal("skybridge.operator_approval_record.v1"),
  approval_id: z.string().min(1),
  scope: z.string().min(1),
  requested_action: z.string().min(1),
  requested_mode: z.string().min(1),
  run_id: z.string().min(1),
  workunit_ids: z.array(z.string()),
  max_workunits: z.number().int().nonnegative(),
  max_tasks: z.number().int().nonnegative(),
  max_claims: z.number().int().nonnegative(),
  max_codex_executions: z.number().int().nonnegative(),
  max_task_prs: z.number().int().nonnegative(),
  resource_gate_required: z.literal(true),
  human_review_required: z.literal(true),
  finalizer_required: z.literal(true),
  failure_budget_required: z.literal(true),
  evidence_retention_required: z.literal(true),
  audit_required: z.literal(true),
  redaction_required: z.literal(true),
  state: z.enum(["pending", "approved_preview", "rejected", "expired", "consumed"]),
  created_at: z.string().datetime(),
  expires_at: z.string().datetime(),
  consumed_at: z.string().datetime().nullable(),
  decision_reason: z.string(),
  can_execute_now: z.literal(false),
  token_printed: z.literal(false),
});

export const OperatorApprovalStoreSchema = z.object({
  schema: z.literal("skybridge.operator_approval_store.v1"),
  store_path_redacted: z.string().min(1),
  approvals: z.array(OperatorApprovalRecordSchema),
  consumptions: z.array(OperatorApprovalConsumptionSchema),
  expiries: z.array(OperatorApprovalExpirySchema),
  audit: z.array(OperatorApprovalAuditRecordSchema),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  token_printed: z.literal(false),
});

export const ResidentPollingPolicySchema = z.object({
  schema: z.literal("skybridge.resident_polling_policy.v1"),
  polling_enabled: z.literal(false),
  polling_preview_enabled: z.literal(true),
  execution_enabled: z.literal(false),
  claim_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  poll_interval_seconds: z.number().int().min(300),
  max_iterations_preview: z.number().int().positive(),
  require_resource_gate: z.literal(true),
  require_pairing: z.literal(true),
  require_approval_for_future_execution: z.literal(true),
  no_next_execution_authorized: z.literal(true),
  token_printed: z.literal(false),
});

export const ResidentPollingBlockerSchema = z.object({
  schema: z.literal("skybridge.resident_polling_blocker.v1"),
  blocker_id: z.string().min(1),
  reason: z.string().min(1),
  token_printed: z.literal(false),
});

export const ResidentPollingIterationSchema = z.object({
  schema: z.literal("skybridge.resident_polling_iteration.v1"),
  iteration_id: z.string().min(1),
  poll_started_at: z.string().datetime(),
  server_state_checked: z.literal(true),
  pairing_state_checked: z.literal(true),
  approval_state_checked: z.literal(true),
  queue_state_checked: z.literal(true),
  task_claimed: z.literal(false),
  codex_executed: z.literal(false),
  queue_apply_performed: z.literal(false),
  token_printed: z.literal(false),
});

export const ResidentPollingStatusSchema = z.object({
  schema: z.literal("skybridge.resident_polling_status.v1"),
  status: z.enum(["preview_disabled", "preview_ready", "preview_checked"]),
  last_poll_summary: z.string(),
  next_poll_interval_seconds: z.number().int().min(300),
  blockers: z.array(ResidentPollingBlockerSchema),
  execution_enabled: z.literal(false),
  claim_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  no_next_execution_authorized: z.literal(true),
  token_printed: z.literal(false),
});

export const ResidentPollingReportSchema = z.object({
  schema: z.literal("skybridge.resident_polling_report.v1"),
  policy: ResidentPollingPolicySchema,
  status: ResidentPollingStatusSchema,
  iterations: z.array(ResidentPollingIterationSchema),
  task_claimed: z.literal(false),
  codex_executed: z.literal(false),
  queue_apply_performed: z.literal(false),
  ready_for_goal_225: z.boolean(),
  token_printed: z.literal(false),
});

export type WorkerCapabilitySummary = z.infer<typeof WorkerCapabilitySummarySchema>;
export type WorkerIdentity = z.infer<typeof WorkerIdentitySchema>;
export type WorkerConnectionState = z.infer<typeof WorkerConnectionStateSchema>;
export type WorkerRegistration = z.infer<typeof WorkerRegistrationSchema>;
export type WorkerPairingPreview = z.infer<typeof WorkerPairingPreviewSchema>;
export type WorkerPairingRecord = z.infer<typeof WorkerPairingRecordSchema>;
export type WorkerPairingStore = z.infer<typeof WorkerPairingStoreSchema>;
export type WorkerPairingStoreReport = z.infer<typeof WorkerPairingStoreReportSchema>;
export type WorkerResourceGateReport = z.infer<typeof WorkerResourceGateReportSchema>;
export type WorkerQueuePreviewReport = z.infer<typeof WorkerQueuePreviewReportSchema>;
export type WorkerResidentStatus = z.infer<typeof WorkerResidentStatusSchema>;
export type ControlPlaneWorkerHeartbeat = z.infer<typeof WorkerHeartbeatSchema>;
export type WorkerIngestRejection = z.infer<typeof WorkerIngestRejectionSchema>;
export type OperatorApprovalRequest = z.infer<typeof OperatorApprovalRequestSchema>;
export type OperatorApprovalState = z.infer<typeof OperatorApprovalStateSchema>;
export type OperatorApprovalDecision = z.infer<typeof OperatorApprovalDecisionSchema>;
export type OperatorApprovalGate = z.infer<typeof OperatorApprovalGateSchema>;
export type OperatorApprovalRecord = z.infer<typeof OperatorApprovalRecordSchema>;
export type OperatorApprovalStore = z.infer<typeof OperatorApprovalStoreSchema>;
export type ResidentPollingPolicy = z.infer<typeof ResidentPollingPolicySchema>;
export type ResidentPollingStatus = z.infer<typeof ResidentPollingStatusSchema>;
export type ResidentPollingReport = z.infer<typeof ResidentPollingReportSchema>;

export const fixtureWorkerRegistration: WorkerRegistration = {
  schema: "skybridge.worker_registration.v1",
  worker_id: "laptop-zenbookduo",
  device_id_hash: "local-fixture-device",
  display_name: "Zenbook Duo local resident preview",
  repo: "skybridge-agent-hub",
  branch: "main",
  commit: "fixture-goal-218",
  capabilities: ["heartbeat", "resource-state", "queue-preview"],
  resource_policy_summary: "local resource gate passes; execution disabled",
  resident_enabled: false,
  execution_enabled: false,
  queue_apply_enabled: false,
  paired: false,
  pairing_state: "pairing_preview",
  pairing_code_hash: "fixture-pairing-code-hash-only",
  pairing_code_raw_persisted: false,
  remote_execution_enabled: false,
  arbitrary_command_enabled: false,
  token_printed: false,
};

export const fixtureWorkerPairingPreview: WorkerPairingPreview = {
  schema: "skybridge.worker_pairing_preview.v1",
  worker_id: fixtureWorkerRegistration.worker_id,
  pairing_state: "pairing_preview",
  paired: false,
  pairing_code_hash: fixtureWorkerRegistration.pairing_code_hash,
  pairing_code_raw_persisted: false,
  pairing_preview_only: true,
  expires_at: "2026-06-13T00:30:00.000Z",
  resident_enabled: false,
  execution_enabled: false,
  queue_apply_enabled: false,
  remote_execution_enabled: false,
  arbitrary_command_enabled: false,
  operator_approval_required: true,
  human_review_required: true,
  token_printed: false,
};

export const fixtureWorkerPairingRecord: WorkerPairingRecord = {
  schema: "skybridge.worker_pairing_record.v1",
  pairing_id: "pairing-goal-223-preview",
  worker_id: fixtureWorkerRegistration.worker_id,
  device_id_hash: fixtureWorkerRegistration.device_id_hash,
  repo: fixtureWorkerRegistration.repo,
  display_name: fixtureWorkerRegistration.display_name,
  created_at: "2026-06-14T00:00:00.000Z",
  expires_at: "2026-06-14T01:00:00.000Z",
  revoked_at: null,
  pairing_state: "pending",
  raw_pairing_code_persisted: false,
  pairing_code_hash: "sha256-fixture-pairing-code-hash-only",
  pairing_code_preview_last4: "1234",
  capabilities: ["heartbeat", "resident-polling-preview"],
  resident_enabled: false,
  execution_enabled: false,
  queue_apply_enabled: false,
  remote_execution_enabled: false,
  arbitrary_command_enabled: false,
  token_printed: false,
};

export const fixtureWorkerHeartbeat: ControlPlaneWorkerHeartbeat = {
  schema: "skybridge.worker_heartbeat.v1",
  worker_id: fixtureWorkerRegistration.worker_id,
  device_id_hash: fixtureWorkerRegistration.device_id_hash,
  repo: fixtureWorkerRegistration.repo,
  branch: "main",
  commit: "fixture-goal-218",
  resident_enabled: false,
  execution_enabled: false,
  queue_apply_enabled: false,
  resource_gate_status: "pass",
  resource_gate_blockers: [],
  active_tasks: 0,
  stale_leases: 0,
  runner_lock: "none",
  open_review_hold: false,
  queue_preview: {
    queued_workunits: 0,
    runnable_workunits: 0,
    would_create_tasks: false,
    would_claim_tasks: false,
    would_execute_tasks: false,
  },
  drain_pause_state: false,
  emergency_stop_preview_state: false,
  timestamp: "2026-06-13T00:00:00.000Z",
  token_printed: false,
};

export const fixtureOperatorApprovalRequest: OperatorApprovalRequest = {
  schema: "skybridge.operator_approval_request.v1",
  approval_request_id: "approval-goal-218-preview",
  requested_action: "future_start_one_controlled_preview",
  requested_mode: "preview",
  scope: "skybridge-agent-hub/local-fixture",
  run_id: "goal-218-preview",
  workunit_ids: [],
  max_workunits: 0,
  max_parallel_repo_mutations: 1,
  risk: "medium",
  resource_gate_required: true,
  human_review_required: true,
  finalizer_required: true,
  failure_budget_required: true,
  evidence_retention_required: true,
  audit_required: true,
  expires_at: "2026-06-13T01:00:00.000Z",
  token_printed: false,
};

export const fixtureOperatorApprovalState: OperatorApprovalState = {
  schema: "skybridge.operator_approval_state.v1",
  approval_request_id: fixtureOperatorApprovalRequest.approval_request_id,
  approval_state: "pending",
  decision_reason: "preview-only approval object; no execution side effects",
  consumed: false,
  execution_enabled: false,
  remote_execution_enabled: false,
  arbitrary_command_enabled: false,
  token_printed: false,
};

export const fixtureOperatorApprovalGate: OperatorApprovalGate = {
  schema: "skybridge.operator_approval_gate.v1",
  approval_request_id: fixtureOperatorApprovalRequest.approval_request_id,
  allowed_to_execute: false,
  approval_does_not_execute: true,
  resource_gate_required: true,
  human_review_required: true,
  finalizer_required: true,
  generic_bounded_queue_apply_enabled: false,
  remote_arbitrary_command_dispatch_enabled: false,
  token_printed: false,
};

export const fixtureOperatorApprovalRecord: OperatorApprovalRecord = {
  schema: "skybridge.operator_approval_record.v1",
  approval_id: "approval-goal-223-preview",
  scope: "skybridge-agent-hub/local-preview",
  requested_action: "resident_polling_preview",
  requested_mode: "preview",
  run_id: "goal-223-224-preview",
  workunit_ids: [],
  max_workunits: 0,
  max_tasks: 0,
  max_claims: 0,
  max_codex_executions: 0,
  max_task_prs: 0,
  resource_gate_required: true,
  human_review_required: true,
  finalizer_required: true,
  failure_budget_required: true,
  evidence_retention_required: true,
  audit_required: true,
  redaction_required: true,
  state: "pending",
  created_at: "2026-06-14T00:00:00.000Z",
  expires_at: "2026-06-14T01:00:00.000Z",
  consumed_at: null,
  decision_reason: "preview-only approval state; no execution side effects",
  can_execute_now: false,
  token_printed: false,
};

export const fixtureResidentPollingReport: ResidentPollingReport = {
  schema: "skybridge.resident_polling_report.v1",
  policy: {
    schema: "skybridge.resident_polling_policy.v1",
    polling_enabled: false,
    polling_preview_enabled: true,
    execution_enabled: false,
    claim_enabled: false,
    queue_apply_enabled: false,
    remote_execution_enabled: false,
    arbitrary_command_enabled: false,
    poll_interval_seconds: 300,
    max_iterations_preview: 3,
    require_resource_gate: true,
    require_pairing: true,
    require_approval_for_future_execution: true,
    no_next_execution_authorized: true,
    token_printed: false,
  },
  status: {
    schema: "skybridge.resident_polling_status.v1",
    status: "preview_ready",
    last_poll_summary: "preview fixture has not executed work",
    next_poll_interval_seconds: 300,
    blockers: [],
    execution_enabled: false,
    claim_enabled: false,
    queue_apply_enabled: false,
    no_next_execution_authorized: true,
    token_printed: false,
  },
  iterations: [],
  task_claimed: false,
  codex_executed: false,
  queue_apply_performed: false,
  ready_for_goal_225: false,
  token_printed: false,
};

export function parseWorkerRegistration(input: unknown): WorkerRegistration {
  return WorkerRegistrationSchema.parse(input);
}

export function parseWorkerHeartbeat(input: unknown): ControlPlaneWorkerHeartbeat {
  return WorkerHeartbeatSchema.parse(input);
}

export function parseOperatorApprovalRequest(input: unknown): OperatorApprovalRequest {
  return OperatorApprovalRequestSchema.parse(input);
}
