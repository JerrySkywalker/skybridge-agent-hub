import { z } from "zod";

export const FailureClassSchema = z.enum([
  "no_failure",
  "timeout_no_mutation",
  "timeout_with_changes",
  "nonzero_no_mutation",
  "nonzero_with_changes",
  "no_change_result",
  "dirty_worktree",
  "disallowed_path_change",
  "pr_created_hold",
  "raw_artifact_detected",
  "secret_detected",
  "resource_gate_blocked",
  "repeated_blocker",
  "unknown_unsafe",
  "token_printed_true",
]);

export const FailureBudgetSchema = z.object({
  schema: z.literal("skybridge.failure_budget.v1"),
  timeout_budget: z.number().int().nonnegative(),
  nonzero_exit_budget: z.number().int().nonnegative(),
  no_change_budget: z.number().int().nonnegative(),
  dirty_worktree_budget: z.number().int().nonnegative(),
  resource_gate_block_budget: z.number().int().nonnegative(),
  repeated_blocker_suppression: z.boolean(),
  retry_requires_explicit_authorization: z.literal(true),
  replacement_requires_no_mutation_classification: z.literal(true),
  max_retries_per_workunit: z.number().int().nonnegative(),
  max_replacements_per_workunit: z.number().int().nonnegative(),
  no_silent_rerun: z.literal(true),
  no_retry_after_pr_created: z.literal(true),
  no_retry_after_raw_artifact: z.literal(true),
  no_retry_after_disallowed_change: z.literal(true),
  no_retry_after_secret_detected: z.literal(true),
  token_printed: z.literal(false),
});

export const FailureClassificationSchema = z.object({
  schema: z.literal("skybridge.failure_classification.v1"),
  run_id: z.string().min(1),
  workunit_id: z.string().min(1),
  failure_class: FailureClassSchema,
  changed_files: z.array(z.string()),
  pr_created: z.boolean(),
  raw_artifact_detected: z.boolean(),
  secret_detected: z.boolean(),
  token_printed: z.literal(false),
});

export const RetryAuthorizationGateSchema = z.object({
  schema: z.literal("skybridge.retry_authorization_gate.v1"),
  workunit_id: z.string().min(1),
  retry_allowed: z.literal(false),
  automatic_retry_allowed: z.literal(false),
  explicit_operator_authorization_required: z.literal(true),
  no_silent_rerun: z.literal(true),
  no_retry_after_pr_created: z.literal(true),
  token_printed: z.literal(false),
});

export const ReplacementAuthorizationGateSchema = z.object({
  schema: z.literal("skybridge.replacement_authorization_gate.v1"),
  workunit_id: z.string().min(1),
  replacement_allowed: z.boolean(),
  automatic_replacement_allowed: z.literal(false),
  requires_no_mutation_classification: z.literal(true),
  explicit_operator_authorization_required: z.literal(true),
  token_printed: z.literal(false),
});

export const FailureBudgetBlockerSchema = z.object({
  schema: z.literal("skybridge.failure_budget_blocker.v1"),
  blocker_id: z.string().min(1),
  failure_class: FailureClassSchema,
  reason: z.string().min(1),
  retry_blocked: z.boolean(),
  replacement_blocked: z.boolean(),
  token_printed: z.literal(false),
});

export const FailureBudgetReportSchema = z.object({
  schema: z.literal("skybridge.failure_budget_report.v1"),
  policy: FailureBudgetSchema,
  classifications: z.array(FailureClassificationSchema),
  retry_gate: RetryAuthorizationGateSchema,
  replacement_gate: ReplacementAuthorizationGateSchema,
  blockers: z.array(FailureBudgetBlockerSchema),
  ready_for_controlled_release: z.boolean(),
  token_printed: z.literal(false),
});

