import React from "react";
import { createRoot } from "react-dom/client";
import { invoke } from "@tauri-apps/api/core";
import {
  type CampaignRunReport,
  type CampaignSafeSummary,
  createCampaignSafeSummary,
  createAttentionModel,
  createWorkerServiceReadiness,
  fixtureCampaignRunReport,
  fixtureCampaignLock,
  fixtureCampaignPriorityQueue,
  fixtureBoundedQueuePlan,
  fixtureBoundedQueueReadiness,
  fixtureBoincManagerState,
  fixtureBoincV1ControlledTrialStatus,
  fixtureBoincV1Status,
  fixtureBoincV1AlphaStatus,
  fixtureBoincV1ReleaseApproval,
  fixtureBoincV1ReleaseStatus,
  fixtureTrustedDocsAutoMergeGate,
  fixtureCoreEngineStatus,
  fixtureLocalResourcePolicyEnforcement,
  fixtureManagedModeRepeatabilitySummary,
  fixtureManagedModeRunRegistry,
  fixtureManagedModeV0Status,
  fixtureOneAtATimeManagedModeGate,
  fixtureDesktopResidentState,
  fixtureGoalQueueReviewSummary,
  fixtureAuditReport,
  fixtureEvidenceRetentionReport,
  fixtureFailureBudgetReport,
  fixtureSafeExportGate,
  fixtureWorkerPairingRecord,
  fixtureOperatorApprovalRecord,
  fixtureResidentPollingReport,
  fixtureLocalExecutionGuard,
  fixtureLocalResourcePolicy,
  fixtureLocalWorkerSupervisorState,
  fixtureMultiWorkerReadiness,
  fixtureProposedGoalReviewSummary,
  fixtureProjectProfileReviewSummary,
  fixtureQueueControlState,
  fixtureSchedulingPreview,
  fixtureWorkunitCandidatePack,
  fixtureRepoExclusiveLock,
  fixtureStaleCampaignLock,
  fixtureWorkerServiceState,
  queueControlActionMatrix,
  routeAttentionEvent,
  summarizeCampaignEvidence,
  type AttentionEvent,
  type BoundedQueuePlan,
  type BoundedQueueReadiness,
  type BoincManagerState,
  type BoincV1ControlledTrialStatusSummary,
  type BoincV1Status,
  type BoincV1AlphaStatus,
  type BoincV1ReleaseApprovalSummary,
  type BoincV1ReleaseStatusSummary,
  type TrustedDocsAutoMergeGateSummary,
  type CoreEngineStatus,
  type ManagedModeRepeatabilitySummary,
  type ManagedModeRunRegistry,
  type OneAtATimeManagedModeGate,
  type DesktopResidentState,
  type LocalExecutionGuard,
  type LocalResourcePolicy,
  type LocalResourcePolicyEnforcement,
  type LocalWorkerSupervisorState,
  type ManagedModeV0Status,
  type MultiWorkerReadiness,
  type SchedulingPreview,
  type WorkunitCandidatePack,
  type WorkerServiceState,
  type ProposedGoalReviewSummary,
  type AuditTrailSummary,
  type EvidenceRetentionSummary,
  type FailureBudgetSummary,
  type SafeExportGateSummary,
} from "@skybridge-agent-hub/client";
import "./styles.css";

type DesktopStatus = {
  ok: boolean;
  mode_banner: string;
  mutation_scope: string;
  execution_disabled: boolean;
  project_id: string;
  campaign_id: string;
  worker_id: string;
  worker_status: string;
  current_step: string;
  current_goal_id: string;
  current_goal_status: string;
  current_goal_linked_task_ids: string[];
  current_goal_linked_pr_urls: string[];
  previous_goal_id: string;
  previous_goal_status: string;
  goal_190_linked_task_ids_count: number;
  goal_190_linked_pr_urls_count: number;
  active_tasks: number | null;
  stale_leases: number | null;
  token_printed: boolean;
  last_refresh_time: string;
  status_age_seconds: number;
  pre190_readiness: {
    state: "PASS" | "WARN" | "BLOCK";
    reasons: string[];
  };
  operator_readiness: {
    state: "PASS" | "WARN" | "BLOCK";
    reasons: string[];
  };
  campaign_report: CampaignRunReport | null;
  worker_service_state: WorkerServiceState | null;
  desktop_resident_state: DesktopResidentState | null;
  local_worker_supervisor_state: LocalWorkerSupervisorState | null;
  local_resource_policy: LocalResourcePolicy | null;
  local_execution_guard: LocalExecutionGuard | null;
  workunit_preview_plan: BoundedQueuePlan | null;
  bounded_queue_readiness: BoundedQueueReadiness | null;
  safe_summary: CampaignSafeSummary | null;
  bridge_outcomes: Array<{
    name: string;
    ok: boolean;
    warning: string | null;
  }>;
  report_cached: boolean;
  report_age_seconds: number;
  status_file: string;
  log_file: string;
  report_file: string;
  warnings: string[];
  errors: string[];
};

type HeartbeatResult = {
  ok: boolean;
  token_printed: boolean;
  worker_status: string;
  current_task_id: string | null;
  last_seen: string | null;
  status: DesktopStatus;
};

const emptyStatus: DesktopStatus = {
  ok: false,
  mode_banner: "STANDBY / READ ONLY",
  mutation_scope: "HEARTBEAT ONLY MUTATION",
  execution_disabled: true,
  project_id: "skybridge-agent-hub",
  campaign_id: "dev-queue-189-200",
  worker_id: "laptop-zenbookduo",
  worker_status: "unknown",
  current_step: "unknown",
  current_goal_id: "unknown",
  current_goal_status: "unknown",
  current_goal_linked_task_ids: [],
  current_goal_linked_pr_urls: [],
  previous_goal_id: "unknown",
  previous_goal_status: "unknown",
  goal_190_linked_task_ids_count: 0,
  goal_190_linked_pr_urls_count: 0,
  active_tasks: null,
  stale_leases: null,
  token_printed: false,
  last_refresh_time: "",
  status_age_seconds: 0,
  pre190_readiness: {
    state: "WARN",
    reasons: ["status=unknown"],
  },
  operator_readiness: {
    state: "WARN",
    reasons: ["status=unknown"],
  },
  campaign_report: null,
  worker_service_state: null,
  desktop_resident_state: null,
  local_worker_supervisor_state: null,
  local_resource_policy: null,
  local_execution_guard: null,
  workunit_preview_plan: null,
  bounded_queue_readiness: null,
  safe_summary: null,
  bridge_outcomes: [],
  report_cached: false,
  report_age_seconds: -1,
  status_file: "",
  log_file: "",
  report_file: "",
  warnings: [],
  errors: [],
};

const fixtureStatus: DesktopStatus = {
  ok: true,
  mode_banner: "STANDBY / READ ONLY",
  mutation_scope: "HEARTBEAT ONLY MUTATION",
  execution_disabled: true,
  project_id: "skybridge-agent-hub",
  campaign_id: "dev-queue-189-200",
  worker_id: "laptop-zenbookduo",
  worker_status: "offline",
  current_step: fixtureCampaignRunReport.current_step_id,
  current_goal_id: fixtureCampaignRunReport.current_goal_id,
  current_goal_status: "ready",
  current_goal_linked_task_ids: [],
  current_goal_linked_pr_urls: [],
  previous_goal_id: "super-192-dashboard-safe-actions",
  previous_goal_status: "completed",
  goal_190_linked_task_ids_count: 0,
  goal_190_linked_pr_urls_count: 0,
  active_tasks: 0,
  stale_leases: 0,
  token_printed: false,
  last_refresh_time: "unix:1800000000",
  status_age_seconds: 0,
  pre190_readiness: {
    state: "PASS",
    reasons: ["active_tasks=0", "stale_leases=0", "token_printed=false", "Goal 191 is current/ready and read-only"],
  },
  operator_readiness: {
    state: "PASS",
    reasons: ["active_tasks=0", "stale_leases=0", "token_printed=false", "can_start_one=false", "can_start_queue=false", "can_resume=false", "worker_status=offline"],
  },
  campaign_report: fixtureCampaignRunReport,
  worker_service_state: fixtureWorkerServiceState,
  desktop_resident_state: fixtureDesktopResidentState,
  local_worker_supervisor_state: fixtureLocalWorkerSupervisorState,
  local_resource_policy: fixtureLocalResourcePolicy,
  local_execution_guard: fixtureLocalExecutionGuard,
  workunit_preview_plan: fixtureBoundedQueuePlan,
  bounded_queue_readiness: fixtureBoundedQueueReadiness,
  safe_summary: createCampaignSafeSummary(fixtureCampaignRunReport),
  bridge_outcomes: [
    { name: "campaign_report", ok: true, warning: null },
    { name: "worker_status", ok: false, warning: "worker_status: status bridge command timed out after 30s" },
  ],
  report_cached: true,
  report_age_seconds: 42,
  status_file: ".agent/tmp/desktop-visual-qa/status.fixture.json",
  log_file: ".agent/tmp/desktop-visual-qa/desktop-client.fixture.log",
  report_file: ".agent/tmp/campaign-reports/dev-queue-189-200-campaign-report.md",
  warnings: [],
  errors: [],
};

