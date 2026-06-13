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

export function parseFailureBudget(input: unknown): FailureBudget {
  return FailureBudgetSchema.parse(input);
}

export function parseEvidenceRetentionReport(input: unknown): EvidenceRetentionReport {
  return EvidenceRetentionReportSchema.parse(input);
}

export function parseAuditReport(input: unknown): AuditReport {
  return AuditReportSchema.parse(input);
}