export const EvidenceIndexEntrySchema = z.object({
  schema: z.literal("skybridge.evidence_index_entry.v1"),
  evidence_id: z.string().min(1),
  run_id: z.string().min(1),
  workunit_id: z.string().min(1),
  alpha_id: z.string().min(1),
  evidence_type: z.string().min(1),
  source_path: z.string().min(1),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  previous_hash: z.string(),
  chain_index: z.number().int().nonnegative(),
  created_at: z.string().datetime(),
  retention_class: z.enum(["release_audit", "goal_report", "campaign_report", "desktop_report", "control_plane_report"]),
  safe_to_export: z.boolean(),
  raw_artifact: z.literal(false),
  secret_detected: z.literal(false),
  token_printed: z.literal(false),
});

export const EvidenceHashChainSchema = z.object({
  schema: z.literal("skybridge.evidence_hash_chain.v1"),
  chain_id: z.string().min(1),
  entries: z.array(EvidenceIndexEntrySchema),
  head_hash: z.string().regex(/^[a-f0-9]{64}$/),
  verified: z.boolean(),
  token_printed: z.literal(false),
});

export const EvidenceRetentionSchema = z.object({
  schema: z.literal("skybridge.evidence_retention.v1"),
  policy_id: z.string().min(1),
  indexed_paths: z.array(z.string()),
  excluded_raw_patterns: z.array(z.string()),
  safe_to_export: z.boolean(),
  raw_artifact: z.literal(false),
  secret_detected: z.literal(false),
  token_printed: z.literal(false),
});

export const EvidenceExportSummarySchema = z.object({
  schema: z.literal("skybridge.evidence_export_summary.v1"),
  entry_count: z.number().int().nonnegative(),
  safe_to_export_count: z.number().int().nonnegative(),
  raw_artifact_count: z.literal(0),
  secret_detected_count: z.literal(0),
  token_printed: z.literal(false),
});

export const EvidenceRetentionViolationSchema = z.object({
  schema: z.literal("skybridge.evidence_retention_violation.v1"),
  violation_id: z.string().min(1),
  source_path: z.string().min(1),
  violation_type: z.enum(["missing_expected_evidence", "hash_mismatch", "raw_artifact_detected", "secret_detected"]),
  blocks_export: z.boolean(),
  token_printed: z.literal(false),
});

export const EvidenceRetentionReportSchema = z.object({
  schema: z.literal("skybridge.evidence_retention_report.v1"),
  retention: EvidenceRetentionSchema,
  entries: z.array(EvidenceIndexEntrySchema),
  hash_chain: EvidenceHashChainSchema,
  export_summary: EvidenceExportSummarySchema,
  violations: z.array(EvidenceRetentionViolationSchema),
  token_printed: z.literal(false),
});

export const AuditEventTypeSchema = z.enum([
  "resource_gate_passed",
  "resource_gate_blocked",
  "approval_requested",
  "approval_approved_preview",
  "approval_rejected_preview",
  "approval_expired_preview",
  "workunit_started",
  "task_pr_created",
  "human_review_required",
  "task_pr_merged",
  "finalizer_completed",
  "retry_refused",
  "duplicate_blocked",
  "emergency_stop_requested_preview",
  "drain_requested_preview",
  "pause_requested_preview",
  "server_heartbeat_ingested",
  "server_payload_rejected",
  "evidence_indexed",
  "redaction_scan_passed",
  "redaction_scan_failed",
]);

export const AuditEventSchema = z.object({
  schema: z.literal("skybridge.audit_event.v1"),
  event_id: z.string().min(1),
  actor_type: z.enum(["operator", "codex", "system", "server_preview", "desktop_preview"]),
  event_type: AuditEventTypeSchema,
  run_id: z.string().optional(),
  workunit_id: z.string().optional(),
  alpha_id: z.string().optional(),
  pr_url: z.string().url().optional(),
  decision: z.string().optional(),
  reason: z.string().min(1),
  evidence_hash: z.string().regex(/^[a-f0-9]{64}$/).optional(),
  timestamp: z.string().datetime(),
  token_printed: z.literal(false),
});

export const AuditTrailSchema = z.object({
  schema: z.literal("skybridge.audit_trail.v1"),
  trail_id: z.string().min(1),
  events: z.array(AuditEventSchema),
  raw_payload_included: z.literal(false),
  token_printed: z.literal(false),
});