function StatusValue({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="status-row">
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function ExecutionDisabledBanner({ guard }: { guard: LocalExecutionGuard }) {
  return (
    <section className="mode-strip execution-disabled-banner" aria-label="Execution disabled guard">
      <span>EXECUTION DISABLED</span>
      <span>Start One {guard.start_one_enabled ? "enabled" : "disabled"}</span>
      <span>{`start_all_present=${String(guard.start_all_present)}; ${guard.next_safe_action}`}</span>
    </section>
  );
}

function ResidentStatusPanel({ resident }: { resident: DesktopResidentState }) {
  return (
    <section className="panel resident-status-card" aria-label="Resident status card">
      <h2>Desktop Resident Worker</h2>
      <div className="mode-strip execution-disabled-banner" aria-label="Desktop resident execution disabled banner">
        <span>EXECUTION DISABLED</span>
        <span>queue_apply_enabled={String(resident.queue_apply_enabled)}</span>
        <span>no_next_execution_authorized={String(resident.no_next_execution_authorized)}</span>
      </div>
      <dl>
        <StatusValue label="Schema" value={resident.schema} />
        <StatusValue label="Worker id" value={resident.worker_id} />
        <StatusValue label="Device id" value={resident.device_id} />
        <StatusValue label="Resident enabled" value={String(resident.resident_enabled)} />
        <StatusValue label="Execution enabled" value={String(resident.execution_enabled)} />
        <StatusValue label="Poll enabled" value={String(resident.poll_enabled)} />
        <StatusValue label="Run apply enabled" value={String(resident.run_apply_enabled)} />
        <StatusValue label="Queue apply enabled" value={String(resident.queue_apply_enabled)} />
        <StatusValue label="Resource gate required" value={String(resident.resource_gate_required)} />
        <StatusValue label="Operator approval" value={String(resident.require_operator_approval)} />
        <StatusValue label="Human review" value={String(resident.require_human_review)} />
        <StatusValue label="No next execution" value={String(resident.no_next_execution_authorized)} />
        <StatusValue label="Current repo" value={resident.current_repo} />
        <StatusValue label="Current branch" value={resident.current_branch} />
        <StatusValue label="Current commit" value={resident.current_commit} />
        <StatusValue label="Active tasks" value={String(resident.active_tasks)} />
        <StatusValue label="Stale leases" value={String(resident.stale_leases)} />
        <StatusValue label="Runner lock" value={resident.runner_lock} />
        <StatusValue label="Open review hold" value={String(resident.open_review_hold)} />
        <StatusValue label="Resource gate" value={resident.resource_gate_status} />
        <StatusValue label="Drain/pause state" value={resident.drain_pause_state} />
        <StatusValue label="Last heartbeat" value={resident.last_heartbeat_at ?? "none"} />
        <StatusValue label="Tray available" value={String(resident.tray_available)} />
        <StatusValue label="Window visible" value={String(resident.window_visible)} />
        <StatusValue label="Close to tray" value={resident.close_to_tray_supported ? "preview supported" : "disabled pending safe window-close handler"} />
        <StatusValue label="Autostart" value={`${String(resident.tray_state.autostart_supported)} / enabled=${String(resident.tray_state.autostart_enabled)} / apply=${String(resident.tray_state.autostart_apply_enabled)}`} />
        <StatusValue label="Resident mode" value={resident.resident_mode} />
        <StatusValue label="Safety banner" value={resident.safety_banner.message} />
        <StatusValue label="Pause preview" value={String(resident.control_state.pause_after_current)} />
        <StatusValue label="Drain preview" value={String(resident.control_state.drain_after_current)} />
        <StatusValue label="Emergency stop preview" value={String(resident.control_state.emergency_stop_requested)} />
        <StatusValue label="Completed alpha" value="Workunit A completed; Workunit B completed; Workunit C absent" />
        <StatusValue label="Last refresh" value={resident.last_refresh_at} />
        <StatusValue label="token_printed" value={String(resident.token_printed)} />
      </dl>
      <div className="queue-action-grid" aria-label="Resident worker safe folder actions">
        <button type="button" disabled aria-disabled="true">Open Evidence Folder</button>
        <button type="button" disabled aria-disabled="true">Open Logs Folder</button>
        <a href={resident.github_pr_list_url} target="_blank" rel="noreferrer">Open GitHub PR List</a>
      </div>
    </section>
  );
}

function DurablePairingApprovalPollingPanel() {
  const pairing = fixtureWorkerPairingRecord;
  const approval = fixtureOperatorApprovalRecord;
  const polling = fixtureResidentPollingReport;
  return (
    <section className="panel durable-pairing-polling-card" aria-label="Pairing approval polling status">
      <h2>Durable Pairing / Approval / Polling</h2>
      <div className="mode-strip execution-disabled-banner" aria-label="Desktop durable control-plane execution disabled banner">
        <span>Execution disabled</span>
        <span>Claim disabled</span>
        <span>Queue apply disabled</span>
      </div>
      <dl>
        <StatusValue label="Pairing status" value={`${pairing.pairing_state}; worker=${pairing.worker_id}`} />
        <StatusValue label="Paired worker id" value={pairing.worker_id} />
        <StatusValue label="Pairing state" value={pairing.pairing_state} />
        <StatusValue label="Approval state summary" value={`${approval.state}; can_execute_now=${String(approval.can_execute_now)}`} />
        <StatusValue label="Local supervisor sync status" value="preview-only safe metadata sync" />
        <StatusValue label="Resident polling preview status" value={polling.status.status} />
        <StatusValue label="Last poll summary" value={polling.status.last_poll_summary} />
        <StatusValue label="Next poll interval" value={`${polling.policy.poll_interval_seconds}s`} />
        <StatusValue label="Execution disabled" value={String(polling.policy.execution_enabled === false)} />
        <StatusValue label="Claim disabled" value={String(polling.policy.claim_enabled === false)} />
        <StatusValue label="Queue apply disabled" value={String(polling.policy.queue_apply_enabled === false)} />
        <StatusValue label="no_next_execution_authorized" value={String(polling.policy.no_next_execution_authorized)} />
        <StatusValue label="token_printed" value="false" />
      </dl>
    </section>
  );
}

function TrayPreviewPanel({ resident }: { resident: DesktopResidentState }) {
  return (
    <section className="panel desktop-tray-preview-card" aria-label="Desktop tray preview controls">
      <h2>Tray Controls Preview</h2>
      <dl>
        <StatusValue label="Tray schema" value={resident.tray_state.schema} />
        <StatusValue label="Menu entries" value={resident.tray_state.menu_entries.join("; ")} />
        <StatusValue label="Pause Preview" value={`preview_only apply=${String(resident.tray_state.pause_preview_apply_enabled)}`} />
        <StatusValue label="Drain Preview" value={`preview_only apply=${String(resident.tray_state.drain_preview_apply_enabled)}`} />
        <StatusValue label="Emergency Stop Preview" value={`preview_only apply=${String(resident.tray_state.emergency_stop_preview_apply_enabled)}`} />
        <StatusValue label="Task claim enabled" value={String(resident.tray_state.task_claim_enabled)} />
        <StatusValue label="Codex execution enabled" value={String(resident.tray_state.codex_execution_enabled)} />
        <StatusValue label="Queue apply enabled" value={String(resident.tray_state.queue_apply_enabled)} />
        <StatusValue label="token_printed" value={String(resident.tray_state.token_printed)} />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Pause Preview metadata only</button>
        <button type="button" disabled aria-disabled="true">Drain Preview metadata only</button>
        <button type="button" disabled aria-disabled="true">Emergency Stop Preview metadata only</button>
      </div>
    </section>
  );
}

function LocalWorkerSupervisorPanel({ supervisor }: { supervisor: LocalWorkerSupervisorState }) {
  return (
    <section className="panel local-worker-supervisor-card" aria-label="Local worker supervisor card">
      <h2>Worker Supervisor</h2>
      <dl>
        <StatusValue label="Worker id" value={supervisor.worker_id} />
        <StatusValue label="Service mode" value={supervisor.worker_service_mode} />
        <StatusValue label="Heartbeat age" value={supervisor.heartbeat_age_seconds === null ? "none" : `${supervisor.heartbeat_age_seconds}s`} />
        <StatusValue label="Current task" value={supervisor.current_task_id ?? "none"} />
        <StatusValue label="Can claim tasks" value={String(supervisor.can_claim_tasks)} />
        <StatusValue label="Can execute tasks" value={String(supervisor.can_execute_tasks)} />
        <StatusValue label="Pause requested" value={String(supervisor.pause_requested)} />
        <StatusValue label="Stop requested" value={String(supervisor.stop_requested)} />
        <StatusValue label="Last local evidence" value={supervisor.last_local_evidence_at ?? "none"} />
        <StatusValue label="Readiness blockers" value={supervisor.readiness_blockers.join("; ") || "none"} />
        <StatusValue label="token_printed" value={String(supervisor.token_printed)} />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Start standby metadata only</button>
        <button type="button" disabled aria-disabled="true">Pause metadata only</button>
        <button type="button" disabled aria-disabled="true">Stop standby metadata only</button>
        <button type="button" disabled aria-disabled="true">Resume execution disabled</button>
        <button type="button" disabled aria-disabled="true">Start One disabled</button>
        <button type="button" disabled aria-disabled="true">Start Queue disabled</button>
      </div>
    </section>
  );
}

function LocalResourcePolicyPanel({ policy }: { policy: LocalResourcePolicy }) {
  return (
    <section className="panel local-resource-policy-card" aria-label="Local resource policy card">
      <h2>Resource Policy</h2>
      <dl>
        <StatusValue label="AC required" value={String(policy.require_ac_power)} />
        <StatusValue label="Battery pause" value={`${String(policy.pause_on_battery)} below ${policy.pause_below_battery_percent}%`} />
        <StatusValue label="Idle required" value={String(policy.require_idle)} />
        <StatusValue label="CPU / memory caps" value={`${policy.max_cpu_percent}% / ${policy.max_memory_percent}%`} />
        <StatusValue label="Network required" value={String(policy.network_required)} />
        <StatusValue label="Allowed hours" value={policy.allowed_hours} />
        <StatusValue label="Battery state" value={`${policy.battery_state}; ${policy.battery_percent ?? "unknown"}%`} />
        <StatusValue label="Memory used" value={policy.memory_used_percent === null ? "unknown" : `${policy.memory_used_percent}%`} />
        <StatusValue label="CPU summary" value={policy.cpu_summary} />
        <StatusValue label="Enforcement" value={`${policy.enforcement_status}; source=${policy.policy_source}`} />
        <StatusValue label="Run allowance" value={`can_run_one_at_a_time=${String(policy.can_run_one_at_a_time ?? false)}`} />
        <StatusValue label="Gate blockers" value={policy.blockers?.join("; ") || "none"} />
        <StatusValue label="Sleep/lid note" value={policy.sleep_lid_behavior_note} />
        <StatusValue label="token_printed" value={String(policy.token_printed)} />
      </dl>
    </section>
  );
}

function LocalResourceEnforcementPanel({ enforcement }: { enforcement: LocalResourcePolicyEnforcement }) {
  return (
    <section className="panel local-resource-enforcement-card" aria-label="Local resource enforcement gate">
      <h2>Resource Gate</h2>
      <dl>
        <StatusValue label="Can run one-at-a-time" value={String(enforcement.can_run_one_at_a_time)} />
        <StatusValue label="Observation" value={`${enforcement.observation.observation_source}; ac=${String(enforcement.observation.ac_power)}; network=${String(enforcement.observation.network_available)}`} />
        <StatusValue label="Memory" value={enforcement.observation.memory_used_percent === null ? "unknown" : `${enforcement.observation.memory_used_percent}%`} />
        <StatusValue label="Blockers" value={enforcement.blockers.map((blocker) => blocker.blocker_id).join("; ") || "none"} />
        <StatusValue label="No power mutation" value={String(enforcement.no_powercfg_mutation)} />
        <StatusValue label="Admin required" value={String(enforcement.admin_required)} />
        <StatusValue label="No task execution" value={`claimed=${String(enforcement.task_claimed)}; executed=${String(enforcement.task_executed)}`} />
        <StatusValue label="token_printed" value={String(enforcement.token_printed)} />
      </dl>
    </section>
  );
}

function WorkunitPreviewPanel({
  plan,
  readiness,
}: {
  plan: BoundedQueuePlan;
  readiness: BoundedQueueReadiness;
}) {
  const completed = plan.workunits.filter((workunit) => workunit.state === "completed").length;
  return (
    <section className="panel workunit-preview-card" aria-label="Workunit bounded queue preview card">
      <h2>Workunit / Bounded Queue Preview</h2>
      <dl>
        <StatusValue label="Plan" value={`${plan.plan_id}; mode=${plan.mode}`} />
        <StatusValue label="Workunits" value={`${plan.workunits.length}; completed=${completed}`} />
        <StatusValue label="Bootstrap mapping" value={plan.workunits[0]?.workunit_id ?? "none"} />
        <StatusValue label="State" value={plan.workunits[0]?.state ?? "none"} />
        <StatusValue label="Would create tasks" value={String(plan.would_create_tasks)} />
        <StatusValue label="Would claim tasks" value={String(plan.would_claim_tasks)} />
        <StatusValue label="Would execute tasks" value={String(plan.would_execute_tasks)} />
        <StatusValue label="Would create PRs" value={String(plan.would_create_prs)} />
        <StatusValue label="Would start runner" value={String(plan.would_start_runner)} />
        <StatusValue label="Apply available" value={String(readiness.start_bounded_queue_apply_available)} />
        <StatusValue label="Can start bounded queue" value={String(readiness.can_start_bounded_queue)} />
        <StatusValue label="Blockers" value={readiness.blockers.join("; ")} />
        <StatusValue label="Policy" value={`max_tasks=${plan.policy.max_tasks}; max_prs=${plan.policy.max_prs}; human_review=${String(plan.policy.require_human_review)}`} />
        <StatusValue label="token_printed" value={String(plan.token_printed && readiness.token_printed)} />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Bounded Queue Apply disabled</button>
        <button type="button" disabled aria-disabled="true">No task creation</button>
        <button type="button" disabled aria-disabled="true">No task claim</button>
        <button type="button" disabled aria-disabled="true">No execution</button>
      </div>
    </section>
  );
}

function BoincManagerPanel({ state }: { state: BoincManagerState }) {
  const surface = state.control_surface;
  return (
    <section className="panel boinc-manager-panel" aria-label="BOINC manager control plane">
      <h2>BOINC Manager Control Plane</h2>
      <dl>
        <StatusValue label="Mode" value={`${surface.current_mode.display_name}; enabled=${String(surface.current_mode.enabled)}`} />
        <StatusValue label="Description" value={surface.current_mode.description} />
        <StatusValue label="Resident worker" value={`${state.local_worker_supervisor_state.worker_id}; claim=${String(state.local_worker_supervisor_state.can_claim_tasks)}; execute=${String(state.local_worker_supervisor_state.can_execute_tasks)}`} />
        <StatusValue label="Resource policy" value={`${state.local_resource_policy.enforcement_status}; AC required=${String(state.local_resource_policy.require_ac_power)}`} />
        <StatusValue label="Workunit preview" value={`${state.workunit_preview_plan.workunits.length} workunit; would_execute=${String(state.workunit_preview_plan.would_execute_tasks)}`} />
        <StatusValue label="Bounded queue readiness" value={`can_start_bounded_queue=${String(state.bounded_queue_readiness.can_start_bounded_queue)}; apply=${String(state.bounded_queue_readiness.start_bounded_queue_apply_available)}`} />
        <StatusValue label="Active holds" value={state.active_holds.map((hold) => `${hold.hold_id}:${hold.reason}`).join("; ") || "none"} />
        <StatusValue label="Completed bootstrap trial" value={`${surface.completed_bootstrap_trial.final_state}; ${surface.completed_bootstrap_trial.task_pr_url}`} />
        <StatusValue label="Next safe action" value={state.next_safe_action} />
        <StatusValue label="token_printed" value={String(state.token_printed)} />
      </dl>
      <div className="queue-action-grid">
        {surface.action_matrix.disabled.slice(0, 6).map((action) => (
          <button key={action.action} type="button" disabled aria-disabled="true" title={action.reason_disabled ?? "disabled"}>
            {action.display_name} disabled
          </button>
        ))}
      </div>
    </section>
  );
}

function BoincV1PreviewPanel({ status }: { status: BoincV1Status }) {
  const resourceGate = status.apply_gate.resource_gate as { can_run_one_at_a_time?: boolean; blockers?: string[] };
  return (
    <section className="panel boinc-v1-preview-panel" aria-label="BOINC-like v1 two-workunit preview panel">
      <h2>BOINC-like v1 Preview</h2>
      <dl>
        <StatusValue label="Readiness" value={status.readiness.readiness_id} />
        <StatusValue label="Preview workunits" value={status.preview.workunits.map((workunit) => `${workunit.queue_order}:${workunit.target_path}`).join("; ")} />
        <StatusValue label="Apply disabled" value={String(!status.preview.apply_enabled && status.readiness.apply_disabled)} />
        <StatusValue label="Blocked reason" value={status.preview.blocked_reason} />
        <StatusValue label="Open review hold" value={String(status.preview.blocked_by_open_review)} />
        <StatusValue label="Resource gate state" value={`can_run_one_at_a_time=${String(resourceGate.can_run_one_at_a_time ?? false)}; blockers=${(resourceGate.blockers ?? []).join("; ") || "none"}`} />
        <StatusValue label="Drain / pause" value={`drain_after_current=${String(status.drain_pause_policy.drain_after_current)}; pause_new_claims=${String(status.drain_pause_policy.pause_new_claims)}`} />
        <StatusValue label="Next safe action" value={status.readiness.next_safe_action} />
        <StatusValue label="token_printed" value={String(status.token_printed)} />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Apply disabled</button>
        <button type="button" disabled aria-disabled="true">No task creation</button>
        <button type="button" disabled aria-disabled="true">No task claim</button>
        <button type="button" disabled aria-disabled="true">No execution</button>
      </div>
    </section>
  );
}

function CoreEngineStatusPanel({ status }: { status: CoreEngineStatus }) {
  return (
    <section className="panel core-engine-status-panel" aria-label="Core engine module status panel">
      <h2>Core Engine</h2>
      <dl>
        <StatusValue label="Module status" value={`${status.module_status.modules_added.length} modules; preferred=${String(status.module_status.preferred_implementation_path)}`} />
        <StatusValue label="completed run registry" value={status.completed_run_registry.completed_run_ids.join("; ")} />
        <StatusValue label="Resource gate" value={`required=${String(status.resource_gate_status.resource_gate_required)}; blockers=${status.resource_gate_status.blockers.join("; ") || "none"}`} />
        <StatusValue label="Two-workunit preview" value={`count=${status.two_workunit_preview_status.preview_workunit_count}; apply=${String(status.two_workunit_preview_status.apply_enabled)}`} />
        <StatusValue label="Drain / pause preview" value={`drain=${String(status.drain_pause_preview_status.drain_after_current)}; pause=${String(status.drain_pause_preview_status.pause_new_claims)}`} />
        <StatusValue label="Apply disabled" value={`${status.apply_disabled_status.reason}; general=${String(status.apply_disabled_status.general_bounded_queue_apply_enabled)}`} />
        <StatusValue label="No next execution authorized" value={String(status.no_next_execution_authorized)} />
        <StatusValue label="token_printed" value={String(status.token_printed)} />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Run apply disabled</button>
        <button type="button" disabled aria-disabled="true">Queue apply disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execution disabled</button>
      </div>
      <p>Core engine status is read-only; no raw logs or execution controls are exposed. token_printed=false</p>
    </section>
  );
}

function BoincV1AlphaPanel({ status }: { status: BoincV1AlphaStatus }) {
  return (
    <section className="panel boinc-v1-alpha-panel" aria-label="BOINC v1 alpha status panel">
      <h2>BOINC v1 Alpha</h2>
      <dl>
        <StatusValue label="Alpha id" value={status.alpha_id} />
        <StatusValue label="Workunit A state" value={`${status.workunit_a.workunit_id}:${status.workunit_a.status}`} />
        <StatusValue label="Workunit B state" value={`${status.workunit_b.workunit_id}:${status.workunit_b.status}`} />
        <StatusValue label="Workunit B blocked reason" value={status.workunit_b_blocked_reason} />
        <StatusValue label="Workunit B PR" value={status.workunit_b_pr_url ?? "none"} />
        <StatusValue label="Readiness" value={status.readiness_state} />
        <StatusValue label="Workunit C present" value={String(status.workunit_c_present)} />
        <StatusValue label="No next execution authorized" value={String(status.no_next_execution_authorized)} />
        <StatusValue label="Next safe action" value={status.next_safe_action} />
        <StatusValue label="Open review hold" value={String(status.open_review_hold)} />
        <StatusValue label="Apply disabled" value={String(status.apply_disabled)} />
        <StatusValue label="Resource gate" value={status.resource_gate_status} />
        <StatusValue label="Drain / pause" value={`drain=${String(status.drain_pause_status.drain_after_current)}; pause_new_claims=${String(status.drain_pause_status.pause_new_claims)}`} />
        <StatusValue label="token_printed" value={String(status.token_printed)} />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Alpha completed</button>
        <button type="button" disabled aria-disabled="true">General apply disabled</button>
        <button type="button" disabled aria-disabled="true">Workunit C absent</button>
      </div>
      <p>BOINC v1 alpha completed; Workunit C is absent. token_printed=false</p>
    </section>
  );
}

function ManagedModeRunRegistryPanel({
  registry,
  gate,
  summary,
}: {
  registry: ManagedModeRunRegistry;
  gate: OneAtATimeManagedModeGate;
  summary: ManagedModeRepeatabilitySummary;
}) {
  return (
    <section className="panel managed-mode-run-registry-panel" aria-label="Repeatable Managed Mode run registry">
      <h2>Repeatable Managed Mode</h2>
      <dl>
        <StatusValue label="completed runs" value={registry.completed_runs.map((run) => `${run.run_id}:${run.state}`).join("; ") || "none"} />
        <StatusValue label="Next run preview" value={`${gate.run_id}; workunits=${String(gate.selected_workunit_count ?? 0)}; worker=${gate.selected_worker_id ?? "none"}`} />
        <StatusValue label="Open hold status" value={`open_runs=${summary.open_run_count}; open_prs=${summary.open_managed_mode_pr_count}; active_tasks=${summary.active_tasks}; stale_leases=${summary.stale_leases}; runner_lock=${summary.runner_lock}`} />
        <StatusValue label="Apply disabled reason" value={summary.apply_disabled_reason} />
        <StatusValue label="Next safe action" value={summary.next_safe_action} />
        <StatusValue label="Sequence policy" value={`max_open_runs=${registry.sequence_policy.max_open_runs}; max_workunits=${registry.sequence_policy.max_workunits_per_run}; max_tasks=${registry.sequence_policy.max_tasks_per_run}; max_claims=${registry.sequence_policy.max_claims_per_run}; max_codex=${registry.sequence_policy.max_codex_executions_per_run}; max_prs=${registry.sequence_policy.max_prs_per_run}`} />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Run apply disabled</button>
        <button type="button" disabled aria-disabled="true">No bounded queue apply</button>
        <button type="button" disabled aria-disabled="true">Human review required</button>
      </div>
      <p>Read-only registry panel: no active execution buttons are exposed. token_printed=false</p>
    </section>
  );
}

function ManagedModeV0StatusPanel({ status }: { status: ManagedModeV0Status }) {
  return (
    <section className="panel managed-mode-v0-status-panel" aria-label="Managed Mode v0 status panel">
      <h2>Managed Mode v0</h2>
      <dl>
        <StatusValue label="Release status" value={status.status} />
        <StatusValue label="Readiness id" value={status.release_readiness.readiness_id ?? status.operator_guidance.current_state} />
        <StatusValue label="Completed runs" value={status.completed_runs.completed_run_ids.join("; ")} />
        <StatusValue label="Release readiness" value={String(status.release_readiness.release_ready)} />
        <StatusValue label="No next execution authorized" value={String(status.release_readiness.no_next_execution_authorized)} />
        <StatusValue label="Resource gate integrated" value={String(status.release_readiness.resource_gate_integrated ?? false)} />
        <StatusValue label="Resource gate required" value={String(status.release_readiness.resource_gate_required_for_next_run)} />
        <StatusValue label="General bounded queue apply" value={String(status.release_readiness.general_bounded_queue_apply_enabled)} />
        <StatusValue label="Next safe action" value={status.operator_guidance.next_safe_action} />
        <StatusValue label="token_printed" value={String(status.token_printed)} />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Execution disabled</button>
        <button type="button" disabled aria-disabled="true">Resource gate required</button>
        <button type="button" disabled aria-disabled="true">General bounded queue apply disabled</button>
      </div>
    </section>
  );
}

function DesktopAuditPanel({
  failureBudget,
  evidence,
  audit,
  safeExportGate,
}: {
  failureBudget: FailureBudgetSummary;
  evidence: EvidenceRetentionSummary;
  audit: AuditTrailSummary;
  safeExportGate: SafeExportGateSummary;
}) {
  return (
    <section className="panel desktop-audit-panel" aria-label="Desktop failure budget and audit panel">
      <h2>Failure Budget / Audit</h2>
      <div className="mode-strip execution-disabled-banner" aria-label="Desktop audit execution disabled banner">
        <span>EXECUTION DISABLED</span>
        <span>queue_apply_enabled=false</span>
        <span>token_printed=false</span>
      </div>
      <dl>
        <StatusValue label="Failure budget status" value={failureBudget.policy.no_silent_rerun ? "no silent rerun" : "blocked"} />
        <StatusValue label="Retry gate status" value={`retry_allowed=${String(failureBudget.retry_gate.retry_allowed)}; automatic=${String(failureBudget.retry_gate.automatic_retry_allowed)}`} />
        <StatusValue label="Replacement gate status" value={`replacement_allowed=${String(failureBudget.replacement_gate.replacement_allowed)}; automatic=${String(failureBudget.replacement_gate.automatic_replacement_allowed)}`} />
        <StatusValue label="Evidence retention status" value={`entries=${evidence.entries.length}; safe_to_export=${String(evidence.retention.safe_to_export)}`} />
        <StatusValue label="Hash chain status" value={`verified=${String(evidence.hash_chain.verified)}; head=${evidence.hash_chain.head_hash.slice(0, 12)}`} />
        <StatusValue label="Audit trail summary" value={`${audit.audit_trail.events.length} metadata events; raw_payload_included=${String(audit.audit_trail.raw_payload_included)}`} />
        <StatusValue label="Redaction scan status" value={`passed=${String(audit.redaction_scan.passed)}; violations=${audit.redaction_scan.violations.length}`} />
        <StatusValue label="Safe export gate status" value={`safe_to_export=${String(safeExportGate.safe_to_export)}; raw_logs_persisted=${String(safeExportGate.raw_logs_persisted)}`} />
        <StatusValue label="v1 readiness gap closure status" value="ready for Goal 220 after checks" />
        <StatusValue label="No raw logs" value="raw prompts, transcripts, stdout, stderr, worker logs, CI logs and GitHub logs are not displayed" />
        <StatusValue label="token_printed" value="false" />
      </dl>
    </section>
  );
}

function BoincV1ReleaseStatusPanel({
  status,
  approval,
}: {
  status: BoincV1ReleaseStatusSummary;
  approval: BoincV1ReleaseApprovalSummary;
}) {
  const readiness = status.gate.readiness;
  return (
    <section className="panel boinc-v1-release-status-panel" aria-label="BOINC-like v1 release status">
      <h2>BOINC-like v1 Release</h2>
      <div className="mode-strip execution-disabled-banner" aria-label="Release no execution enabled banner">
        <span>EXECUTION DISABLED</span>
        <span>queue_apply_enabled=false</span>
        <span>remote_execution_enabled=false</span>
        <span>token_printed=false</span>
      </div>
      <dl>
        <StatusValue label="Release version" value={status.release_version} />
        <StatusValue label="Release gate summary" value={`${status.gate.gate_result}; can_execute_now=${String(status.gate.can_execute_now)}`} />
        <StatusValue label="Controlled release policy" value={`resource=${String(status.gate.policy.require_resource_gate)}; approval=${String(status.gate.policy.require_operator_approval)}; review=${String(status.gate.policy.require_human_review)}`} />
        <StatusValue label="Desktop resident state" value={String(readiness.desktop_resident_worker_ready)} />
        <StatusValue label="Resource gate state" value={String(readiness.resource_gate_ready)} />
        <StatusValue label="Server approval state" value={String(readiness.operator_approval_preview_ready)} />
        <StatusValue label="Failure budget state" value={String(readiness.failure_budget_ready)} />
        <StatusValue label="Evidence retention/hash chain state" value={String(readiness.evidence_retention_hash_chain_ready)} />
        <StatusValue label="Audit/redaction state" value={String(readiness.audit_redaction_ready)} />
        <StatusValue label="Safe export status" value={String(readiness.safe_export_gate_ready)} />
        <StatusValue label="Approval preview" value={`${approval.approval_state}; can_execute_now=${String(approval.can_execute_now)}; expires=${approval.expires_at}`} />
        <StatusValue label="No next execution authorized" value={String(readiness.no_next_execution_authorized)} />
        <StatusValue label="Execution enabled" value={String(readiness.execution_enabled)} />
        <StatusValue label="Queue apply enabled" value={String(readiness.queue_apply_enabled)} />
        <StatusValue label="Remote execution enabled" value={String(readiness.remote_execution_enabled)} />
        <StatusValue label="Arbitrary command enabled" value={String(readiness.arbitrary_command_enabled)} />
        <StatusValue label="token_printed" value="false" />
      </dl>
    </section>
  );
}

function BoincV1ControlledTrialPanel({ status }: { status: BoincV1ControlledTrialStatusSummary }) {
  const gate = status.gate;
  const reliability = gate.reliability_gates as Record<string, unknown>;
  const releaseGate = gate.release_gate as Record<string, unknown>;
  const taskPrUrl =
    typeof status.finalizer_preview === "object" &&
    status.finalizer_preview !== null &&
    "task_pr_url" in status.finalizer_preview
      ? String((status.finalizer_preview as Record<string, unknown>).task_pr_url ?? "pending")
      : "pending";
  const finalizerEvidence =
    typeof status.finalizer_preview === "object" &&
    status.finalizer_preview !== null &&
    "finalizer_evidence_path" in status.finalizer_preview
      ? String((status.finalizer_preview as Record<string, unknown>).finalizer_evidence_path)
      : ".agent/tmp/boinc-v1-controlled-trial-221/trial-finalizer-evidence.json";
  return (
    <section className="panel boinc-v1-controlled-trial-panel" aria-label="BOINC v1 controlled trial 221 status">
      <h2>BOINC v1 Controlled Trial 221</h2>
      <div className="mode-strip execution-disabled-banner" aria-label="Controlled trial human review hold">
        <span>boinc_v1_controlled_trial_221_completed</span>
        <span>queue_apply_enabled=false</span>
        <span>remote_execution_enabled=false</span>
        <span>token_printed=false</span>
      </div>
      <dl>
        <StatusValue label="Trial" value={status.trial_id} />
        <StatusValue label="Workunit" value={status.workunit.workunit_id} />
        <StatusValue label="Task" value={`${status.workunit.task_id}; ${status.workunit.task_type}; ${status.workunit.risk}`} />
        <StatusValue label="Target" value={status.workunit.target_path} />
        <StatusValue label="Release gate" value={String(releaseGate.release_gate_result)} />
        <StatusValue label="Approval gate" value={gate.approval_gate.approval_state} />
        <StatusValue label="Resource gate" value={String((gate.resource_gate as Record<string, unknown>).can_run_one_at_a_time)} />
        <StatusValue label="Failure budget gate" value={String(reliability.failure_budget_gate_result)} />
        <StatusValue label="Evidence retention gate" value={String(reliability.evidence_retention_gate_result)} />
        <StatusValue label="Audit/redaction gate" value={String(reliability.audit_redaction_gate_result)} />
        <StatusValue label="Task PR URL" value={taskPrUrl} />
        <StatusValue label="Finalizer evidence" value={finalizerEvidence} />
        <StatusValue label="Human review" value="confirmed by merged task PR" />
        <StatusValue label="No next execution authorized" value={String(gate.no_next_execution_authorized)} />
        <StatusValue label="No raw logs" value="raw prompts, transcripts, stdout, stderr, worker logs and CI logs are not displayed" />
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Trial apply disabled</button>
        <button type="button" disabled aria-disabled="true">Finalizer apply requires merged task PR</button>
      </div>
    </section>
  );
}

function TrustedDocsAutoMergePanel({ gate }: { gate: TrustedDocsAutoMergeGateSummary }) {
  return (
    <section className="panel trusted-docs-auto-merge-panel" aria-label="Trusted docs auto-merge preview">
      <h2>Trusted Docs Auto-merge Preview</h2>
      <div className="mode-strip execution-disabled-banner" aria-label="Trusted docs auto-merge disabled">
        <span>trusted_docs_auto_merge_enabled=false</span>
        <span>auto_merge_apply_enabled=false</span>
        <span>human_review_required=true</span>
        <span>token_printed=false</span>
      </div>
      <dl>
        <StatusValue label="Policy" value={`max_files=${gate.policy.max_files}; max_additions=${gate.policy.max_additions}; max_deletions=${gate.policy.max_deletions}`} />
        <StatusValue label="Allowed paths" value={gate.policy.allowed_paths.join("; ")} />
        <StatusValue label="Decision" value={gate.decision.decision} />
        <StatusValue label="Eligible preview" value={`theoretical=${String(gate.decision.theoretically_eligible)}; auto_merge_allowed=${String(gate.decision.auto_merge_allowed)}`} />
        <StatusValue label="Blockers" value={gate.decision.blockers.join("; ")} />
        <StatusValue label="Audit" value={gate.audit.events.join("; ")} />
        <StatusValue label="No enabled auto-merge button" value="true" />
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Auto-merge disabled</button>
        <button type="button" disabled aria-disabled="true">Human review required</button>
      </div>
    </section>
  );
}

function App() {
  const fixtureOnly = isFixtureMode();
  const [status, setStatus] = React.useState<DesktopStatus>(fixtureOnly ? fixtureStatus : emptyStatus);
  const [refreshing, setRefreshing] = React.useState(false);
  const refreshGeneration = React.useRef(0);
  const [message, setMessage] = React.useState(fixtureOnly ? "Fixture-only visual QA" : "Standby");
  const [nowSeconds, setNowSeconds] = React.useState(() => Math.floor(Date.now() / 1000));

  const refresh = React.useCallback(async () => {
    if (fixtureOnly) {
      setStatus(fixtureStatus);
      setMessage("Fixture-only status rendered");
      return;
    }
    const generation = refreshGeneration.current + 1;
    refreshGeneration.current = generation;
    setRefreshing(true);
    setMessage(status.campaign_report ? "Refreshing in background; cached report remains visible" : "Refreshing read-only status");
    try {
      const next = await invoke<DesktopStatus>("get_status", { requestId: `desktop-refresh-${generation}` });
      if (generation !== refreshGeneration.current) {
        setMessage("Older refresh result ignored");
        return;
      }
      setStatus(next);
      setMessage(next.report_cached ? "Status refreshed with cached report" : "Status refreshed");
    } catch (error) {
      if (generation !== refreshGeneration.current) {
        return;
      }
      setMessage(`Refresh failed: ${String(error)}`);
    } finally {
      if (generation === refreshGeneration.current) {
        setRefreshing(false);
      }
    }
  }, [fixtureOnly, status.campaign_report]);

  const openReport = React.useCallback(async () => {
    if (fixtureOnly) {
      setMessage("Fixture-only: report artifact open skipped");
      return;
    }
    setMessage("Opening safe campaign report artifact");
    try {
      await invoke("open_report");
      setMessage("Report artifact opened");
    } catch (error) {
      setMessage(`Open report failed: ${String(error)}`);
      window.setTimeout(() => {
        void refresh();
      }, 0);
    } finally {
    }
  }, [fixtureOnly, refresh]);

  const copySafeSummary = React.useCallback(async () => {
    const summary = status.safe_summary ?? (status.campaign_report ? createCampaignSafeSummary(status.campaign_report) : null);
    if (!summary) {
      setMessage("Safe summary unavailable");
      return;
    }
    const text = JSON.stringify(summary, null, 2);
    if (containsSecretLookingText(text)) {
      setMessage("Safe summary blocked by secret-pattern guard");
      return;
    }
    await navigator.clipboard?.writeText(text);
    setMessage("Safe summary copied");
  }, [status]);

  React.useEffect(() => {
    void refresh();
  }, [refresh]);

  React.useEffect(() => {
    const timer = window.setInterval(() => setNowSeconds(Math.floor(Date.now() / 1000)), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const refreshEpoch = parseUnixTimestamp(status.last_refresh_time);
  const statusAge = refreshEpoch === null ? "unknown" : `${Math.max(0, nowSeconds - refreshEpoch)}s`;
  const readinessState = status.operator_readiness?.state ?? status.pre190_readiness.state;
  const readinessClass = `readiness readiness-${readinessState.toLowerCase()}`;
  const report = status.campaign_report ?? fixtureCampaignRunReport;
  const readiness = report.queue_control_readiness;
  const evidence = summarizeCampaignEvidence(report);
  const attention = createAttentionModel(report);
  const workerService = status.worker_service_state ?? report.worker_service_state ?? fixtureWorkerServiceState;
  const workerReadiness = createWorkerServiceReadiness(workerService);
  const residentState = status.desktop_resident_state ?? report.desktop_resident_state ?? fixtureDesktopResidentState;
  const supervisorState = status.local_worker_supervisor_state ?? report.local_worker_supervisor_state ?? fixtureLocalWorkerSupervisorState;
  const resourcePolicy = status.local_resource_policy ?? report.local_resource_policy ?? fixtureLocalResourcePolicy;
  const executionGuard = status.local_execution_guard ?? report.local_execution_guard ?? fixtureLocalExecutionGuard;
  const workunitPlan = status.workunit_preview_plan ?? report.workunit_preview_plan ?? fixtureBoundedQueuePlan;
  const boundedQueueReadiness = status.bounded_queue_readiness ?? report.bounded_queue_readiness ?? fixtureBoundedQueueReadiness;
  const remainingSteps = report.step_ledger.filter((step) => step.status === "pending");
  const goal190IsCurrent = report.current_goal_id === "super-190-campaign-run-report-evidence-ledger";
  const previewActions = queueControlActionMatrix.filter((entry) => entry.class === "preview");
  const forbiddenActions = queueControlActionMatrix.filter((entry) => entry.class === "armed_execution" || entry.class === "forbidden");

  return (
    <main className="shell">
      <header className="topbar">
        <div>
          <h1>SkyBridge Desktop</h1>
          <p>Local resident standby status and heartbeat tool</p>
        </div>
        <div className={readinessClass}>
          Queue Readiness {readinessState}
        </div>
      </header>

      <section className="mode-strip" aria-label="Desktop safety mode">
        <span>{status.mode_banner}</span>
        <span>{status.mutation_scope}</span>
        <span>{status.execution_disabled ? "EXECUTION DISABLED" : "EXECUTION STATE UNKNOWN"}</span>
      </section>

      <section className="toolbar" aria-label="Queue dashboard actions">
        <button type="button" onClick={refresh} disabled={refreshing}>
          {refreshing ? "Refreshing..." : "Refresh"}
        </button>
        <button type="button" onClick={openReport}>
          Open report
        </button>
        <button type="button" onClick={copySafeSummary}>
          Copy safe summary
        </button>
        <span>{message}</span>
      </section>

      <section className="panel queue-panel">
        <h2>Read-only Queue Dashboard</h2>
        <dl>
          <StatusValue label="Campaign id" value={report.campaign_id} />
          <StatusValue label="Campaign status" value={report.campaign_status} />
          <StatusValue label="Current step" value={report.current_step_id} />
          <StatusValue label="Current goal" value={`${report.current_goal_id} (${report.current_goal_status})`} />
          <StatusValue label="Previous completed step" value={report.previous_step_summary?.goal_id ?? "unknown"} />
          <StatusValue label="Remaining steps" value={remainingSteps.length} />
          <StatusValue label="Worker status" value={readiness.worker_status} />
          <StatusValue label="Next safe action" value={readiness.next_safe_action} />
        </dl>
      </section>

      <AttentionPanel events={attention.attention_events} />
      <ExecutionDisabledBanner guard={executionGuard} />
      <BoincManagerPanel state={fixtureBoincManagerState} />
      <CoreEngineStatusPanel status={fixtureCoreEngineStatus} />
      <BoincV1AlphaPanel status={fixtureBoincV1AlphaStatus} />
      <BoincV1PreviewPanel status={fixtureBoincV1Status} />
      <BoincV1ReleaseStatusPanel
        status={fixtureBoincV1ReleaseStatus}
        approval={fixtureBoincV1ReleaseApproval}
      />
      <BoincV1ControlledTrialPanel status={fixtureBoincV1ControlledTrialStatus} />
      <TrustedDocsAutoMergePanel gate={fixtureTrustedDocsAutoMergeGate} />
      <ManagedModeV0StatusPanel status={fixtureManagedModeV0Status} />
      <DesktopAuditPanel
        failureBudget={fixtureFailureBudgetReport}
        evidence={fixtureEvidenceRetentionReport}
        audit={fixtureAuditReport}
        safeExportGate={fixtureSafeExportGate}
      />
      <ManagedModeRunRegistryPanel
        registry={fixtureManagedModeRunRegistry}
        gate={fixtureOneAtATimeManagedModeGate}
        summary={fixtureManagedModeRepeatabilitySummary}
      />
      <ResidentStatusPanel resident={residentState} />
      <DurablePairingApprovalPollingPanel />
      <TrayPreviewPanel resident={residentState} />
      <LocalWorkerSupervisorPanel supervisor={supervisorState} />
      <LocalResourcePolicyPanel policy={resourcePolicy} />
      <LocalResourceEnforcementPanel enforcement={fixtureLocalResourcePolicyEnforcement} />
      <WorkunitPreviewPanel plan={workunitPlan} readiness={boundedQueueReadiness} />
      <CampaignLockPanel />
      <CampaignPriorityQueuePanel />
      <ProjectProfileReviewPanel />
      <GoalQueueReviewPanel />
      <ProposedGoalReviewPanel review={fixtureProposedGoalReviewSummary} />
      <WorkunitCandidateReviewPanel pack={fixtureWorkunitCandidatePack} />
      <WorkerServicePanel service={workerService} readiness={workerReadiness} />
      <WorkerPoolPreviewPanel preview={fixtureSchedulingPreview} readiness={fixtureMultiWorkerReadiness} />
      <WorkerRoutingPanel report={report} />

      <section className="panel queue-panel">
        <h2>Queue Control Readiness</h2>
        <dl>
          <StatusValue label="can_start_one" value={String(readiness.can_start_one)} />
          <StatusValue label="can_start_queue" value={String(readiness.can_start_queue)} />
          <StatusValue label="can_resume" value={String(readiness.can_resume)} />
          <StatusValue label="can_stop" value={String(readiness.can_stop)} />
          <StatusValue label="can_emergency_stop" value={String(readiness.can_emergency_stop)} />
          <StatusValue label="Evidence counts" value={`present=${evidence.present}; recovered=${evidence.recovered}; missing=${evidence.missing}; not_applicable=${evidence.not_applicable}`} />
          <StatusValue label="Blockers" value={readiness.blockers.join("; ") || "none"} />
          <StatusValue label="Warnings" value={readiness.warnings.join("; ") || "none"} />
        </dl>
      </section>

      <section className="future-controls" aria-label="Future execution controls">
        <span>Start One Apply disabled by queue-control contract</span>
        <span>Start Queue Apply disabled by queue-control contract</span>
        <span>Start All disabled</span>
        <span>Run Forever disabled</span>
        <span>Worker Loop disabled</span>
      </section>

      <section className="panel queue-actions" aria-label="Safe Actions / Queue Controls">
        <h2>Safe Actions / Queue Controls</h2>
        <dl>
          <StatusValue label="Reason required" value={String(readiness.reason_required)} />
          <StatusValue label="worker_offline blocker" value={String(readiness.blockers.includes("worker_offline"))} />
          <StatusValue label="State hash" value={fixtureQueueControlState.state_hash} />
          <StatusValue label="Audit result" value="shown after safe action apply" />
          <StatusValue label="Start disabled reason" value={`worker=${readiness.worker_status}; execution apply deferred until worker service mode`} />
          <StatusValue label="Preview action ids" value="start_one_preview; start_queue_preview; resume_preview" />
        </dl>
        <div className="queue-action-grid">
          <button type="button" onClick={refresh} disabled={refreshing}>
            Refresh
          </button>
          <button type="button" onClick={openReport}>
            Report
          </button>
          <button type="button" onClick={copySafeSummary}>
            Copy Safe Summary
          </button>
          <button type="button" disabled aria-disabled="true">
            Safe Pause
          </button>
          <button type="button" disabled aria-disabled="true">
            Stop Queue
          </button>
          <button type="button" disabled aria-disabled="true">
            Emergency Stop
          </button>
          {previewActions.map((entry) => (
            <button type="button" key={entry.action}>
              {entry.action.replace(/_/g, " ")}
            </button>
          ))}
          {forbiddenActions.map((entry) => (
            <button type="button" key={entry.action} disabled aria-disabled="true">
              {entry.action.replace(/_/g, " ")} disabled
            </button>
          ))}
        </div>
      </section>

      <section className="panel">
        <h2>Campaign Status</h2>
        <dl>
          <StatusValue label="Project id" value={status.project_id} />
          <StatusValue label="Campaign id" value={status.campaign_id} />
          <StatusValue label="Current step id" value={report.current_step_id} />
          <StatusValue label="Current goal" value={`${report.current_goal_id} (${report.current_goal_status})`} />
          <StatusValue label="Previous goal" value={`${report.previous_step_summary?.goal_id ?? status.previous_goal_id} (${report.previous_step_summary?.status ?? status.previous_goal_status})`} />
          {goal190IsCurrent ? (
            <>
              <StatusValue label="Goal 190 task links" value={status.goal_190_linked_task_ids_count} />
              <StatusValue label="Goal 190 PR links" value={status.goal_190_linked_pr_urls_count} />
            </>
          ) : null}
        </dl>
      </section>

      <section className="panel">
        <h2>Safety Gate</h2>
        <dl>
          <StatusValue label="Worker id" value={status.worker_id} />
          <StatusValue label="Worker status" value={status.worker_status || "unknown"} />
          <StatusValue label="Active tasks" value={formatKnownNumber(status.active_tasks)} />
          <StatusValue label="Stale leases" value={formatKnownNumber(status.stale_leases)} />
          <StatusValue label="Token printed" value={String(status.token_printed)} />
          <StatusValue label="Last refresh" value={status.last_refresh_time || "not refreshed"} />
          <StatusValue label="Status age" value={statusAge} />
          <StatusValue label="Report cache" value={status.report_cached ? `cached; age=${formatAge(status.report_age_seconds)}` : `fresh; file_age=${formatAge(status.report_age_seconds)}`} />
          <StatusValue label="Bridge warnings" value={status.warnings.length + status.errors.length} />
        </dl>
      </section>

      <section className={readinessClass}>
        <h2>Operator Readiness</h2>
        <p>{status.operator_readiness.reasons.join("; ")}</p>
      </section>

      <section className="panel">
        <h2>Local Metadata</h2>
        <dl>
          <StatusValue label="Status file" value={status.status_file || ".agent/desktop-client/status.json"} />
          <StatusValue label="Log file" value={status.log_file || ".agent/desktop-client/logs/desktop-client.log"} />
          <StatusValue label="Report file" value={status.report_file || ".agent/tmp/campaign-reports/dev-queue-189-200-campaign-report.md"} />
        </dl>
      </section>

      {status.warnings.length > 0 || status.errors.length > 0 ? (
        <section className="panel errors">
          <h2>Bridge Warnings</h2>
          {status.bridge_outcomes.length > 0 ? (
            <dl>
              {status.bridge_outcomes.map((outcome) => (
                <StatusValue
                  key={outcome.name}
                  label={outcome.name}
                  value={outcome.ok ? "ok" : outcome.warning ?? "warning"}
                />
              ))}
            </dl>
          ) : null}
          <ul>
            {status.warnings.map((warning) => (
              <li key={warning}>{warning}</li>
            ))}
            {status.errors.map((error) => (
              <li key={error}>{error}</li>
            ))}
          </ul>
        </section>
      ) : null}
    </main>
  );
}

function WorkerPoolPreviewPanel({
  preview,
  readiness,
}: {
  preview: SchedulingPreview;
  readiness: MultiWorkerReadiness;
}) {
  return (
    <section className="panel worker-pool-preview-card" aria-label="Worker Pool Preview card">
      <h2>Worker Pool Preview</h2>
      <dl>
        <StatusValue label="Workers" value={`total=${readiness.worker_pool_count}; ready_preview_only=${readiness.ready_preview_only_count}; stale=${readiness.stale_count}; disabled=${readiness.disabled_count}`} />
        <StatusValue label="Groups" value={preview.worker_pool.groups.join("; ")} />
        <StatusValue label="Route plan" value={`${preview.route_plan.plan_id}; routes=${preview.route_plan.selected_routes.length}`} />
        <StatusValue label="Selected route" value={preview.route_plan.selected_routes.map((route) => `${route.workunit_id}->${route.selected_worker_id ?? "none"}`).join("; ")} />
        <StatusValue label="Repo parallelism" value={`max_parallel_per_repo=${preview.repo_parallelism_policy.max_parallel_per_repo}; mutating_serialized=${String(preview.repo_parallelism_policy.mutating_work_serialized)}`} />
        <StatusValue label="Apply disabled" value={String(!preview.apply_available)} />
        <StatusValue label="No claim/lease/execution" value={`task_claimed=${String(preview.task_claimed)}; lease_created=${String(preview.lease_created)}; task_executed=${String(preview.task_executed)}`} />
        <StatusValue label="Attention" value={readiness.attention_events.join("; ")} />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Scheduling apply disabled</button>
        <button type="button" disabled aria-disabled="true">Create claim disabled</button>
        <button type="button" disabled aria-disabled="true">Create lease disabled</button>
        <button type="button" disabled aria-disabled="true">Execute workunit disabled</button>
      </div>
    </section>
  );
}

function WorkerRoutingPanel({ report }: { report: CampaignRunReport }) {
  const routing = report.queue_control_readiness.routing_readiness;
  const preview = routing?.route_preview;
  return (
    <section className="panel worker-routing-panel" aria-label="Multi-worker readiness and routing panel">
      <h2>Multi-worker Readiness</h2>
      <dl>
        <StatusValue label="Worker pool counts" value={routing ? `total=${routing.worker_pool_counts.total}; online=${routing.worker_pool_counts.online}; stale=${routing.worker_pool_counts.stale}; offline=${routing.worker_pool_counts.offline}; disabled=${routing.worker_pool_counts.disabled}; busy=${routing.worker_pool_counts.busy}` : "unavailable"} />
        <StatusValue label="Preview candidates" value={String(routing?.worker_pool_counts.preview_candidates ?? 0)} />
        <StatusValue label="Selected worker preview" value={preview?.selected_worker?.worker_label ?? "none"} />
        <StatusValue label="Project profile hash" value={preview?.task.project_profile_hash ?? "none"} />
        <StatusValue label="Project selection" value={preview?.task.project_selection_preview_only ? "preview only" : "unavailable"} />
        <StatusValue label="Execution enabled" value={String(routing?.execution_enabled ?? false)} />
        <StatusValue label="max_parallel_per_repo" value={String(preview?.repo_parallelism_guard.max_parallel_per_repo ?? 1)} />
        <StatusValue label="Repo guard" value={preview ? `blocked=${preview.repo_parallelism_guard.blocked}; blocker=${preview.repo_parallelism_guard.blocker ?? "none"}` : "unavailable"} />
        <StatusValue label="No claim/no execution" value={`task_claimed=${String(preview?.task_claimed ?? false)}; task_executed=${String(preview?.task_executed ?? false)}; worker_loop_started=${String(preview?.worker_loop_started ?? false)}`} />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <div className="capability-grid">
        {(routing?.worker_capability_matrix ?? []).map((worker) => (
          <span key={worker.worker_id}>{worker.worker_label}: {worker.os}; {worker.tools.join(", ")}</span>
        ))}
      </div>
      <ul>
        {(preview?.rejected_workers ?? []).slice(0, 5).map((worker) => (
          <li key={worker.worker_id}>{worker.worker_label}: {worker.rejection_reasons.join(", ") || "accepted"}</li>
        ))}
      </ul>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Start One disabled</button>
        <button type="button" disabled aria-disabled="true">Claim task disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execution disabled</button>
      </div>
    </section>
  );
}

function GoalQueueReviewPanel() {
  const review = fixtureGoalQueueReviewSummary;
  return (
    <section className="panel goal-queue-review" aria-label="Manual goal queue review">
      <h2>Manual Goal Queue Review</h2>
      <dl>
        <StatusValue label="Goal pack id" value={review.goal_pack_id} />
        <StatusValue label="Current pack hash" value={review.current_campaign_pack_hash} />
        <StatusValue label="Validation result" value={review.validation_result} />
        <StatusValue label="Hash drift count" value={review.hash_drift_count} />
        <StatusValue label="Dependency/order status" value={review.dependency_order_status} />
        <StatusValue label="Proposed update action" value={review.proposed_import_update_action} />
        <StatusValue label="Re-import preview" value={`added=${review.reimport_preview_summary.added_goals}; removed=${review.reimport_preview_summary.removed_goals}; changed=${review.reimport_preview_summary.changed_goals}; safety=${review.reimport_preview_summary.safety_policy_changes}; safe=${review.reimport_preview_summary.update_safe}`} />
        <StatusValue label="Archive preview" value={`${review.archive_preview_summary.archive_target}; would_archive=${review.archive_preview_summary.would_archive}; excludes_raw_logs_and_secrets=${review.archive_preview_summary.excludes_raw_logs_and_secrets}`} />
        <StatusValue label="No execution controls" value={String(review.no_execution_controls)} />
        <StatusValue label="Task created" value={String(review.task_created)} />
        <StatusValue label="Worker loop started" value={String(review.worker_loop_started)} />
        <StatusValue label="Queue execution enabled" value={String(review.queue_execution_enabled)} />
        <StatusValue label="token_printed" value="false" />
      </dl>
    </section>
  );
}

function ProposedGoalReviewPanel({ review }: { review: ProposedGoalReviewSummary }) {
  return (
    <section className="panel proposed-goal-review" aria-label="Proposed goal review">
      <h2>Proposed Goal Review</h2>
      <dl>
        <StatusValue label="Proposed goals" value={review.proposed_goal_count} />
        <StatusValue label="Pending review" value={review.pending_review_count} />
        <StatusValue label="Blocked drafts" value={review.blocked_draft_count} />
        <StatusValue label="Next action" value={review.next_action} />
        <StatusValue label="Import requires Goal 200" value={String(review.import_requires_goal_200)} />
        <StatusValue label="Approved" value={String(review.approved_count)} />
        <StatusValue label="Rejected" value={String(review.rejected_count)} />
        <StatusValue label="Imported" value={String(review.imported_count)} />
        <StatusValue label="Import target" value={review.import_target} />
        <StatusValue label="Controlled Review / Import" value={`Approve preview=${review.review_controls.approve_preview}; Reject preview=${review.review_controls.reject_preview}; Edit staged=${review.review_controls.edit_staged}; Import preview=${review.review_controls.import_preview}; Import apply disabled=${review.review_controls.import_apply}`} />
        <StatusValue label="Reason gated" value={review.review_controls.approve_preview === "reason-gated" ? "reason-gated" : "unavailable"} />
        <StatusValue label="manifest diff" value={`${review.import_preview_summary.target_path}; ${review.import_preview_summary.manifest_diff.join("; ")}; ${review.import_preview_summary.dependency_order_changes.join("; ")}; ${review.import_preview_summary.hash_changes.join("; ")}`} />
        <StatusValue label="execution review required" value={String(review.import_preview_summary.execution_review_required)} />
        <StatusValue label="Imported" value={String(review.imported)} />
        <StatusValue label="Executed" value={String(review.executed)} />
        <StatusValue label="Task created" value={String(review.task_created)} />
        <StatusValue label="Worker loop started" value={String(review.worker_loop_started)} />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <ul>
        {review.proposed_goals.map((goal) => (
          <li key={goal.proposed_goal_id}>
            <strong>{goal.title}</strong> {goal.safety_classification} {goal.review_status} {goal.proposed_markdown_path} {goal.content_hash.slice(0, 12)} reviewer={goal.reviewer ?? "none"} decision={goal.decision ?? "pending"} import={goal.import_status ?? "not_imported"} target={goal.import_target ?? "none"} deps={goal.suggested_dependencies.join(", ") || "none"} notes={goal.review_notes.join("; ")}
          </li>
        ))}
      </ul>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Approve preview reason-gated</button>
        <button type="button" disabled aria-disabled="true">Reject preview reason-gated</button>
        <button type="button" disabled aria-disabled="true">Edit staged hash recompute</button>
        <button type="button" disabled aria-disabled="true">Import preview dry-run</button>
        <button type="button" disabled aria-disabled="true">Import apply disabled</button>
        <button type="button" disabled aria-disabled="true">Import disabled</button>
        <button type="button" disabled aria-disabled="true">Execute disabled</button>
      </div>
    </section>
  );
}

function WorkunitCandidateReviewPanel({ pack }: { pack: WorkunitCandidatePack }) {
  const lowRisk = pack.candidates.filter((candidate) => candidate.risk === "low").length;
  return (
    <section className="panel workunit-candidate-review" aria-label="Workunit Candidate Review">
      <h2>Workunit Candidate Review</h2>
      <dl>
        <StatusValue label="Candidate pack" value={pack.candidate_pack_id} />
        <StatusValue label="Candidates" value={pack.candidates.length} />
        <StatusValue label="Low-risk candidates" value={lowRisk} />
        <StatusValue label="Candidate ready" value={pack.candidate_ready_count} />
        <StatusValue label="Blocked" value={pack.blocked_count} />
        <StatusValue label="Requires review" value={pack.requires_review_count} />
        <StatusValue label="Bounded queue preview only" value={String(pack.bounded_queue_preview_only)} />
        <StatusValue label="Execution disabled" value={String(pack.execution_disabled)} />
        <StatusValue label="Apply available" value={String(pack.apply_available)} />
        <StatusValue label="Next safe action" value={pack.next_safe_action} />
        <StatusValue label="token_printed" value={String(pack.token_printed)} />
      </dl>
      <ul>
        {pack.candidates.map((candidate) => (
          <li key={candidate.candidate_id}>
            <strong>{candidate.candidate_id}</strong> {candidate.conversion_status} risk={candidate.risk} workunit={candidate.suggested_workunit_id} blockers={candidate.blockers.join(", ") || "none"} warnings={candidate.warnings.join(", ")}
          </li>
        ))}
      </ul>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">Candidate execution disabled</button>
        <button type="button" disabled aria-disabled="true">Task creation disabled</button>
        <button type="button" disabled aria-disabled="true">Worker claim disabled</button>
        <button type="button" disabled aria-disabled="true">Bounded queue apply disabled</button>
      </div>
    </section>
  );
}

function ProjectProfileReviewPanel() {
  const profile = fixtureProjectProfileReviewSummary;
  return (
    <section className="panel project-profile-review" aria-label="Project profile review">
      <h2>Project Profile Review</h2>
      <dl>
        <StatusValue label="Selected project" value={profile.project_id} />
        <StatusValue label="Display name" value={profile.display_name} />
        <StatusValue label="Validation status" value={profile.validation_status} />
        <StatusValue label="Repo identity" value={profile.repo_identity} />
        <StatusValue label="Repo path" value={profile.repo_path_display} />
        <StatusValue label="Default branch" value={profile.default_branch} />
        <StatusValue label="Allowed paths" value={profile.allowed_paths.join("; ")} />
        <StatusValue label="Blocked paths" value={profile.blocked_paths.join("; ")} />
        <StatusValue label="Validation commands" value={profile.validation_commands.map((command) => `${command.id}: executes=${String(command.executes)}`).join("; ")} />
        <StatusValue label="Worker profile" value={`${profile.worker_profile_summary.default_worker_profile}; can_claim=${String(profile.worker_profile_summary.can_claim_tasks)}; can_execute=${String(profile.worker_profile_summary.can_execute_tasks)}`} />
        <StatusValue label="Goal pack" value={`${profile.goal_pack_summary.default_goal_pack_dir}; import_apply=${String(profile.goal_pack_summary.import_apply_enabled)}`} />
        <StatusValue label="Policy summary" value={`dry_run_default=${String(profile.policy_summary.dry_run_default)}; selection_preview_only=${String(profile.policy_summary.selection_preview_only)}; forbid_arbitrary_shell=${String(profile.policy_summary.forbid_arbitrary_shell)}`} />
        <StatusValue label="Profile hash" value={profile.profile_hash} />
        <StatusValue label="No execution controls" value={String(profile.no_execution_controls)} />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">
          Validate commands disabled
        </button>
        <button type="button" disabled aria-disabled="true">
          Project selection apply disabled
        </button>
        <button type="button" disabled aria-disabled="true">
          External repo mutation disabled
        </button>
      </div>
    </section>
  );
}

function CampaignLockPanel() {
  return (
    <section className="panel campaign-lock-review" aria-label="Campaign and repo lock review">
      <h2>Campaign Lock Review</h2>
      <dl>
        <StatusValue label="campaign_lock" value={fixtureCampaignLock.lock_status} />
        <StatusValue label="repo_exclusive_lock" value={fixtureRepoExclusiveLock.lock_status} />
        <StatusValue label="Lock owner" value={fixtureRepoExclusiveLock.lock_owner.display_name} />
        <StatusValue label="Heartbeat age" value={`${fixtureRepoExclusiveLock.age_seconds}s`} />
        <StatusValue label="Expires at" value={fixtureRepoExclusiveLock.expires_at} />
        <StatusValue label="Blocks execution preview" value={String(fixtureRepoExclusiveLock.blocks_execution_preview)} />
        <StatusValue label="Stale recovery preview" value={`${fixtureStaleCampaignLock.lock_status}; reason required=true`} />
        <StatusValue label="Active unlock refused" value={String(!fixtureRepoExclusiveLock.force_release_allowed)} />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true">
          Unlock stale preview
        </button>
        <button type="button" disabled aria-disabled="true">
          Unlock apply requires reason
        </button>
        <button type="button" disabled aria-disabled="true">
          Force unlock active refused
        </button>
        <button type="button" disabled aria-disabled="true">
          Start controls disabled
        </button>
      </div>
    </section>
  );
}

function CampaignPriorityQueuePanel() {
  return (
    <section className="panel campaign-priority-queue" aria-label="Campaign priority queue">
      <h2>Campaign Priority Queue</h2>
      <dl>
        <StatusValue label="One active campaign per project" value={String(fixtureCampaignPriorityQueue.one_active_campaign_per_project)} />
        <StatusValue label="Deterministic order" value={String(fixtureCampaignPriorityQueue.deterministic_order)} />
        <StatusValue label="Selected campaign" value={fixtureCampaignPriorityQueue.selection.selected_campaign_id ?? "none"} />
        <StatusValue label="Blocked reason" value={fixtureCampaignPriorityQueue.selection.blocked_campaign_reason ?? "none"} />
        <StatusValue label="Queue decision summary" value={fixtureCampaignPriorityQueue.selection.queue_decision_summary} />
        <StatusValue label="Execution side effects" value={String(fixtureCampaignPriorityQueue.selection.execution_side_effects)} />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <ul>
        {fixtureCampaignPriorityQueue.items.map((item) => (
          <li key={item.campaign_id}>
            {item.priority}: {item.campaign_id} {item.status} selected={String(item.selected)}
          </li>
        ))}
      </ul>
    </section>
  );
}

function AttentionPanel({ events }: { events: AttentionEvent[] }) {
  const top = events.find((event) => event.attention_level === "critical" || event.attention_level === "blocker" || event.attention_level === "action_required") ?? events[0];
  const routing = top ? routeAttentionEvent(top) : null;
  return (
    <section className="panel attention-panel" aria-label="Attention panel">
      <h2>Attention Panel</h2>
      <dl>
        <StatusValue label="Attention count" value={events.length} />
        <StatusValue label="Top item" value={top ? `${top.event_type}: ${top.message}` : "none"} />
        <StatusValue label="Recommended action" value={top?.recommended_action ?? "none"} />
        <StatusValue label="Worker offline" value={String(events.some((event) => event.event_type === "worker_offline"))} />
        <StatusValue label="Queue blocked" value={String(events.some((event) => event.event_type === "queue_blocked"))} />
        <StatusValue label="Safe notification status" value={(routing?.routes ?? []).map((route) => `${route.route}=${route.status}`).join("; ") || "none"} />
        <StatusValue label="External notification sent" value="false" />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <ul>
        {events.slice(0, 5).map((event) => (
          <li key={event.attention_event_id}>
            <strong>{event.attention_level}</strong> {event.event_type}: {event.recommended_action}
          </li>
        ))}
      </ul>
    </section>
  );
}

function WorkerServicePanel({
  service,
  readiness,
}: {
  service: WorkerServiceState;
  readiness: ReturnType<typeof createWorkerServiceReadiness>;
}) {
  const capabilities = service.capability_matrix;
  return (
    <section className="panel worker-service-panel" aria-label="Worker service panel">
      <h2>Worker Service Panel</h2>
      <dl>
        <StatusValue label="Worker service status" value={service.mode} />
        <StatusValue label="Worker id" value={service.worker_id} />
        <StatusValue label="Worker profile" value={service.worker_profile} />
        <StatusValue label="Heartbeat age" value={readiness.heartbeat_age_seconds === null ? "none" : `${readiness.heartbeat_age_seconds}s`} />
        <StatusValue label="Current task id" value={service.current_task_id ?? "none"} />
        <StatusValue label="Can claim tasks" value={String(readiness.can_claim_tasks)} />
        <StatusValue label="Can execute tasks" value={String(readiness.can_execute_tasks)} />
        <StatusValue label="Stop requested" value={String(service.stop_requested)} />
        <StatusValue label="Pause requested" value={String(service.pause_requested)} />
        <StatusValue label="Readiness blockers" value={readiness.blockers.join("; ") || "none"} />
        <StatusValue label="Recommended action" value={readiness.recommended_action} />
        <StatusValue label="token_printed" value="false" />
      </dl>
      <div className="capability-grid">
        <span>heartbeat={String(capabilities.heartbeat)}</span>
        <span>status={String(capabilities.status)}</span>
        <span>stop={String(capabilities.stop)}</span>
        <span>task_claim={String(capabilities.task_claim)}</span>
        <span>task_execute={String(capabilities.task_execute)}</span>
        <span>codex_execute={String(capabilities.codex_execute)}</span>
        <span>pr_create={String(capabilities.pr_create)}</span>
        <span>arbitrary_shell={String(capabilities.arbitrary_shell)}</span>
      </div>
      <div className="queue-action-grid">
        <button type="button" disabled aria-disabled="true" title="Preview only in this UI build">
          Start standby preview
        </button>
        <button type="button" disabled aria-disabled="true" title="Bounded local supervisor apply remains CLI-only and disabled during Goal 196 lock review">
          Start standby apply disabled
        </button>
        <button type="button" disabled aria-disabled="true" title="Heartbeat-only CLI smoke path; no task claim">
          Heartbeat only
        </button>
        <button type="button" disabled aria-disabled="true" title="Stop request is safe local metadata only">
          Stop standby
        </button>
        <button type="button" disabled aria-disabled="true">
          Claim task disabled
        </button>
        <button type="button" disabled aria-disabled="true">
          Execute task disabled
        </button>
      </div>
    </section>
  );
}

function formatKnownNumber(value: number | null) {
  return value === null ? "unknown" : value;
}

function formatAge(value: number) {
  return value < 0 ? "unknown" : `${value}s`;
}

function parseUnixTimestamp(value: string) {
  if (!value.startsWith("unix:")) {
    return null;
  }
  const parsed = Number.parseInt(value.slice("unix:".length), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function isFixtureMode() {
  const fixture = new URLSearchParams(window.location.search).get("fixture");
  return fixture === "desktop-pre190-pass" || fixture === "desktop-queue-dashboard" || fixture === "desktop-async-timeout-warning";
}

function containsSecretLookingText(text: string) {
  const patterns = [
    "sk-[A-Za-z0-9_-]{20,}",
    "gh[pousr]_[A-Za-z0-9_]{20,}",
    "authorization\\s*[:=]\\s*bearer",
    "bearer\\s+[A-Za-z0-9_.-]{12,}",
    "-----BEGIN [A-Z ]*" + "PRIVATE " + "KEY-----",
  ];
  return new RegExp(patterns.join("|"), "i").test(text);
}

createRoot(document.getElementById("root") as HTMLElement).render(<App />);