export const RedactionViolationSchema = z.object({
  schema: z.literal("skybridge.redaction_violation.v1"),
  violation_id: z.string().min(1),
  violation_type: z.string().min(1),
  source_path: z.string().min(1),
  reason: z.string().min(1),
  token_printed: z.literal(false),
});

export const RedactionScanResultSchema = z.object({
  schema: z.literal("skybridge.redaction_scan_result.v1"),
  scan_id: z.string().min(1),
  scanned_path_count: z.number().int().nonnegative(),
  violations: z.array(RedactionViolationSchema),
  passed: z.boolean(),
  token_printed: z.literal(false),
});

export const SafeExportGateSchema = z.object({
  schema: z.literal("skybridge.safe_export_gate.v1"),
  safe_to_export: z.boolean(),
  raw_prompt_persisted: z.literal(false),
  raw_transcript_persisted: z.literal(false),
  raw_stdout_persisted: z.literal(false),
  raw_stderr_persisted: z.literal(false),
  raw_logs_persisted: z.literal(false),
  authorization_persisted: z.literal(false),
  token_printed: z.literal(false),
});

export const AuditReportSchema = z.object({
  schema: z.literal("skybridge.audit_report.v1"),
  audit_trail: AuditTrailSchema,
  redaction_scan: RedactionScanResultSchema,
  safe_export_gate: SafeExportGateSchema,
  release_audit_ready: z.boolean(),
  token_printed: z.literal(false),
});

export const BoincV1ReleaseBlockerSchema = z.object({
  schema: z.literal("skybridge.boinc_v1_release_blocker.v1"),
  blocker_id: z.string().min(1),
  severity: z.enum(["info", "warning", "blocker"]),
  reason: z.string().min(1),
  intentionally_deferred: z.boolean(),
  token_printed: z.literal(false),
});

export const BoincV1ControlledReleasePolicySchema = z.object({
  schema: z.literal("skybridge.boinc_v1_controlled_release_policy.v1"),
  release_version: z.string().min(1),
  generic_bounded_queue_apply_enabled: z.literal(false),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  require_operator_approval: z.literal(true),
  require_resource_gate: z.literal(true),
  require_human_review: z.literal(true),
  require_finalizer: z.literal(true),
  require_failure_budget: z.literal(true),
  require_evidence_retention: z.literal(true),
  require_audit: z.literal(true),
  no_next_execution_authorized: z.literal(true),
  token_printed: z.literal(false),
});

export const BoincV1ReleaseReadinessSchema = z.object({
  schema: z.literal("skybridge.boinc_v1_release_readiness.v1"),
  release_version: z.string().min(1),
  core_engine_ready: z.boolean(),
  boinc_v1_alpha_completed: z.boolean(),
  workunit_a_finalized: z.boolean(),
  workunit_b_finalized: z.boolean(),
  workunit_c_present: z.literal(false),
  desktop_resident_worker_ready: z.boolean(),
  local_supervisor_heartbeat_ready: z.boolean(),
  server_control_plane_ready: z.boolean(),
  worker_pairing_preview_ready: z.boolean(),
  operator_approval_preview_ready: z.boolean(),
  failure_budget_ready: z.boolean(),
  evidence_retention_hash_chain_ready: z.boolean(),
  audit_redaction_ready: z.boolean(),
  safe_export_gate_ready: z.boolean(),
  resource_gate_ready: z.boolean(),
  drain_pause_policy_ready: z.boolean(),
  completed_managed_mode_runs: z.array(z.string()),
  completed_alpha_workunits: z.array(z.string()),
  no_open_task_pr: z.boolean(),
  active_tasks: z.literal(0),
  stale_leases: z.literal(0),
  runner_lock: z.literal("none"),
  remote_execution_enabled: z.literal(false),
  arbitrary_command_enabled: z.literal(false),
  execution_enabled: z.literal(false),
  queue_apply_enabled: z.literal(false),
  generic_bounded_queue_apply_enabled: z.literal(false),
  no_next_execution_authorized: z.literal(true),
  token_printed: z.literal(false),
});

export const BoincV1ReleaseGateSchema = z.object({
  schema: z.literal("skybridge.boinc_v1_release_gate.v1"),
  release_version: z.string().min(1),
  gate_result: z.enum(["pass", "blocked"]),
  release_candidate: z.boolean(),
  blockers: z.array(BoincV1ReleaseBlockerSchema),
  policy: BoincV1ControlledReleasePolicySchema,
  readiness: BoincV1ReleaseReadinessSchema,
  can_execute_now: z.literal(false),
  can_create_workunit_now: z.literal(false),
  can_claim_task_now: z.literal(false),
  token_printed: z.literal(false),
});

export const BoincV1ReleaseStatusSchema = z.object({
  schema: z.literal("skybridge.boinc_v1_release_status.v1"),
  release_version: z.string().min(1),
  release_name: z.string().min(1),
  status: z.enum(["ready", "blocked"]),
  gate: BoincV1ReleaseGateSchema,
  next_safe_action: z.string().min(1),
  token_printed: z.literal(false),
});

export const BoincV1ReleaseTagPlanSchema = z.object({
  schema: z.literal("skybridge.boinc_v1_release_tag_plan.v1"),
  tag: z.string().min(1),
  target_commit: z.string().min(1),
  tag_exists: z.boolean(),
  tag_matches_target: z.boolean(),
  can_create_tag: z.boolean(),
  force_tag: z.literal(false),
  token_printed: z.literal(false),
});

export const BoincV1ReleaseApprovalSchema = z.object({
  schema: z.literal("skybridge.boinc_v1_release_approval.v1"),
  release_approval_id: z.string().min(1),
  release_version: z.string().min(1),
  release_mode: z.enum(["controlled_release_preview", "future_controlled_trial"]),
  allowed_future_modes: z.array(z.string()),
  max_workunits: z.number().int().nonnegative(),
  max_parallel_repo_mutations: z.literal(1),
  require_resource_gate: z.literal(true),
  require_human_review: z.literal(true),
  require_finalizer: z.literal(true),
  require_failure_budget: z.literal(true),
  require_evidence_retention: z.literal(true),
  require_audit: z.literal(true),
  require_server_approval: z.literal(true),
  require_desktop_resident_state: z.literal(true),
  expires_at: z.string().datetime(),
  approval_state: z.enum(["preview_only", "pending", "approved", "rejected", "expired", "consumed"]),
  can_execute_now: z.literal(false),
  token_printed: z.literal(false),
});

export const BoincV1OperatorReleaseDecisionSchema = z.object({
  schema: z.literal("skybridge.boinc_v1_operator_release_decision.v1"),
  release_approval_id: z.string().min(1),
  decision: z.enum(["approved_preview", "rejected_preview", "expired_preview"]),
  reason: z.string().min(1),
  decided_at: z.string().datetime(),
  can_execute_now: z.literal(false),
  token_printed: z.literal(false),
});

export const BoincV1ControlledApplyBoundarySchema = z.object({
  schema: z.literal("skybridge.boinc_v1_controlled_apply_boundary.v1"),
  release_version: z.string().min(1),
  generic_bounded_queue_apply_enabled: z.literal(false),
  remote_arbitrary_command_dispatch_enabled: z.literal(false),
  workunit_creation_enabled: z.literal(false),
  task_claim_enabled: z.literal(false),
  task_pr_creation_enabled: z.literal(false),
  can_execute_now: z.literal(false),
  token_printed: z.literal(false),
});

export const BoincV1ReleaseOperatorPolicySchema = z.object({
  schema: z.literal("skybridge.boinc_v1_release_operator_policy.v1"),
  release_version: z.string().min(1),
  approval_must_expire: z.literal(true),
  approval_single_scope: z.literal(true),
  auditable: z.literal(true),
  shell_command_text_allowed: z.literal(false),
  bypass_resource_gate_allowed: z.literal(false),
  bypass_failure_budget_allowed: z.literal(false),
  bypass_human_review_allowed: z.literal(false),
  bypass_finalizer_allowed: z.literal(false),
  bypass_evidence_retention_allowed: z.literal(false),
  bypass_audit_allowed: z.literal(false),
  token_printed: z.literal(false),
});

export const BoincV1ReleaseReportSchema = z.object({
  schema: z.literal("skybridge.boinc_v1_release_report.v1"),
  release_version: z.string().min(1),
  tag: z.string().min(1),
  commit: z.string().min(1),
  pr_number: z.number().int().nonnegative().optional(),
  merge_commit: z.string().optional(),
  completed_goals: z.array(z.string()),
  completed_workunits_runs: z.array(z.string()),
  release_gate_result: z.enum(["pass", "blocked"]),
  resource_gate_result: z.enum(["pass", "blocked"]),
  desktop_status: z.string().min(1),
  server_status: z.string().min(1),
  failure_budget_status: z.string().min(1),
  evidence_retention_status: z.string().min(1),
  audit_redaction_status: z.string().min(1),
  safe_export_status: z.string().min(1),
  disabled_execution_status: z.string().min(1),
  next_safe_action: z.string().min(1),
  ready_for_postrelease_controlled_trial: z.boolean(),
  token_printed: z.literal(false),
});

export type FailureBudget = z.infer<typeof FailureBudgetSchema>;
export type FailureClassification = z.infer<typeof FailureClassificationSchema>;
export type RetryAuthorizationGate = z.infer<typeof RetryAuthorizationGateSchema>;
export type ReplacementAuthorizationGate = z.infer<typeof ReplacementAuthorizationGateSchema>;
export type FailureBudgetReport = z.infer<typeof FailureBudgetReportSchema>;
export type EvidenceRetentionReport = z.infer<typeof EvidenceRetentionReportSchema>;
export type AuditEvent = z.infer<typeof AuditEventSchema>;
export type AuditReport = z.infer<typeof AuditReportSchema>;
export type RedactionScanResult = z.infer<typeof RedactionScanResultSchema>;
export type SafeExportGate = z.infer<typeof SafeExportGateSchema>;
export type BoincV1ReleaseStatus = z.infer<typeof BoincV1ReleaseStatusSchema>;
export type BoincV1ReleaseReport = z.infer<typeof BoincV1ReleaseReportSchema>;
export type BoincV1ReleaseApproval = z.infer<typeof BoincV1ReleaseApprovalSchema>;

const fixtureHash = "0".repeat(64);
const fixtureHashA = "a".repeat(64);
const fixtureHashB = "b".repeat(64);

export const fixtureFailureBudget: FailureBudget = {
  schema: "skybridge.failure_budget.v1",
  timeout_budget: 1,
  nonzero_exit_budget: 1,
  no_change_budget: 1,
  dirty_worktree_budget: 0,
  resource_gate_block_budget: 3,
  repeated_blocker_suppression: true,
  retry_requires_explicit_authorization: true,
  replacement_requires_no_mutation_classification: true,
  max_retries_per_workunit: 0,
  max_replacements_per_workunit: 1,
  no_silent_rerun: true,
  no_retry_after_pr_created: true,
  no_retry_after_raw_artifact: true,
  no_retry_after_disallowed_change: true,
  no_retry_after_secret_detected: true,
  token_printed: false,
};

export const fixtureFailureClassification: FailureClassification = {
  schema: "skybridge.failure_classification.v1",
  run_id: "managed-mode-run-211",
  workunit_id: "boinc-v1-alpha-215-workunit-b",
  failure_class: "nonzero_no_mutation",
  changed_files: [],
  pr_created: false,
  raw_artifact_detected: false,
  secret_detected: false,
  token_printed: false,
};

export const fixtureRetryAuthorizationGate: RetryAuthorizationGate = {
  schema: "skybridge.retry_authorization_gate.v1",
  workunit_id: fixtureFailureClassification.workunit_id,
  retry_allowed: false,
  automatic_retry_allowed: false,
  explicit_operator_authorization_required: true,
  no_silent_rerun: true,
  no_retry_after_pr_created: true,
  token_printed: false,
};

export const fixtureReplacementAuthorizationGate: ReplacementAuthorizationGate = {
  schema: "skybridge.replacement_authorization_gate.v1",
  workunit_id: fixtureFailureClassification.workunit_id,
  replacement_allowed: true,
  automatic_replacement_allowed: false,
  requires_no_mutation_classification: true,
  explicit_operator_authorization_required: true,
  token_printed: false,
};

export const fixtureFailureBudgetReport: FailureBudgetReport = {
  schema: "skybridge.failure_budget_report.v1",
  policy: fixtureFailureBudget,
  classifications: [fixtureFailureClassification],
  retry_gate: fixtureRetryAuthorizationGate,
  replacement_gate: fixtureReplacementAuthorizationGate,
  blockers: [
    {
      schema: "skybridge.failure_budget_blocker.v1",
      blocker_id: "pr-created-hold",
      failure_class: "pr_created_hold",
      reason: "PR-created work must move through human review and finalizer.",
      retry_blocked: true,
      replacement_blocked: true,
      token_printed: false,
    },
  ],
  ready_for_controlled_release: true,
  token_printed: false,
};

export const fixtureEvidenceRetentionReport: EvidenceRetentionReport = {
  schema: "skybridge.evidence_retention_report.v1",
  retention: {
    schema: "skybridge.evidence_retention.v1",
    policy_id: "goal-219-safe-evidence-retention",
    indexed_paths: [".agent/tmp/server-control-plane/goal-218-report.json"],
    excluded_raw_patterns: ["*.log", "*.stdout*", "*.stderr*", "*prompt*", "*transcript*"],
    safe_to_export: true,
    raw_artifact: false,
    secret_detected: false,
    token_printed: false,
  },
  entries: [
    {
      schema: "skybridge.evidence_index_entry.v1",
      evidence_id: "goal-218-report",
      run_id: "goal-218",
      workunit_id: "none",
      alpha_id: "boinc-v1-alpha-215",
      evidence_type: "control_plane_report",
      source_path: ".agent/tmp/server-control-plane/goal-218-report.json",
      sha256: fixtureHashA,
      previous_hash: fixtureHash,
      chain_index: 0,
      created_at: "2026-06-13T00:00:00.000Z",
      retention_class: "control_plane_report",
      safe_to_export: true,
      raw_artifact: false,
      secret_detected: false,
      token_printed: false,
    },
  ],
  hash_chain: {
    schema: "skybridge.evidence_hash_chain.v1",
    chain_id: "goal-219-fixture-chain",
    entries: [],
    head_hash: fixtureHashB,
    verified: true,
    token_printed: false,
  },
  export_summary: {
    schema: "skybridge.evidence_export_summary.v1",
    entry_count: 1,
    safe_to_export_count: 1,
    raw_artifact_count: 0,
    secret_detected_count: 0,
    token_printed: false,
  },
  violations: [],
  token_printed: false,
};

fixtureEvidenceRetentionReport.hash_chain.entries = fixtureEvidenceRetentionReport.entries;

export const fixtureAuditEvent: AuditEvent = {
  schema: "skybridge.audit_event.v1",
  event_id: "audit-goal-219-redaction-pass",
  actor_type: "system",
  event_type: "redaction_scan_passed",
  run_id: "goal-219",
  alpha_id: "boinc-v1-alpha-215",
  reason: "Safe fixture scan passed without raw artifacts.",
  evidence_hash: fixtureHashB,
  timestamp: "2026-06-13T00:00:00.000Z",
  token_printed: false,
};

export const fixtureSafeExportGate: SafeExportGate = {
  schema: "skybridge.safe_export_gate.v1",
  safe_to_export: true,
  raw_prompt_persisted: false,
  raw_transcript_persisted: false,
  raw_stdout_persisted: false,
  raw_stderr_persisted: false,
  raw_logs_persisted: false,
  authorization_persisted: false,
  token_printed: false,
};

export const fixtureAuditReport: AuditReport = {
  schema: "skybridge.audit_report.v1",
  audit_trail: {
    schema: "skybridge.audit_trail.v1",
    trail_id: "goal-219-audit-trail",
    events: [fixtureAuditEvent],
    raw_payload_included: false,
    token_printed: false,
  },
  redaction_scan: {
    schema: "skybridge.redaction_scan_result.v1",
    scan_id: "goal-219-redaction-scan",
    scanned_path_count: 1,
    violations: [],
    passed: true,
    token_printed: false,
  },
  safe_export_gate: fixtureSafeExportGate,
  release_audit_ready: true,
  token_printed: false,
};

export const fixtureBoincV1ReleaseReadiness: z.infer<typeof BoincV1ReleaseReadinessSchema> = {
  schema: "skybridge.boinc_v1_release_readiness.v1",
  release_version: "v0.99.0-boinc-like-v1-controlled-release",
  core_engine_ready: true,
  boinc_v1_alpha_completed: true,
  workunit_a_finalized: true,
  workunit_b_finalized: true,
  workunit_c_present: false,
  desktop_resident_worker_ready: true,
  local_supervisor_heartbeat_ready: true,
  server_control_plane_ready: true,
  worker_pairing_preview_ready: true,
  operator_approval_preview_ready: true,
  failure_budget_ready: true,
  evidence_retention_hash_chain_ready: true,
  audit_redaction_ready: true,
  safe_export_gate_ready: true,
  resource_gate_ready: true,
  drain_pause_policy_ready: true,
  completed_managed_mode_runs: [
    "managed-mode-pilot-208",
    "managed-mode-run-209",
    "managed-mode-run-210",
    "managed-mode-run-211",
  ],
  completed_alpha_workunits: [
    "boinc-v1-alpha-215-workunit-a",
    "boinc-v1-alpha-215-workunit-b",
  ],
  no_open_task_pr: true,
  active_tasks: 0,
  stale_leases: 0,
  runner_lock: "none",
  remote_execution_enabled: false,
  arbitrary_command_enabled: false,
  execution_enabled: false,
  queue_apply_enabled: false,
  generic_bounded_queue_apply_enabled: false,
  no_next_execution_authorized: true,
  token_printed: false,
};

export const fixtureBoincV1ControlledReleasePolicy: z.infer<typeof BoincV1ControlledReleasePolicySchema> = {
  schema: "skybridge.boinc_v1_controlled_release_policy.v1",
  release_version: fixtureBoincV1ReleaseReadiness.release_version,
  generic_bounded_queue_apply_enabled: false,
  remote_execution_enabled: false,
  arbitrary_command_enabled: false,
  execution_enabled: false,
  queue_apply_enabled: false,
  require_operator_approval: true,
  require_resource_gate: true,
  require_human_review: true,
  require_finalizer: true,
  require_failure_budget: true,
  require_evidence_retention: true,
  require_audit: true,
  no_next_execution_authorized: true,
  token_printed: false,
};

export const fixtureBoincV1ReleaseGate: z.infer<typeof BoincV1ReleaseGateSchema> = {
  schema: "skybridge.boinc_v1_release_gate.v1",
  release_version: fixtureBoincV1ReleaseReadiness.release_version,
  gate_result: "pass",
  release_candidate: true,
  blockers: [
    {
      schema: "skybridge.boinc_v1_release_blocker.v1",
      blocker_id: "installer-packaging-deferred",
      severity: "info",
      reason: "Installer packaging is deferred; manual dev launch is documented for controlled release.",
      intentionally_deferred: true,
      token_printed: false,
    },
  ],
  policy: fixtureBoincV1ControlledReleasePolicy,
  readiness: fixtureBoincV1ReleaseReadiness,
  can_execute_now: false,
  can_create_workunit_now: false,
  can_claim_task_now: false,
  token_printed: false,
};

export const fixtureBoincV1ReleaseStatus: BoincV1ReleaseStatus = {
  schema: "skybridge.boinc_v1_release_status.v1",
  release_version: fixtureBoincV1ReleaseReadiness.release_version,
  release_name: "BOINC-like v1 controlled release",
  status: "ready",
  gate: fixtureBoincV1ReleaseGate,
  next_safe_action: "Tag the merged release commit after post-merge release gate checks pass.",
  token_printed: false,
};

export const fixtureBoincV1ReleaseApproval: BoincV1ReleaseApproval = {
  schema: "skybridge.boinc_v1_release_approval.v1",
  release_approval_id: "boinc-v1-release-approval-preview",
  release_version: fixtureBoincV1ReleaseReadiness.release_version,
  release_mode: "controlled_release_preview",
  allowed_future_modes: ["goal-221-controlled-v1-trial"],
  max_workunits: 0,
  max_parallel_repo_mutations: 1,
  require_resource_gate: true,
  require_human_review: true,
  require_finalizer: true,
  require_failure_budget: true,
  require_evidence_retention: true,
  require_audit: true,
  require_server_approval: true,
  require_desktop_resident_state: true,
  expires_at: "2026-06-15T00:00:00.000Z",
  approval_state: "preview_only",
  can_execute_now: false,
  token_printed: false,
};

export const fixtureBoincV1ControlledApplyBoundary: z.infer<typeof BoincV1ControlledApplyBoundarySchema> = {
  schema: "skybridge.boinc_v1_controlled_apply_boundary.v1",
  release_version: fixtureBoincV1ReleaseReadiness.release_version,
  generic_bounded_queue_apply_enabled: false,
  remote_arbitrary_command_dispatch_enabled: false,
  workunit_creation_enabled: false,
  task_claim_enabled: false,
  task_pr_creation_enabled: false,
  can_execute_now: false,
  token_printed: false,
};

export const fixtureBoincV1ReleaseOperatorPolicy: z.infer<typeof BoincV1ReleaseOperatorPolicySchema> = {
  schema: "skybridge.boinc_v1_release_operator_policy.v1",
  release_version: fixtureBoincV1ReleaseReadiness.release_version,
  approval_must_expire: true,
  approval_single_scope: true,
  auditable: true,
  shell_command_text_allowed: false,
  bypass_resource_gate_allowed: false,
  bypass_failure_budget_allowed: false,
  bypass_human_review_allowed: false,
  bypass_finalizer_allowed: false,
  bypass_evidence_retention_allowed: false,
  bypass_audit_allowed: false,
  token_printed: false,
};

export const fixtureBoincV1ReleaseTagPlan: z.infer<typeof BoincV1ReleaseTagPlanSchema> = {
  schema: "skybridge.boinc_v1_release_tag_plan.v1",
  tag: fixtureBoincV1ReleaseReadiness.release_version,
  target_commit: "HEAD",
  tag_exists: false,
  tag_matches_target: false,
  can_create_tag: true,
  force_tag: false,
  token_printed: false,
};

export const fixtureBoincV1ReleaseReport: BoincV1ReleaseReport = {
  schema: "skybridge.boinc_v1_release_report.v1",
  release_version: fixtureBoincV1ReleaseReadiness.release_version,
  tag: fixtureBoincV1ReleaseReadiness.release_version,
  commit: "HEAD",
  completed_goals: ["214", "215", "216", "217", "218", "219", "220"],
  completed_workunits_runs: [
    ...fixtureBoincV1ReleaseReadiness.completed_managed_mode_runs,
    ...fixtureBoincV1ReleaseReadiness.completed_alpha_workunits,
  ],
  release_gate_result: "pass",
  resource_gate_result: "pass",
  desktop_status: "preview_shell_ready_execution_disabled",
  server_status: "control_plane_preview_ready_no_remote_execution",
  failure_budget_status: "ready_no_silent_rerun",
  evidence_retention_status: "ready_hash_chain_verified",
  audit_redaction_status: "ready_redaction_passed",
  safe_export_status: "safe_to_export",
  disabled_execution_status: "execution_disabled_queue_apply_disabled_remote_disabled",
  next_safe_action: "Proceed only to a separately authorized Goal 221 controlled trial.",
  ready_for_postrelease_controlled_trial: true,
  token_printed: false,
};

export function parseFailureBudget(input: unknown): FailureBudget {
  return FailureBudgetSchema.parse(input);
}

export function parseEvidenceRetentionReport(input: unknown): EvidenceRetentionReport {
  return EvidenceRetentionReportSchema.parse(input);
}

export function parseAuditReport(input: unknown): AuditReport {
  return AuditReportSchema.parse(input);
}

export function parseBoincV1ReleaseStatus(input: unknown): BoincV1ReleaseStatus {
  return BoincV1ReleaseStatusSchema.parse(input);
}
