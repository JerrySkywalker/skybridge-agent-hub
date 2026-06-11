import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ActiveRunsPanel,
  ApprovalQueuePanel,
  EventTimeline,
  NotificationList,
  ProviderStatusPanel,
  RunDetailPanel,
  SkyBridgeHealthCard,
  SourceFilterBar,
  type SourceFilters,
} from "@skybridge-agent-hub/react-widgets";
import {
  SkyBridgeClient,
  type AutoMergeSummary,
  type AuditEntry,
  type CampaignRunReport,
  createCampaignSafeSummary,
  createAttentionModel,
  createWorkerServiceReadiness,
  fixtureCampaignRunReport,
  fixtureCampaignLock,
  fixtureCampaignPriorityQueue,
  fixtureBoundedQueuePlan,
  fixtureBoundedQueueReadiness,
  fixtureBoincManagerState,
  fixtureManagedModeRepeatabilitySummary,
  fixtureManagedModeRunRegistry,
  fixtureOneAtATimeManagedModeGate,
  fixtureLocalExecutionGuard,
  fixtureLocalResourcePolicy,
  fixtureLocalWorkerSupervisorState,
  fixtureMultiWorkerReadiness,
  fixtureGoalQueueReviewSummary,
  fixtureProposedGoalReviewSummary,
  fixtureProjectProfileReviewSummary,
  fixtureQueueControlState,
  fixtureRepoExclusiveLock,
  fixtureSchedulingPreview,
  fixtureStaleCampaignLock,
  fixtureWorkunitCandidatePack,
  queueControlActionMatrix,
  routeAttentionEvent,
  summarizeCampaignEvidence,
  type AttentionEvent,
  type BoundedQueuePlan,
  type BoundedQueueReadiness,
  type BoincManagerState,
  type ManagedModeRepeatabilitySummary,
  type ManagedModeRunRegistry,
  type OneAtATimeManagedModeGate,
  type LocalExecutionGuard,
  type LocalResourcePolicy,
  type LocalWorkerSupervisorState,
  type MultiWorkerReadiness,
  type SchedulingPreview,
  type HermesSummary,
  type IterationsSummary,
  type NotificationsSummary,
  type PrsSummary,
  type GoalRecord,
  type ProjectSummary,
  type SummaryResponse,
  type TaskRecord,
  type TaskSummary,
  type WorkerRecord,
  type WorkerSummary,
  type ProposedGoalReviewSummary,
  type WorkunitCandidatePack,
} from "@skybridge-agent-hub/client";
import type {
  IterationRun,
  RunSummary,
  SkyBridgeEvent,
} from "@skybridge-agent-hub/event-schema";
import "./style.css";

type Route =
  | "overview"
  | "runs"
  | "iterations"
  | "campaign-queue"
  | "goals"
  | "workers"
  | "tasks"
  | "pr-ci"
  | "notifications"
  | "hermes"
  | "sources"
  | "audit"
  | "settings"
  | "embed";

const navItems: Array<{ route: Route; label: string }> = [
  { route: "overview", label: "Overview" },
  { route: "runs", label: "Runs" },
  { route: "iterations", label: "Iterations" },
  { route: "campaign-queue", label: "Campaign Queue" },
  { route: "goals", label: "Goals" },
  { route: "workers", label: "Worker Pool" },
  { route: "tasks", label: "Task Queue" },
  { route: "pr-ci", label: "PR/CI" },
  { route: "notifications", label: "Notifications" },
  { route: "hermes", label: "Hermes Adapter" },
  { route: "sources", label: "Sources/Audit" },
  { route: "settings", label: "Settings" },
];

function App() {
  const apiBase =
    import.meta.env.VITE_SKYBRIDGE_API_BASE || "http://127.0.0.1:8787";
  const route = useHashRoute();
  const [filters, setFilters] = useState<SourceFilters>({
    platform: "all",
    severity: "all",
    status: "all",
  });
  const [selectedRunId, setSelectedRunId] = useState<string | undefined>();

  if (route === "embed") {
    return (
      <main className="embed-page">
        <SkyBridgeHealthCard apiBase={apiBase} />
      </main>
    );
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <strong>SkyBridge</strong>
          <span>Agent Hub</span>
        </div>
        <nav className="sidebar-nav" aria-label="Operator Console">
          {navItems.map((item) => (
            <a
              key={item.route}
              className={route === item.route ? "is-active" : ""}
              href={`#/${item.route}`}
            >
              {item.label}
            </a>
          ))}
        </nav>
        <a className="sidebar-embed" href="#/embed/compact">
          Compact embed
        </a>
      </aside>

      <main className="page">
        <header className="topbar">
          <div>
            <p className="eyebrow">SkyBridge Agent Hub</p>
            <h1>{titleForRoute(route)}</h1>
          </div>
          <div className="topbar__meta">
            <code>{apiBase}</code>
          </div>
        </header>

        {route === "overview" ? <OverviewPage apiBase={apiBase} /> : null}
        {route === "runs" ? (
          <RunsPage
            apiBase={apiBase}
            filters={filters}
            onFilters={setFilters}
            selectedRunId={selectedRunId}
            onSelectRun={setSelectedRunId}
          />
        ) : null}
        {route === "iterations" ? <IterationsPage apiBase={apiBase} /> : null}
        {route === "campaign-queue" ? <CampaignQueuePage /> : null}
        {route === "goals" ? <GoalsPage apiBase={apiBase} /> : null}
        {route === "workers" ? <WorkerPoolPage apiBase={apiBase} /> : null}
        {route === "tasks" ? <TaskQueuePage apiBase={apiBase} /> : null}
        {route === "pr-ci" ? <PrCiPage apiBase={apiBase} /> : null}
        {route === "notifications" ? (
          <NotificationsPage apiBase={apiBase} />
        ) : null}
        {route === "hermes" ? <HermesPage apiBase={apiBase} /> : null}
        {route === "sources" ? <SourcesAuditPage apiBase={apiBase} /> : null}
        {route === "settings" ? <SettingsPage apiBase={apiBase} /> : null}
      </main>
    </div>
  );
}

function OverviewPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  const summary = data.summary;

  return (
    <div className="route-stack">
      <section className="hero-panel">
        <div>
          <h2>Daily operator picture</h2>
          <p>
            {summary?.latest?.next_recommended_action ??
              "Connect the server or seed demo data to populate the operator picture."}
          </p>
        </div>
        <span
          className={badgeClass(summary?.totals.attention_items ? "bad" : "ok")}
        >
          {summary?.totals.attention_items ?? 0} attention
        </span>
      </section>
      <section className="kpi-grid">
        <Kpi label="Health" value={summary?.health.ok ? "online" : "unknown"} />
        <Kpi label="Open PRs" value={summary?.totals.open_prs ?? 0} />
        <Kpi label="Latest CI" value={summary?.latest?.ci_state ?? "unknown"} />
        <Kpi
          label="Auto-merge blocked"
          value={summary?.totals.automerge_blocked ?? 0}
        />
        <Kpi
          label="Online workers"
          value={summary?.totals.workers_online ?? 0}
        />
        <Kpi
          label="Queued tasks"
          value={summary?.totals.tasks_queued ?? 0}
        />
        <Kpi
          label="Running tasks"
          value={summary?.totals.tasks_running ?? 0}
        />
        <Kpi
          label="Blocked tasks"
          value={summary?.totals.tasks_blocked ?? 0}
        />
        <Kpi
          label="Latest iteration"
          value={summary?.latest?.iteration?.state ?? "idle"}
        />
        <Kpi
          label="Active goals"
          value={summary?.totals.active_goals ?? 0}
        />
        <Kpi
          label="Planner adapters"
          value={
            data.adapters.filter((adapter) => adapter.role === "planner")
              .length || "unknown"
          }
        />
        <Kpi
          label="Latest notification"
          value={summary?.latest?.notification?.status ?? "none"}
        />
        <Kpi
          label="Recent failures"
          value={summary?.recent_failures?.length ?? 0}
        />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <SkyBridgeHealthCard apiBase={apiBase} />
          <FailureList failures={summary?.recent_failures ?? []} />
          <ProductTable
            title="Open PR/CI"
            rows={(data.prs?.prs ?? [])
              .slice(0, 6)
              .map((pr) => [
                `#${pr.pr_number}`,
                pr.ci_state,
                pr.eligibility,
                pr.reasons[0] ?? "no blocker",
              ])}
          />
        </div>
        <aside className="dashboard-grid__side">
          <SummaryCard
            title="Auto-merge"
            state={`${data.automerge?.eligible ?? 0} eligible`}
            lines={[
              `Dry-run default: ${data.automerge?.dry_run_default ? "yes" : "no"}`,
              `Blocked: ${data.automerge?.blocked ?? 0}`,
              `Latest sweep: ${data.automerge?.latest_sweep?.summary ?? "none"}`,
            ]}
          />
          <SummaryCard
          title="Adapter ring"
            state={`${data.adapters.length} adapters`}
            lines={[
              `Planner adapters: ${adapterLabels(data.adapters, "planner")}`,
              `Executor adapters: ${adapterLabels(data.adapters, "executor")}`,
              `Notification providers: ${adapterLabels(data.adapters, "notification_provider")}`,
            ]}
          />
          <SummaryCard
            title="Task queue"
            state={`${data.tasksSummary?.queued ?? 0} queued`}
            lines={[
              `Running: ${(data.tasksSummary?.running ?? 0) + (data.tasksSummary?.claimed ?? 0)}`,
              `Completed: ${data.tasksSummary?.completed ?? 0}`,
              `Latest event: ${data.tasksSummary?.latest_event?.type ?? "none"}`,
            ]}
          />
          <NotificationList apiBase={apiBase} />
        </aside>
      </section>
      {data.error ? <p className="skybridge-error">{data.error}</p> : null}
    </div>
  );
}

function CampaignQueuePage() {
  const report = fixtureCampaignRunReport;
  const evidence = summarizeCampaignEvidence(report);
  const readiness = report.queue_control_readiness;
  const remainingSteps = report.step_ledger.filter((step) => step.status === "pending");
  const safeSummary = createCampaignSafeSummary(report);
  const attention = createAttentionModel(report);
  const workerReadiness = createWorkerServiceReadiness(report.worker_service_state);
  const workunitPlan = report.workunit_preview_plan ?? fixtureBoundedQueuePlan;
  const boundedQueueReadiness = report.bounded_queue_readiness ?? fixtureBoundedQueueReadiness;

  return (
    <div className="route-stack campaign-queue" data-readonly-dashboard="true">
      <section className="hero-panel hero-panel--queue">
        <div>
          <h2>Campaign Queue</h2>
          <p>{readiness.next_safe_action}</p>
        </div>
        <span className={badgeClass(readiness.worker_status === "online" || readiness.worker_status === "ready" ? "ok" : "bad")}>
          worker {readiness.worker_status}
        </span>
      </section>

      <AttentionBanner events={attention.attention_events} />

      <section className="kpi-grid">
        <Kpi label="Campaign" value={report.campaign_id} />
        <Kpi label="Status" value={report.campaign_status} />
        <Kpi label="Current goal" value={report.current_goal_id} />
        <Kpi label="Remaining steps" value={remainingSteps.length} />
        <Kpi label="Attention" value={attention.attention_events.length} />
      </section>

      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <CampaignStepPanel
            title="Current Step"
            step={report.current_step_summary}
          />
          {report.previous_step_summary ? (
            <CampaignStepPanel
              title="Previous Completed Step"
              step={report.previous_step_summary}
            />
          ) : null}
          <CampaignStepLedger steps={report.step_ledger} />
        </div>
        <aside className="dashboard-grid__side">
          <AttentionFeed events={attention.attention_events} />
          <CampaignLockPanel />
          <CampaignPriorityQueuePanel />
          <ProjectProfileReviewPanel profile={fixtureProjectProfileReviewSummary} />
          <GoalQueueReviewPanel review={fixtureGoalQueueReviewSummary} />
          <BoincControlPlanePanel state={fixtureBoincManagerState} />
          <ManagedModeRunRegistryPanel
            registry={fixtureManagedModeRunRegistry}
            gate={fixtureOneAtATimeManagedModeGate}
            summary={fixtureManagedModeRepeatabilitySummary}
          />
          <ProposedGoalReviewPanel review={fixtureProposedGoalReviewSummary} />
          <ProposedGoalWorkunitPanel pack={fixtureWorkunitCandidatePack} />
          <WorkerReadinessPanel report={report} readiness={workerReadiness} />
          <WebLocalWorkerPolicyPanel
            supervisor={report.local_worker_supervisor_state ?? fixtureLocalWorkerSupervisorState}
            policy={report.local_resource_policy ?? fixtureLocalResourcePolicy}
            guard={report.local_execution_guard ?? fixtureLocalExecutionGuard}
          />
          <WebBoundedQueuePreviewPanel plan={workunitPlan} readiness={boundedQueueReadiness} />
          <WorkerSchedulingPreviewPanel preview={fixtureSchedulingPreview} readiness={fixtureMultiWorkerReadiness} />
          <WorkerRoutingPanel report={report} />
          <QueueReadinessPanel readiness={readiness} />
          <QueueSafeActionsPanel readiness={readiness} />
          <NotificationRoutingPanel events={attention.attention_events} />
          <SummaryCard
            title="Evidence ledger"
            state={`${evidence.total} entries`}
            lines={[
              `Present: ${evidence.present}`,
              `Recovered: ${evidence.recovered}`,
              `Missing: ${evidence.missing}`,
              `Skipped: ${evidence.skipped}`,
              `Not applicable: ${evidence.not_applicable}`,
            ]}
          />
          <SummaryCard
            title="Safe summary"
            state="copy-safe"
            lines={[
              `Campaign: ${safeSummary.campaign_id}`,
              `Current: ${safeSummary.current_goal_id}`,
              `Worker: ${safeSummary.worker_status}`,
              `Worker service: ${safeSummary.worker_service_mode}`,
              `Attention: ${safeSummary.attention_count}`,
              `Top blocker: ${safeSummary.top_blocker ?? "none"}`,
              `token_printed=${String(safeSummary.token_printed)}`,
            ]}
          />
        </aside>
      </section>
    </div>
  );
}

function BoincControlPlanePanel({ state }: { state: BoincManagerState }) {
  const surface = state.control_surface;
  return (
    <section className="skybridge-panel boinc-control-plane-panel" aria-label="BOINC control plane manager">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">BOINC Manager</p>
          <h2>Control Plane Preview</h2>
        </div>
        <span className={badgeClass(surface.current_mode.enabled ? "ok" : "bad")}>
          {surface.current_mode.display_name}
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Worker pool</dt>
          <dd>{`${state.local_worker_supervisor_state.worker_id}; claim=${String(state.local_worker_supervisor_state.can_claim_tasks)}; execute=${String(state.local_worker_supervisor_state.can_execute_tasks)}`}</dd>
        </div>
        <div>
          <dt>Workunit preview</dt>
          <dd>{`${state.workunit_preview_plan.workunits.length} workunit; would_execute=${String(state.workunit_preview_plan.would_execute_tasks)}`}</dd>
        </div>
        <div>
          <dt>Bounded queue readiness</dt>
          <dd>{`can_start_bounded_queue=${String(state.bounded_queue_readiness.can_start_bounded_queue)}; apply=${String(state.bounded_queue_readiness.start_bounded_queue_apply_available)}`}</dd>
        </div>
        <div>
          <dt>Review holds</dt>
          <dd>{state.active_holds.map((hold) => hold.title).join("; ") || "none"}</dd>
        </div>
        <div>
          <dt>Task PR / finalizer</dt>
          <dd>{`${surface.completed_bootstrap_trial.task_pr_url}; ${surface.completed_bootstrap_trial.final_state}`}</dd>
        </div>
        <div>
          <dt>Next safe action</dt>
          <dd>{state.next_safe_action}</dd>
        </div>
      </dl>
      <QueueList
        title="Allowed actions"
        items={surface.action_matrix.allowed.map((action) => action.action)}
        fallback="No allowed actions."
      />
      <QueueList
        title="Disabled execution actions"
        items={surface.action_matrix.disabled.map((action) => `${action.action}: ${action.reason_disabled}`)}
        fallback="No disabled actions."
      />
      <div className="queue-placeholder-controls">
        {surface.action_matrix.disabled.slice(0, 4).map((action) => (
          <button key={action.action} type="button" disabled aria-disabled="true" title={action.reason_disabled ?? "disabled"}>
            {action.display_name} disabled
          </button>
        ))}
      </div>
      <span>token_printed=false</span>
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
    <section className="skybridge-panel managed-mode-run-registry-panel" aria-label="Repeatable Managed Mode run registry">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Repeatable Managed Mode</p>
          <h2>Run Registry</h2>
        </div>
        <span className={badgeClass(summary.open_run_count > 0 ? "bad" : "ok")}>
          {summary.next_mode}
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>completed runs</dt>
          <dd>{registry.completed_runs.map((run) => `${run.run_id}:${run.state}`).join("; ") || "none"}</dd>
        </div>
        <div>
          <dt>Next run preview</dt>
          <dd>{`${gate.run_id}; workunits=${String(gate.selected_workunit_count ?? 0)}; worker=${gate.selected_worker_id ?? "none"}`}</dd>
        </div>
        <div>
          <dt>Open hold status</dt>
          <dd>{`open_runs=${summary.open_run_count}; open_prs=${summary.open_managed_mode_pr_count}; active_tasks=${summary.active_tasks}; stale_leases=${summary.stale_leases}; runner_lock=${summary.runner_lock}`}</dd>
        </div>
        <div>
          <dt>Apply disabled reason</dt>
          <dd>{summary.apply_disabled_reason}</dd>
        </div>
        <div>
          <dt>Next safe action</dt>
          <dd>{summary.next_safe_action}</dd>
        </div>
      </dl>
      <QueueList
        title="Sequence policy"
        items={[
          `max_open_runs=${registry.sequence_policy.max_open_runs}`,
          `max_workunits_per_run=${registry.sequence_policy.max_workunits_per_run}`,
          `max_tasks_per_run=${registry.sequence_policy.max_tasks_per_run}`,
          `max_claims_per_run=${registry.sequence_policy.max_claims_per_run}`,
          `max_codex_executions_per_run=${registry.sequence_policy.max_codex_executions_per_run}`,
          `max_prs_per_run=${registry.sequence_policy.max_prs_per_run}`,
          `general_bounded_queue_apply_enabled=${String(registry.sequence_policy.general_bounded_queue_apply_enabled)}`,
          `one_at_a_time_run_apply_enabled=${String(registry.sequence_policy.one_at_a_time_run_apply_enabled)}`,
        ]}
        fallback="No sequence policy."
      />
      <p className="skybridge-state-note">Read-only registry panel: no active execution buttons are exposed. token_printed=false</p>
    </section>
  );
}

function CampaignLockPanel() {
  return (
    <section className="skybridge-panel campaign-lock-review" aria-label="Campaign and repo lock review">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Lock Review</p>
          <h2>Campaign / Repo Locks</h2>
        </div>
        <span className={badgeClass(fixtureRepoExclusiveLock.blocks_execution_preview ? "bad" : "ok")}>
          {fixtureRepoExclusiveLock.lock_status}
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Campaign lock</dt>
          <dd>{fixtureCampaignLock.lock_status}</dd>
        </div>
        <div>
          <dt>Repo exclusive lock</dt>
          <dd>{fixtureRepoExclusiveLock.repo_id}</dd>
        </div>
        <div>
          <dt>Lock owner</dt>
          <dd>{fixtureRepoExclusiveLock.lock_owner.display_name}</dd>
        </div>
        <div>
          <dt>Heartbeat age</dt>
          <dd>{fixtureRepoExclusiveLock.age_seconds}s</dd>
        </div>
        <div>
          <dt>Expires at</dt>
          <dd>{fixtureRepoExclusiveLock.expires_at}</dd>
        </div>
        <div>
          <dt>Stale recovery preview</dt>
          <dd>{fixtureStaleCampaignLock.lock_status}; reason required=true</dd>
        </div>
      </dl>
      <QueueList
        title="Recovery guidance"
        items={[
          "active repo locks block start previews",
          "stale unlock apply requires operator reason",
          "active non-stale lock force release is refused",
          "token_printed=false",
        ]}
        fallback="No lock guidance."
      />
      <p className="skybridge-state-note">No execution controls are exposed on Web lock review.</p>
    </section>
  );
}

function CampaignPriorityQueuePanel() {
  return (
    <section className="skybridge-panel campaign-priority-queue" aria-label="Campaign priority queue">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Multi-campaign Queue</p>
          <h2>Priority Selection</h2>
        </div>
        <span className={badgeClass(fixtureCampaignPriorityQueue.selection.decision === "select" ? "ok" : "bad")}>
          {fixtureCampaignPriorityQueue.selection.decision}
        </span>
      </div>
      <QueueList
        title="Campaign order"
        items={fixtureCampaignPriorityQueue.items.map(
          (item) => `${item.priority}: ${item.campaign_id} ${item.status} selected=${item.selected} blocked=${item.blocked_reason ?? "none"}`,
        )}
        fallback="No campaigns."
      />
      <QueueList
        title="Selection preview"
        items={[
          `selected=${fixtureCampaignPriorityQueue.selection.selected_campaign_id}`,
          `blocked=${fixtureCampaignPriorityQueue.selection.blocked_campaign_reason}`,
          fixtureCampaignPriorityQueue.selection.queue_decision_summary,
          `execution_side_effects=${fixtureCampaignPriorityQueue.selection.execution_side_effects}`,
        ]}
        fallback="No selection preview."
      />
    </section>
  );
}

function GoalQueueReviewPanel({
  review,
}: {
  review: typeof fixtureGoalQueueReviewSummary;
}) {
  return (
    <section className="skybridge-panel goal-queue-review" aria-label="Manual goal queue review">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Goal Pack Review</p>
          <h2>Manual Queue Authoring</h2>
        </div>
        <span className={badgeClass(review.validation_result === "pass" ? "ok" : "bad")}>
          {review.validation_result}
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Goal pack id</dt>
          <dd>{review.goal_pack_id}</dd>
        </div>
        <div>
          <dt>Current pack hash</dt>
          <dd>{review.current_campaign_pack_hash}</dd>
        </div>
        <div>
          <dt>Hash drift</dt>
          <dd>{review.hash_drift_count}</dd>
        </div>
        <div>
          <dt>Dependency/order</dt>
          <dd>{review.dependency_order_status}</dd>
        </div>
        <div>
          <dt>Proposed action</dt>
          <dd>{review.proposed_import_update_action}</dd>
        </div>
      </dl>
      <QueueList title="Validation errors" items={review.validation_errors} fallback="No validation errors." />
      <QueueList title="Validation warnings" items={review.validation_warnings} fallback="No validation warnings." />
      <QueueList
        title="Re-import preview"
        items={[
          `added=${review.reimport_preview_summary.added_goals}`,
          `removed=${review.reimport_preview_summary.removed_goals}`,
          `changed=${review.reimport_preview_summary.changed_goals}`,
          `dependency_changes=${review.reimport_preview_summary.dependency_changes}`,
          `order_changes=${review.reimport_preview_summary.order_changes}`,
          `safety_policy_changes=${review.reimport_preview_summary.safety_policy_changes}`,
          `update_safe=${review.reimport_preview_summary.update_safe}`,
        ]}
        fallback="No re-import preview."
      />
      <QueueList
        title="Archive preview"
        items={[
          `target=${review.archive_preview_summary.archive_target}`,
          `would_archive=${review.archive_preview_summary.would_archive}`,
          `excludes_raw_logs_and_secrets=${review.archive_preview_summary.excludes_raw_logs_and_secrets}`,
        ]}
        fallback="No archive preview."
      />
      <p className="skybridge-state-note">No execution controls are available on this review surface.</p>
      <span>token_printed=false</span>
    </section>
  );
}

function ProposedGoalReviewPanel({
  review,
}: {
  review: ProposedGoalReviewSummary;
}) {
  return (
    <section className="skybridge-panel proposed-goal-review" aria-label="Proposed goal review">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Proposed Goals</p>
          <h2>Review-Only Intake</h2>
        </div>
        <span className={badgeClass(review.blocked_draft_count > 0 ? "bad" : "ok")}>
          {review.pending_review_count} review
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Proposed goals</dt>
          <dd>{review.proposed_goal_count}</dd>
        </div>
        <div>
          <dt>Pending review</dt>
          <dd>{review.pending_review_count}</dd>
        </div>
        <div>
          <dt>Blocked drafts</dt>
          <dd>{review.blocked_draft_count}</dd>
        </div>
        <div>
          <dt>Next action</dt>
          <dd>{review.next_action}</dd>
        </div>
        <div>
          <dt>Import requires Goal 200</dt>
          <dd>{String(review.import_requires_goal_200)}</dd>
        </div>
      </dl>
      <QueueList
        title="Drafts"
        items={review.proposed_goals.map(
          (goal) =>
            `${goal.proposed_goal_id}: ${goal.safety_classification}; ${goal.review_status}; ${goal.proposed_markdown_path}; hash=${goal.content_hash.slice(0, 12)}; reviewer=${goal.reviewer ?? "none"}; decision=${goal.decision ?? "pending"}; import=${goal.import_status ?? "not_imported"}; target=${goal.import_target ?? "none"}; deps=${goal.suggested_dependencies.join(", ") || "none"}; blocked=${goal.blocked_reasons.join(", ") || "none"}`,
        )}
        fallback="No proposed goals."
      />
      <QueueList
        title="Controlled Review / Import"
        items={[
          `Approve preview=${review.review_controls.approve_preview}`,
          `Reject preview=${review.review_controls.reject_preview}`,
          `Edit staged=${review.review_controls.edit_staged}`,
          `Import preview=${review.review_controls.import_preview}`,
          `Import apply disabled=${review.review_controls.import_apply}`,
          `reason-gated=${review.review_controls.approve_preview}`,
          `execution review required=${review.import_preview_summary.execution_review_required}`,
        ]}
        fallback="No review controls."
      />
      <QueueList
        title="manifest diff"
        items={[
          `target=${review.import_preview_summary.target_path}`,
          ...review.import_preview_summary.manifest_diff,
          ...review.import_preview_summary.dependency_order_changes,
          ...review.import_preview_summary.hash_changes,
          ...review.import_preview_summary.validation_blockers,
        ]}
        fallback="No manifest diff."
      />
      <p className="skybridge-state-note">No import or execute controls: no execute button, no start queue button and no imported-goal execution controls are exposed on proposed-goal review.</p>
      <span>token_printed=false</span>
    </section>
  );
}

function ProposedGoalWorkunitPanel({ pack }: { pack: WorkunitCandidatePack }) {
  return (
    <section className="skybridge-panel proposed-goal-workunit-panel" aria-label="Proposed Goal Workunit Candidate panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Goal to Workunit</p>
          <h2>Candidate Pipeline</h2>
        </div>
        <span className={badgeClass(pack.apply_available ? "ok" : "bad")}>execution disabled</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Candidate pack</dt>
          <dd>{pack.candidate_pack_id}</dd>
        </div>
        <div>
          <dt>Candidates</dt>
          <dd>{`${pack.candidates.length}; ready=${pack.candidate_ready_count}; blocked=${pack.blocked_count}`}</dd>
        </div>
        <div>
          <dt>Risk gate</dt>
          <dd>{pack.risk_gates.map((gate) => `${gate.candidate_id}:${gate.decision}`).join("; ")}</dd>
        </div>
        <div>
          <dt>Bounded queue state</dt>
          <dd>{`preview_only=${String(pack.bounded_queue_preview_only)}; apply=${String(pack.apply_available)}`}</dd>
        </div>
        <div>
          <dt>Next safe action</dt>
          <dd>{pack.next_safe_action}</dd>
        </div>
        <div>
          <dt>token_printed</dt>
          <dd>{String(pack.token_printed)}</dd>
        </div>
      </dl>
      <QueueList
        title="Candidate list"
        items={pack.candidates.map(
          (candidate) =>
            `${candidate.candidate_id}: ${candidate.conversion_status}; risk=${candidate.risk}; workunit=${candidate.suggested_workunit_id}; source=${candidate.source_goal_path}; blockers=${candidate.blockers.join(", ") || "none"}`,
        )}
        fallback="No candidates."
      />
      <QueueList
        title="Disabled execution"
        items={[
          "candidate_execution_disabled",
          "no task creation",
          "no worker claim",
          "bounded queue apply disabled",
          "execution review required",
        ]}
        fallback="Execution controls unavailable."
      />
    </section>
  );
}

function ProjectProfileReviewPanel({
  profile,
}: {
  profile: typeof fixtureProjectProfileReviewSummary;
}) {
  return (
    <section className="skybridge-panel project-profile-review" aria-label="Project profile review">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Project Profile Review</p>
          <h2>{profile.display_name}</h2>
        </div>
        <span className={badgeClass(profile.validation_status === "valid" ? "ok" : "bad")}>
          {profile.validation_status}
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Selected project</dt>
          <dd>{profile.project_id}</dd>
        </div>
        <div>
          <dt>Profile hash</dt>
          <dd>{profile.profile_hash}</dd>
        </div>
        <div>
          <dt>Repo identity</dt>
          <dd>{profile.repo_identity}</dd>
        </div>
        <div>
          <dt>Repo path</dt>
          <dd>{profile.repo_path_display}</dd>
        </div>
        <div>
          <dt>Default branch</dt>
          <dd>{profile.default_branch}</dd>
        </div>
        <div>
          <dt>Worker profile</dt>
          <dd>{profile.worker_profile_summary.default_worker_profile}</dd>
        </div>
        <div>
          <dt>Goal pack</dt>
          <dd>{profile.goal_pack_summary.default_goal_pack_dir}</dd>
        </div>
      </dl>
      <QueueList title="Allowed paths" items={profile.allowed_paths} fallback="No allowed paths." />
      <QueueList title="Blocked paths" items={profile.blocked_paths} fallback="No blocked paths." />
      <QueueList
        title="Validation commands"
        items={profile.validation_commands.map((command) => `${command.id}: ${command.command}; executes=${command.executes}`)}
        fallback="No validation commands."
      />
      <QueueList
        title="Policy summary"
        items={[
          `dry_run_default=${profile.policy_summary.dry_run_default}`,
          `selection_preview_only=${profile.policy_summary.selection_preview_only}`,
          `forbid_arbitrary_shell=${profile.policy_summary.forbid_arbitrary_shell}`,
          `forbid_secret_fields=${profile.policy_summary.forbid_secret_fields}`,
          `forbid_production_paths=${profile.policy_summary.forbid_production_paths}`,
        ]}
        fallback="No policy summary."
      />
      <p className="skybridge-state-note">No execution controls are available on this project profile review surface.</p>
      <span>token_printed=false</span>
    </section>
  );
}

function AttentionBanner({ events }: { events: AttentionEvent[] }) {
  const top = events.find((event) => event.attention_level === "critical" || event.attention_level === "blocker" || event.attention_level === "action_required") ?? events[0];
  if (!top) return null;
  return (
    <section className="attention-banner" aria-label="Attention required">
      <div>
        <p className="skybridge-kicker">Attention Loop</p>
        <h2>{top.event_type}</h2>
        <p>{top.message}</p>
        <small>{top.recommended_action}</small>
      </div>
      <span className={badgeClass(top.attention_level === "info" ? "ok" : "bad")}>
        {top.attention_level}
      </span>
    </section>
  );
}

function AttentionFeed({ events }: { events: AttentionEvent[] }) {
  return (
    <section className="skybridge-panel attention-feed" aria-label="Attention feed">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Attention</p>
          <h2>Action Items</h2>
        </div>
        <span className={badgeClass(events.length ? "bad" : "ok")}>{events.length} items</span>
      </div>
      <ul className="summary-lines">
        {events.slice(0, 6).map((event) => (
          <li key={event.attention_event_id}>
            <strong>{event.event_type}</strong>
            <span>{event.message}</span>
            <small>{event.recommended_action}</small>
          </li>
        ))}
      </ul>
    </section>
  );
}

function NotificationRoutingPanel({ events }: { events: AttentionEvent[] }) {
  const top = events[0];
  const decision = top ? routeAttentionEvent(top) : null;
  return (
    <section className="skybridge-panel attention-routing" aria-label="Notification routing status">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Notification Routing</p>
          <h2>Fixture Matrix</h2>
        </div>
        <span className="skybridge-state">no external send</span>
      </div>
      <QueueList
        title="Routes"
        items={(decision?.routes ?? []).map((route) => `${route.route}: ${route.status}`)}
        fallback="No route selected."
      />
      <p className="skybridge-state-note">ntfy placeholder is disabled/not configured by default; local fixture ledger is explicit only.</p>
      <span>token_printed=false</span>
    </section>
  );
}

function WorkerReadinessPanel({
  report,
  readiness,
}: {
  report: CampaignRunReport;
  readiness: ReturnType<typeof createWorkerServiceReadiness>;
}) {
  const service = report.worker_service_state;
  const capabilities = service.capability_matrix;
  return (
    <section className="skybridge-panel worker-readiness" aria-label="Worker readiness panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Worker Service</p>
          <h2>Readiness</h2>
        </div>
        <span className={badgeClass(readiness.blockers.length ? "bad" : "ok")}>
          {service.mode}
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Worker id</dt>
          <dd>{service.worker_id}</dd>
        </div>
        <div>
          <dt>Heartbeat age</dt>
          <dd>{readiness.heartbeat_age_seconds === null ? "none" : `${readiness.heartbeat_age_seconds}s`}</dd>
        </div>
        <div>
          <dt>Current task</dt>
          <dd>{service.current_task_id ?? "none"}</dd>
        </div>
        <div>
          <dt>Can claim</dt>
          <dd>{String(readiness.can_claim_tasks)}</dd>
        </div>
      </dl>
      <QueueList
        title="Capability"
        items={[
          `heartbeat=${capabilities.heartbeat}`,
          `status=${capabilities.status}`,
          `stop=${capabilities.stop}`,
          `task_claim=${capabilities.task_claim}`,
          `task_execute=${capabilities.task_execute}`,
          `codex_execute=${capabilities.codex_execute}`,
          `pr_create=${capabilities.pr_create}`,
          `arbitrary_shell=${capabilities.arbitrary_shell}`,
        ]}
        fallback="No capability data."
      />
      <QueueList title="Readiness blockers" items={readiness.blockers} fallback="No worker service blockers." />
      <p className="skybridge-state-note">Web has no direct local process control; Start One remains disabled until a later reviewed execution gate.</p>
      <span>token_printed=false</span>
    </section>
  );
}

function WebLocalWorkerPolicyPanel({
  supervisor,
  policy,
  guard,
}: {
  supervisor: LocalWorkerSupervisorState;
  policy: LocalResourcePolicy;
  guard: LocalExecutionGuard;
}) {
  return (
    <section className="skybridge-panel web-local-worker-policy" aria-label="Web local worker policy panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Local Worker</p>
          <h2>Resident Policy</h2>
        </div>
        <span className={badgeClass(guard.execution_disabled ? "bad" : "ok")}>preview only</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Supervisor</dt>
          <dd>{`${supervisor.worker_id}; ${supervisor.worker_service_mode}`}</dd>
        </div>
        <div>
          <dt>Claim / execute</dt>
          <dd>{`${String(supervisor.can_claim_tasks)} / ${String(supervisor.can_execute_tasks)}`}</dd>
        </div>
        <div>
          <dt>Policy</dt>
          <dd>{`${policy.enforcement_status}; ac=${String(policy.require_ac_power)}; battery=${String(policy.pause_on_battery)}`}</dd>
        </div>
        <div>
          <dt>Limits</dt>
          <dd>{`cpu=${policy.max_cpu_percent}%; memory=${policy.max_memory_percent}%; hours=${policy.allowed_hours}`}</dd>
        </div>
        <div>
          <dt>Execution guard</dt>
          <dd>{guard.next_safe_action}</dd>
        </div>
      </dl>
      <QueueList title="Readiness blockers" items={supervisor.readiness_blockers} fallback="No local worker blockers." />
      <p className="skybridge-state-note">Web policy summary is read-only; local execution controls remain disabled.</p>
      <span>token_printed=false</span>
    </section>
  );
}

function WebBoundedQueuePreviewPanel({
  plan,
  readiness,
}: {
  plan: BoundedQueuePlan;
  readiness: BoundedQueueReadiness;
}) {
  const first = plan.workunits[0];
  return (
    <section className="skybridge-panel web-bounded-queue-preview" aria-label="Web bounded queue preview panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Workunit</p>
          <h2>Bounded Queue Preview</h2>
        </div>
        <span className={badgeClass(readiness.can_start_bounded_queue ? "ok" : "bad")}>apply disabled</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Plan</dt>
          <dd>{`${plan.plan_id}; ${plan.mode}`}</dd>
        </div>
        <div>
          <dt>Bootstrap workunit</dt>
          <dd>{`${first?.workunit_id ?? "none"}; state=${first?.state ?? "none"}`}</dd>
        </div>
        <div>
          <dt>Mutation</dt>
          <dd>{`no_mutation=${String(plan.no_mutation)}; tasks=${String(plan.would_create_tasks)}; claims=${String(plan.would_claim_tasks)}; execution=${String(plan.would_execute_tasks)}`}</dd>
        </div>
        <div>
          <dt>PR / runner</dt>
          <dd>{`prs=${String(plan.would_create_prs)}; runner=${String(plan.would_start_runner)}`}</dd>
        </div>
        <div>
          <dt>Readiness</dt>
          <dd>{`can_start_bounded_queue=${String(readiness.can_start_bounded_queue)}; apply=${String(readiness.start_bounded_queue_apply_available)}`}</dd>
        </div>
      </dl>
      <QueueList title="Bounded queue blockers" items={readiness.blockers} fallback="No bounded queue blockers." />
      <p className="skybridge-state-note">Preview only: no task creation, no task claim, no execution, no PR creation, bounded queue apply disabled.</p>
      <span>token_printed=false</span>
    </section>
  );
}

function CampaignStepPanel({
  title,
  step,
}: {
  title: string;
  step: CampaignRunReport["current_step_summary"];
}) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Campaign</p>
          <h2>{title}</h2>
        </div>
        <span className={badgeClass(step.status === "completed" || step.status === "ready" ? "ok" : "bad")}>
          {step.status}
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Goal</dt>
          <dd>{step.goal_id}</dd>
        </div>
        <div>
          <dt>Step</dt>
          <dd>{step.campaign_step_id}</dd>
        </div>
        <div>
          <dt>Evidence</dt>
          <dd>{step.evidence_status}</dd>
        </div>
        <div>
          <dt>Links</dt>
          <dd>{step.linked_task_count} task / {step.linked_pr_count} PR</dd>
        </div>
      </dl>
    </section>
  );
}

function CampaignStepLedger({
  steps,
}: {
  steps: CampaignRunReport["step_ledger"];
}) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Queue</p>
          <h2>Step Ledger</h2>
        </div>
        <span className="skybridge-state">{steps.length} steps</span>
      </div>
      <div className="data-table data-table--campaign">
        <div className="data-table__head">
          <span>Order</span>
          <span>Goal</span>
          <span>Status</span>
          <span>Evidence</span>
        </div>
        {steps.map((step) => (
          <div className="data-table__row" key={step.campaign_step_id}>
            <span>{step.order}</span>
            <span>
              {step.title}
              <small>{step.goal_id}</small>
            </span>
            <span>{step.is_current ? `${step.status} current` : step.status}</span>
            <span>{step.evidence_status}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function WorkerSchedulingPreviewPanel({
  preview,
  readiness,
}: {
  preview: SchedulingPreview;
  readiness: MultiWorkerReadiness;
}) {
  return (
    <section className="skybridge-panel worker-scheduling-preview-panel" aria-label="Worker distribution scheduling preview">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Multi-worker</p>
          <h2>Scheduling Preview</h2>
        </div>
        <span className={badgeClass(preview.apply_available ? "bad" : "ok")}>apply disabled</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Worker readiness</dt>
          <dd>{`total=${readiness.worker_pool_count}; ready_preview_only=${readiness.ready_preview_only_count}; stale=${readiness.stale_count}; disabled=${readiness.disabled_count}`}</dd>
        </div>
        <div>
          <dt>Worker groups</dt>
          <dd>{preview.worker_pool.groups.join("; ")}</dd>
        </div>
        <div>
          <dt>Route plan</dt>
          <dd>{`${preview.route_plan.plan_id}; routes=${preview.route_plan.selected_routes.length}`}</dd>
        </div>
        <div>
          <dt>Repo policy</dt>
          <dd>{`max_parallel_per_repo=${preview.repo_parallelism_policy.max_parallel_per_repo}; mutating_serialized=${String(preview.repo_parallelism_policy.mutating_work_serialized)}`}</dd>
        </div>
        <div>
          <dt>No claim/lease/execution</dt>
          <dd>{`task_claimed=${String(preview.task_claimed)}; lease_created=${String(preview.lease_created)}; task_executed=${String(preview.task_executed)}`}</dd>
        </div>
      </dl>
      <QueueList
        title="Selected routes"
        items={preview.route_plan.selected_routes.map((route) => `${route.queue_order}: ${route.workunit_id}->${route.selected_worker_id ?? "none"} serialized=${route.serialized_by_repo_policy}`)}
        fallback="No selected routes."
      />
      <QueueList
        title="Blockers and attention"
        items={[...readiness.blockers, ...readiness.attention_events]}
        fallback="No blockers."
      />
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Scheduling apply disabled</button>
        <button type="button" disabled aria-disabled="true">Worker claim disabled</button>
        <button type="button" disabled aria-disabled="true">Lease creation disabled</button>
        <button type="button" disabled aria-disabled="true">Execution disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WorkerRoutingPanel({ report }: { report: CampaignRunReport }) {
  const routing = report.queue_control_readiness.routing_readiness;
  const preview = routing?.route_preview;
  return (
    <section className="skybridge-panel worker-routing" aria-label="Multi-worker routing preview">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Multi-worker Routing</p>
          <h2>Preview Policy</h2>
        </div>
        <span className={badgeClass(preview?.selected_worker ? "ok" : "bad")}>
          preview only
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Pool counts</dt>
          <dd>{routing ? `total=${routing.worker_pool_counts.total}; online=${routing.worker_pool_counts.online}; stale=${routing.worker_pool_counts.stale}; offline=${routing.worker_pool_counts.offline}; disabled=${routing.worker_pool_counts.disabled}; busy=${routing.worker_pool_counts.busy}` : "unavailable"}</dd>
        </div>
        <div>
          <dt>Selected preview</dt>
          <dd>{preview?.selected_worker?.worker_label ?? "none"}</dd>
        </div>
        <div>
          <dt>Project profile hash</dt>
          <dd>{preview?.task.project_profile_hash ?? "none"}</dd>
        </div>
        <div>
          <dt>Project selection</dt>
          <dd>{preview?.task.project_selection_preview_only ? "preview only" : "unavailable"}</dd>
        </div>
        <div>
          <dt>Repo max parallel</dt>
          <dd>{preview ? `${preview.repo_parallelism_guard.max_parallel_per_repo}; blocked=${preview.repo_parallelism_guard.blocked}; ${preview.repo_parallelism_guard.blocker ?? "none"}` : "1"}</dd>
        </div>
        <div>
          <dt>No execution</dt>
          <dd>{`task_claimed=${String(preview?.task_claimed ?? false)}; task_executed=${String(preview?.task_executed ?? false)}; worker_loop_started=${String(preview?.worker_loop_started ?? false)}`}</dd>
        </div>
      </dl>
      <QueueList
        title="Capability matrix"
        items={(routing?.worker_capability_matrix ?? []).map((worker) => `${worker.worker_label}: ${worker.os}; tools=${worker.tools.join(", ")}; task_types=${worker.task_type_capabilities.join(", ")}`)}
        fallback="No worker capability matrix."
      />
      <QueueList
        title="Rejected workers"
        items={(preview?.rejected_workers ?? []).map((worker) => `${worker.worker_label}: ${worker.rejection_reasons.join(", ") || "none"}`)}
        fallback="No rejected workers."
      />
      <p className="skybridge-state-note">Execution controls remain disabled; this route preview does not claim tasks.</p>
    </section>
  );
}

function QueueReadinessPanel({
  readiness,
}: {
  readiness: CampaignRunReport["queue_control_readiness"];
}) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Queue Control Readiness</p>
          <h2>Read-only Gate</h2>
        </div>
        <span className={badgeClass(readiness.blockers.length ? "bad" : "ok")}>
          {readiness.blockers.length ? "blocked" : "ready"}
        </span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>can_start_one</dt>
          <dd>{String(readiness.can_start_one)}</dd>
        </div>
        <div>
          <dt>can_start_queue</dt>
          <dd>{String(readiness.can_start_queue)}</dd>
        </div>
        <div>
          <dt>can_resume</dt>
          <dd>{String(readiness.can_resume)}</dd>
        </div>
        <div>
          <dt>Worker status</dt>
          <dd>{readiness.worker_status}</dd>
        </div>
      </dl>
      <QueueList title="Blockers" items={readiness.blockers} fallback="No current blockers." />
      <QueueList title="Warnings" items={readiness.warnings} fallback="No warnings." />
      <QueueList title="Required human action" items={readiness.required_human_action} fallback="No required action." />
    </section>
  );
}

function QueueSafeActionsPanel({
  readiness,
}: {
  readiness: CampaignRunReport["queue_control_readiness"];
}) {
  const previewActions = queueControlActionMatrix.filter((entry) =>
    entry.class === "preview"
  );
  const forbiddenActions = queueControlActionMatrix.filter((entry) =>
    entry.class === "armed_execution" || entry.class === "forbidden"
  );
  return (
    <section className="skybridge-panel queue-placeholder-controls" aria-label="Safe Actions / Queue Controls">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Safe Actions / Queue Controls</p>
          <h2>Contract Preview</h2>
        </div>
      </div>
      <label className="reason-field">
        <span>Reason required for mutations</span>
        <input type="text" value="operator reason required before apply" readOnly />
      </label>
      <button type="button">
        Refresh
      </button>
      <button type="button">
        Report
      </button>
      <button type="button">
        Copy Safe Summary
      </button>
      <button type="button" disabled aria-disabled="true" title="Requires reason and confirmation on apply path">
        Safe Pause
      </button>
      <button type="button" disabled aria-disabled="true" title="Requires reason and confirmation on apply path">
        Stop Queue
      </button>
      <button type="button" disabled aria-disabled="true" title="Requires reason and confirmation on apply path">
        Emergency Stop
      </button>
      {previewActions.map((entry) => (
        <button type="button" key={entry.action}>
          {entry.action.replace(/_/g, " ")}
        </button>
      ))}
      <button type="button" disabled aria-disabled="true">
        Start One Apply disabled
      </button>
      <span>Start One disabled</span>
      <button type="button" disabled aria-disabled="true">
        Start Queue Apply disabled
      </button>
      <span>Start Queue disabled</span>
      <span>Resume disabled</span>
      <button type="button" disabled aria-disabled="true">
        Start All disabled
      </button>
      <button type="button" disabled aria-disabled="true">
        Worker Loop disabled
      </button>
      <span>worker_offline blocker: {String(readiness.blockers.includes("worker_offline"))}</span>
      <span>state_hash: {fixtureQueueControlState.state_hash}</span>
      <span>token_printed=false</span>
      <span>start_one_preview start_queue_preview resume_preview</span>
      <span>Audit result appears after safe action apply.</span>
      <span>Start actions disabled because worker is {readiness.worker_status} and execution apply is deferred until worker service mode.</span>
      <QueueList
        title="Forbidden"
        items={forbiddenActions.map((entry) => `${entry.action}: ${entry.blockers.join(",")}`)}
        fallback="No forbidden actions."
      />
    </section>
  );
}

function QueueList({
  title,
  items,
  fallback,
}: {
  title: string;
  items: string[];
  fallback: string;
}) {
  return (
    <div className="queue-list">
      <strong>{title}</strong>
      {items.length === 0 ? <p>{fallback}</p> : null}
      {items.length > 0 ? (
        <ul>
          {items.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

function WorkerPoolPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Online" value={data.workersSummary?.online ?? 0} />
        <Kpi label="Stale" value={data.workersSummary?.stale ?? 0} />
        <Kpi label="Offline" value={data.workersSummary?.offline ?? 0} />
        <Kpi label="Disabled" value={data.workersSummary?.disabled ?? 0} />
      </section>
      <LoopControlPanel projects={data.projects} tasks={data.tasks} />
      <WorkerTable workers={data.workers} tasks={data.tasks} />
    </div>
  );
}

function GoalsPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Goals" value={data.goals.length} />
        <Kpi label="Active" value={data.goals.filter((goal) => goal.status === "active").length} />
        <Kpi label="Ready" value={data.goals.filter((goal) => goal.status === "ready").length} />
        <Kpi label="Evidence" value={data.goals.reduce((sum, goal) => sum + (goal.task_summary?.evidence_count ?? 0), 0)} />
      </section>
      <GoalTable goals={data.goals} projects={data.projects} />
    </div>
  );
}

function TaskQueuePage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Queued" value={data.tasksSummary?.queued ?? 0} />
        <Kpi
          label="Running"
          value={(data.tasksSummary?.running ?? 0) + (data.tasksSummary?.claimed ?? 0)}
        />
        <Kpi label="Completed" value={data.tasksSummary?.completed ?? 0} />
        <Kpi label="Failed" value={data.tasksSummary?.failed ?? 0} />
      </section>
      <LoopControlPanel projects={data.projects} tasks={data.tasks} />
      <TaskTable tasks={data.tasks} workers={data.workers} projects={data.projects} />
    </div>
  );
}

function RunsPage(props: {
  apiBase: string;
  filters: SourceFilters;
  selectedRunId?: string;
  onFilters: (filters: SourceFilters) => void;
  onSelectRun: (runId: string) => void;
}) {
  return (
    <div className="route-stack">
      <SourceFilterBar filters={props.filters} onChange={props.onFilters} />
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <ActiveRunsPanel
            apiBase={props.apiBase}
            filters={props.filters}
            selectedRunId={props.selectedRunId}
            onSelectRun={props.onSelectRun}
          />
          <EventTimeline apiBase={props.apiBase} filters={props.filters} />
        </div>
        <aside className="dashboard-grid__side">
          <RunDetailPanel apiBase={props.apiBase} runId={props.selectedRunId} />
        </aside>
      </section>
    </div>
  );
}

function IterationsPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Total" value={data.iterations?.total ?? 0} />
        <Kpi label="Active" value={data.iterations?.active ?? 0} />
        <Kpi label="Blocked" value={data.iterations?.blocked ?? 0} />
        <Kpi
          label="Repair attempts"
          value={data.iterations?.repair_attempts ?? 0}
        />
      </section>
      <IterationList iterations={data.iterations?.recent ?? []} />
    </div>
  );
}

function PrCiPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Open PRs" value={data.prs?.open ?? 0} />
        <Kpi label="CI failed" value={data.prs?.ci_failed ?? 0} />
        <Kpi label="Eligible" value={data.prs?.eligible ?? 0} />
        <Kpi
          label="Blocked"
          value={data.automerge?.blocked ?? data.prs?.blocked ?? 0}
        />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <PrTable prs={data.prs} />
        </div>
        <aside className="dashboard-grid__side">
          <AutoMergePanel summary={data.automerge} />
          <ApprovalQueuePanel apiBase={apiBase} />
        </aside>
      </section>
    </div>
  );
}

function NotificationsPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Sent" value={data.notifications?.sent ?? 0} />
        <Kpi label="Skipped" value={data.notifications?.skipped ?? 0} />
        <Kpi label="Failed" value={data.notifications?.failed ?? 0} />
        <Kpi
          label="Bootstrap"
          value={data.notifications?.bootstrap_fallback.status ?? "unknown"}
        />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <NotificationList apiBase={apiBase} />
          <ProductTable
            title="Recent notification attempts"
            rows={(data.notifications?.recent ?? []).map((item) => [
              item.message.title,
              item.provider,
              item.status,
              item.error ?? item.severity ?? "metadata",
            ])}
          />
        </div>
        <aside className="dashboard-grid__side">
          <ProviderStatusPanel apiBase={apiBase} />
          <DocLinks
            links={[
              [
                "Bootstrap setup",
                "docs/notifications/BOOTSTRAP_NOTIFICATIONS.md",
              ],
              ["Dashboard quickstart", "docs/product/QUICKSTART_DASHBOARD.md"],
            ]}
          />
        </aside>
      </section>
    </div>
  );
}

function HermesPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  const hermes = data.hermes;
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Status" value={hermes?.status ?? "placeholder"} />
        <Kpi label="Tunnel" value={hermes?.tunnel.status ?? "unknown"} />
        <Kpi label="API health" value={hermes?.api.health ?? "unknown"} />
        <Kpi
          label="Loop"
          value={selfBootstrapStatus(data.tasks, data.summary)}
        />
        <Kpi
          label="Public exposure"
          value={hermes?.tunnel.public_exposure ? "yes" : "no"}
        />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <SummaryCard
            title="Self-bootstrap loop"
            state={selfBootstrapStatus(data.tasks, data.summary)}
            lines={[
              `Active master goal: ${data.summary?.latest?.active_goal?.title ?? "none"}`,
              `Planner decision: ${latestPlannerDecision(data.tasks)}`,
              `Current task: ${latestHermesTask(data.tasks)?.title ?? "none"}`,
              `Worker: ${latestHermesTask(data.tasks)?.assigned_worker_id ?? "unassigned"}`,
              `Recent result: ${latestHermesTask(data.tasks)?.result?.summary ?? latestHermesTask(data.tasks)?.status ?? "none"}`,
            ]}
          />
          <SummaryCard
            title="Supervisor"
            state={hermes?.status ?? "placeholder"}
            lines={[
              `Capabilities: ${hermes?.capabilities.join(", ") || "none observed"}`,
              `Last safe run: ${hermes?.last_safe_run?.run_id ?? "none"}`,
              `Nightly report: ${hermes?.nightly_report?.summary ?? "none"}`,
              `Sweep dry-run: ${hermes?.sweep_dry_run?.summary ?? "none"}`,
              `Degraded reason: ${hermes?.degraded_reason ?? "none"}`,
            ]}
          />
          <EventTimeline apiBase={apiBase} filters={{ platform: "hermes" }} />
        </div>
        <aside className="dashboard-grid__side">
          <DocLinks
            links={[
              [
                "Cloud supervisor runbook",
                "docs/hermes/CLOUD_SUPERVISOR_RUNBOOK.md",
              ],
              [
                "Self-bootstrap runbook",
                "docs/orchestrator/HERMES_SELF_BOOTSTRAP_RUNBOOK.md",
              ],
              [
                "Planner adapter",
                "docs/orchestrator/HERMES_PLANNER_ADAPTER.md",
              ],
            ]}
          />
        </aside>
      </section>
    </div>
  );
}

function SourcesAuditPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <ProductTable
        title="Adapter capability registry"
        rows={data.adapters.map((adapter) => [
          adapter.role,
          adapter.label,
          adapter.stability,
          adapter.optional ? "optional" : "required",
        ])}
      />
      <ProductTable
        title="Sources and adapters"
        rows={(data.summary?.sources ?? []).map((source) => [
          source.platform,
          source.adapter,
          `${source.event_count} events`,
          formatDateTime(source.latest_event_at),
        ])}
      />
      <ProductTable
        title="Audit trail"
        rows={(data.audit ?? []).map((entry) => [
          entry.action,
          entry.actor,
          entry.safety_decision,
          entry.raw_payload_included ? "raw" : "metadata only",
        ])}
      />
    </div>
  );
}

function SettingsPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="skybridge-panel">
        <div className="skybridge-card__header">
          <div>
            <p className="skybridge-kicker">Settings</p>
            <h2>Local product console</h2>
          </div>
          <span className="skybridge-state">
            {data.summary?.health.persistence ?? "unknown"}
          </span>
        </div>
        <dl className="settings-list">
          <div>
            <dt>API base</dt>
            <dd>{apiBase}</dd>
          </div>
          <div>
            <dt>Database</dt>
            <dd>{data.summary?.health.dbFile ?? "memory or unavailable"}</dd>
          </div>
          <div>
            <dt>Secrets shown</dt>
            <dd>no</dd>
          </div>
          <div>
            <dt>Auto-merge default</dt>
            <dd>
              {data.automerge?.enabled_by_default ? "enabled" : "disabled"}
            </dd>
          </div>
          <div>
            <dt>Core boundary</dt>
            <dd>agent-agnostic; adapters optional</dd>
          </div>
          <div>
            <dt>Hermes public exposure</dt>
            <dd>{data.hermes?.tunnel.public_exposure ? "yes" : "no"}</dd>
          </div>
        </dl>
      </section>
      <DocLinks
        links={[
          ["Product spec", "docs/product/OPERATOR_CONSOLE_PRODUCT_SPEC.md"],
          ["Dashboard quickstart", "docs/product/QUICKSTART_DASHBOARD.md"],
          ["API overview", "docs/api/API_OVERVIEW.md"],
          ["Security", "SECURITY.md"],
        ]}
      />
    </div>
  );
}

function useProductData(apiBase: string) {
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);
  const [summary, setSummary] = useState<SummaryResponse | undefined>();
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [goals, setGoals] = useState<GoalRecord[]>([]);
  const [iterations, setIterations] = useState<IterationsSummary | undefined>();
  const [prs, setPrs] = useState<PrsSummary | undefined>();
  const [notifications, setNotifications] = useState<
    NotificationsSummary | undefined
  >();
  const [hermes, setHermes] = useState<HermesSummary | undefined>();
  const [automerge, setAutoMerge] = useState<AutoMergeSummary | undefined>();
  const [audit, setAudit] = useState<AuditEntry[]>([]);
  const [adapters, setAdapters] = useState<
    Awaited<ReturnType<SkyBridgeClient["listAdapters"]>>
  >([]);
  const [workers, setWorkers] = useState<WorkerRecord[]>([]);
  const [workersSummary, setWorkersSummary] = useState<WorkerSummary | undefined>();
  const [tasks, setTasks] = useState<TaskRecord[]>([]);
  const [tasksSummary, setTasksSummary] = useState<TaskSummary | undefined>();
  const [error, setError] = useState<string | undefined>();

  useEffect(() => {
    let cancelled = false;
    const projectsPromise = client.listProjects();
    void Promise.all([
      client.getSummary(),
      projectsPromise,
      client.getIterationsSummary(),
      client.getPrsSummary(),
      client.getNotificationsSummary(),
      client.getHermesSummary(),
      client.getAutoMergeSummary(),
      client.listAuditEntries({ limit: 20 }),
      client.listAdapters(),
      client.listWorkers(),
      client.getWorkersSummary(),
      client.listTasks(),
      client.getTasksSummary(),
      projectsPromise.then((items) =>
        Promise.all(items.map((project) => client.listGoals(project.project_id))),
      ),
    ])
      .then(
        ([
          nextSummary,
          nextProjects,
          nextIterations,
          nextPrs,
          nextNotifications,
          nextHermes,
          nextAutoMerge,
          nextAudit,
          nextAdapters,
          nextWorkers,
          nextWorkersSummary,
          nextTasks,
          nextTasksSummary,
          nextGoalsByProject,
        ]) => {
          if (cancelled) return;
          setSummary(nextSummary);
          setProjects(nextProjects);
          setGoals(nextGoalsByProject.flat());
          setIterations(nextIterations);
          setPrs(nextPrs);
          setNotifications(nextNotifications);
          setHermes(nextHermes);
          setAutoMerge(nextAutoMerge);
          setAudit(nextAudit);
          setAdapters(nextAdapters);
          setWorkers(nextWorkers);
          setWorkersSummary(nextWorkersSummary);
          setTasks(nextTasks);
          setTasksSummary(nextTasksSummary);
          setError(undefined);
        },
      )
      .catch((err) => {
        if (!cancelled)
          setError(err instanceof Error ? err.message : String(err));
      });
    return () => {
      cancelled = true;
    };
  }, [client]);

  return {
    summary,
    projects,
    goals,
    iterations,
    prs,
    notifications,
    hermes,
    automerge,
    audit,
    adapters,
    workers,
    workersSummary,
    tasks,
    tasksSummary,
    error,
  };
}

function GoalTable({
  goals,
  projects,
}: {
  goals: GoalRecord[];
  projects: ProjectSummary[];
}) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Goal Registry</p>
          <h2>Server-side goals</h2>
        </div>
        <span className="skybridge-state">{goals.length}</span>
      </div>
      {goals.length === 0 ? <p className="skybridge-state-note">No goals recorded.</p> : null}
      <div className="data-table data-table--tasks">
        <div className="data-table__head">
          <span>Goal</span>
          <span>Status / risk</span>
          <span>Priority</span>
          <span>Evidence</span>
          <span>Project / dedupe</span>
        </div>
        {goals.map((goal) => {
          const project = projects.find((item) => item.project_id === goal.project_id);
          return (
            <div className="data-table__row" key={goal.goal_id}>
              <span>
                {goal.title}
                <small>{goal.goal_id} · {goal.source ?? "manual"}</small>
              </span>
              <span>
                <span className={badgeClass(goal.status === "blocked" || goal.status === "failed" ? "bad" : "ok")}>
                  {goal.status}
                </span>
                <small>{goal.risk ?? "low"} risk · {goal.lifecycle ?? goal.status}</small>
              </span>
              <span>
                {goal.priority ?? "normal"}
                <small>{goal.blocked_reason ?? goal.stale_reason ?? "no blocker"}</small>
              </span>
              <span>
                {goal.task_summary?.evidence_count ?? 0} evidence
                <small>{goal.evidence_requirements?.[0] ?? goal.completion_note ?? "requirements pending"}</small>
              </span>
              <span>
                {project?.name ?? goal.project_id}
                <small>{goal.dedupe_key ?? "no dedupe key"}</small>
              </span>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function WorkerTable({ workers, tasks }: { workers: WorkerRecord[]; tasks: TaskRecord[] }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Worker Pool</p>
          <h2>Runtime providers</h2>
        </div>
        <span className="skybridge-state">{workers.length}</span>
      </div>
      {workers.length === 0 ? (
        <p className="skybridge-state-note">No workers registered.</p>
      ) : null}
      <div className="data-table data-table--workers">
        <div className="data-table__head">
          <span>Worker</span>
          <span>Status</span>
          <span>Capabilities</span>
          <span>Task / result</span>
        </div>
        {workers.map((worker) => {
          const workerTasks = tasks.filter((task) => task.assigned_worker_id === worker.worker_id);
          const lastTask = workerTasks[0];
          return (
            <div className="data-table__row" key={worker.worker_id}>
              <span>
                {worker.name}
                <small>{worker.worker_id} · {worker.provider}</small>
              </span>
              <span>
                <span className={badgeClass(worker.status === "online" ? "ok" : "bad")}>
                  {worker.status}
                </span>
                <small>{worker.enabled ? "enabled" : "disabled"} · {formatDateTime(worker.last_seen_at)}</small>
              </span>
              <span>
                {worker.capabilities.join(", ") || "none"}
                <small>
                  {worker.labels.join(", ") || "no labels"} · {worker.auth_mode ?? "auth unknown"} · {worker.api_base_redacted ?? "api local/unknown"}
                </small>
              </span>
              <span>
                {worker.current_task_id ?? lastTask?.task_id ?? "none"}
                <small>{lastTask ? `${lastTask.status}: ${lastTask.result?.summary ?? lastTask.last_event?.type ?? "no result yet"}` : "no task history"}</small>
              </span>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function TaskTable({
  tasks,
  workers,
  projects,
}: {
  tasks: TaskRecord[];
  workers: WorkerRecord[];
  projects: ProjectSummary[];
}) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Task Queue</p>
          <h2>Queued and recent tasks</h2>
        </div>
        <span className="skybridge-state">{tasks.length}</span>
      </div>
      {tasks.length === 0 ? (
        <p className="skybridge-state-note">No tasks recorded.</p>
      ) : null}
      <div className="data-table data-table--tasks">
        <div className="data-table__head">
          <span>Task</span>
          <span>Status / risk</span>
          <span>Worker</span>
          <span>Planner / validation</span>
          <span>Project / PR</span>
        </div>
        {tasks.map((task) => {
          const worker = workers.find((item) => item.worker_id === task.assigned_worker_id);
          const project = projects.find((item) => item.project_id === task.project_id);
          const executionStatus = taskExecutionStatus(task);
          const validationStatus = taskValidationStatus(task);
          const prUrl = task.result?.pr_url;
          return (
            <div className="data-table__row" key={task.task_id}>
              <span>
                {task.title}
                <small>{task.task_id} · {task.last_event?.type ?? "no event"}</small>
              </span>
              <span>
                <span className={badgeClass(task.status === "failed" || task.status === "blocked" ? "bad" : "ok")}>
                  {task.status}
                </span>
                <small>{task.risk} risk · {task.source}</small>
              </span>
              <span>
                {worker?.name ?? task.assigned_worker_id ?? "unassigned"}
                <small>{task.claim?.claimed_at ? formatDateTime(task.claim.claimed_at) : "not claimed"}</small>
              </span>
              <span>
                {executionStatus}
                <small>
                  {task.planner_metadata?.decision ?? task.task_type ?? "executor"} · Validation:{" "}
                  {task.validation?.join(", ") || validationStatus}
                </small>
              </span>
              <span>
                {project?.name ?? task.project_id}
                <small>
                  {prUrl ? <a href={prUrl}>{prUrl}</a> : task.result?.result_url ?? "PR/result link pending"}
                </small>
              </span>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function LoopControlPanel({
  projects,
  tasks,
}: {
  projects: ProjectSummary[];
  tasks: TaskRecord[];
}) {
  const project = projects.find((item) => item.control_state);
  const control = project?.control_state;
  const currentTask = tasks.find((task) => task.task_id === control?.current_task_id);
  const state = control?.state ?? "stopped";
  const idleOrDegraded = control?.degraded_reason
    ? `degraded: ${control.degraded_reason}`
    : control?.idle_since
      ? `idle since ${formatDateTime(control.idle_since)}`
      : "ready";
  return (
    <section className="dashboard-grid">
      <SummaryCard
        title="Edge worker loop"
        state={state}
        lines={[
          `Project: ${project?.name ?? project?.project_id ?? "none selected"}`,
          `Last heartbeat: ${formatDateTime(control?.last_heartbeat)}`,
          `Loop task count: ${control?.loop_task_count ?? 0}`,
          `Idle/degraded: ${idleOrDegraded}`,
        ]}
      />
      <SummaryCard
        title="Loop control"
        state={control?.stop_requested ? "stop requested" : control?.stop_reason ?? "operator gated"}
        lines={[
          `Current worker: ${control?.current_worker_id ?? "none"}`,
          `Current task: ${currentTask?.title ?? control?.current_task_id ?? "none"}`,
          `Max tasks: ${control?.max_tasks ?? "not set"}`,
          `Last error: ${control?.last_error ?? "none"}`,
        ]}
      />
    </section>
  );
}

function taskExecutionStatus(task: TaskRecord): string {
  const summary = task.result?.summary ?? "";
  const match = summary.match(/Execution:\s*([A-Za-z_-]+)/i);
  if (match?.[1]) return match[1].toLowerCase();
  if (task.status === "running" || task.status === "claimed") return task.status;
  if (task.status === "completed") return "completed";
  if (task.status === "failed" || task.status === "blocked") return task.status;
  return "pending";
}

function taskValidationStatus(task: TaskRecord): string {
  const summary = task.result?.summary ?? "";
  const match = summary.match(/Validation:\s*([A-Za-z_-]+)/i);
  if (match?.[1]) return match[1].toLowerCase();
  if (task.status === "completed") return "unknown";
  if (task.status === "failed") return "failed or skipped";
  return "pending";
}

function latestHermesTask(tasks: TaskRecord[]): TaskRecord | undefined {
  return tasks.find((task) => task.source === "hermes-planner");
}

function latestPlannerDecision(tasks: TaskRecord[]): string {
  return latestHermesTask(tasks)?.planner_metadata?.decision ?? "none";
}

function selfBootstrapStatus(
  tasks: TaskRecord[],
  summary: SummaryResponse | undefined,
): string {
  const hermesTasks = tasks.filter((task) => task.source === "hermes-planner");
  const active = hermesTasks.find((task) =>
    ["queued", "claimed", "running"].includes(task.status),
  );
  if (active) return active.status;
  const blocked = hermesTasks.find((task) => task.status === "blocked");
  if (blocked) return "blocked";
  const completed = hermesTasks.filter((task) => task.status === "completed").length;
  if (completed >= 3) return "3 rounds complete";
  if (completed > 0) return `${completed}/3 complete`;
  return summary?.latest?.active_goal?.goal_id === "self-bootstrap-smoke"
    ? "ready"
    : "idle";
}

function IterationList({
  iterations,
}: {
  iterations: IterationsSummary["recent"];
}) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Iterations</p>
          <h2>Controller history</h2>
        </div>
        <span className="skybridge-state">{iterations.length}</span>
      </div>
      {iterations.length === 0 ? (
        <p className="skybridge-state-note">No iterations recorded.</p>
      ) : null}
      <ol className="rich-list">
        {iterations.map((iteration) => (
          <li key={iteration.iteration_id}>
            <div>
              <strong>{iteration.iteration_id}</strong>
              <small>
                {iteration.project_id} · {iteration.branch} · PR{" "}
                {iteration.pr_number ? `#${iteration.pr_number}` : "none"}
              </small>
              <small>
                Blocked reason: {iteration.blocked_reason ?? "none"} · repairs{" "}
                {iteration.repair_attempts}/{iteration.max_attempts}
              </small>
            </div>
            <span
              className={badgeClass(
                iteration.state === "blocked" ||
                  iteration.state === "failed" ||
                  iteration.state === "ci_failed"
                  ? "bad"
                  : "ok",
              )}
            >
              {iteration.state}
            </span>
          </li>
        ))}
      </ol>
    </section>
  );
}

function PrTable({ prs }: { prs?: PrsSummary }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Pull Requests</p>
          <h2>PR and CI readiness</h2>
        </div>
        <span className="skybridge-state">{prs?.open ?? 0} open</span>
      </div>
      <div className="data-table">
        <div className="data-table__head">
          <span>PR</span>
          <span>CI</span>
          <span>Eligibility</span>
          <span>Risk / reason</span>
        </div>
        {(prs?.prs ?? []).map((pr) => (
          <div className="data-table__row" key={pr.pr_number}>
            <span>
              #{pr.pr_number}
              <small>{pr.branch ?? "unknown branch"}</small>
            </span>
            <span>
              {pr.ci_state}
              <small>
                {pr.required_checks
                  .map((check) => `${check.name}:${check.status}`)
                  .join(", ") || "no checks"}
              </small>
            </span>
            <span>{pr.eligibility}</span>
            <span>
              {pr.risk}
              <small>{pr.reasons.join("; ") || "no classifier reason"}</small>
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

function AutoMergePanel({ summary }: { summary?: AutoMergeSummary }) {
  return (
    <SummaryCard
      title="Auto-merge dry-run"
      state={`${summary?.eligible ?? 0} eligible`}
      lines={[
        `Enabled by default: ${summary?.enabled_by_default ? "yes" : "no"}`,
        `Dry-run default: ${summary?.dry_run_default ? "yes" : "no"}`,
        `Blocked: ${summary?.blocked ?? 0}`,
        `Pending: ${summary?.pending ?? 0}`,
      ]}
    />
  );
}

function FailureList({ failures }: { failures: RunSummary[] }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Failures</p>
          <h2>Recent failures</h2>
        </div>
        <span className={badgeClass(failures.length ? "bad" : "ok")}>
          {failures.length}
        </span>
      </div>
      {failures.length === 0 ? (
        <p className="skybridge-state-note">No recent failed runs.</p>
      ) : null}
      <ol className="rich-list">
        {failures.map((run) => (
          <li key={run.run_id}>
            <div>
              <strong>{run.title ?? run.run_id}</strong>
              <small>
                {run.source_platform}/{run.source_adapter} ·{" "}
                {run.latest_message_summary ?? "safe metadata only"}
              </small>
            </div>
            <span className="skybridge-state skybridge-state--bad">failed</span>
          </li>
        ))}
      </ol>
    </section>
  );
}

function ProductTable({
  title,
  rows,
}: {
  title: string;
  rows: Array<Array<React.ReactNode>>;
}) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Product data</p>
          <h2>{title}</h2>
        </div>
        <span className="skybridge-state">{rows.length}</span>
      </div>
      {rows.length === 0 ? (
        <p className="skybridge-state-note">No local records yet.</p>
      ) : null}
      <div className="product-rows">
        {rows.map((row, index) => (
          <div className="product-row" key={index}>
            {row.map((cell, cellIndex) => (
              <span key={cellIndex}>{cell}</span>
            ))}
          </div>
        ))}
      </div>
    </section>
  );
}

function SummaryCard({
  title,
  state,
  lines,
}: {
  title: string;
  state: string;
  lines: string[];
}) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Summary</p>
          <h2>{title}</h2>
        </div>
        <span
          className={badgeClass(
            state.includes("degraded") || state.includes("blocked")
              ? "bad"
              : "ok",
          )}
        >
          {state}
        </span>
      </div>
      <ul className="summary-lines">
        {lines.map((line) => (
          <li key={line}>{line}</li>
        ))}
      </ul>
    </section>
  );
}

function DocLinks({ links }: { links: Array<[string, string]> }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Docs</p>
          <h2>Runbooks</h2>
        </div>
      </div>
      <div className="doc-links">
        {links.map(([label, href]) => (
          <a key={href} href={href}>
            {label}
          </a>
        ))}
      </div>
    </section>
  );
}

function Kpi({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <section className="kpi-card">
      <span>{label}</span>
      <strong>{value}</strong>
    </section>
  );
}

function useHashRoute(): Route {
  const [route, setRoute] = useState<Route>(() => parseRoute());
  useEffect(() => {
    const onHashChange = () => setRoute(parseRoute());
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);
  return route;
}

function parseRoute(): Route {
  const value = window.location.hash.replace(/^#\/?/, "");
  if (
    value === "embed/compact" ||
    window.location.pathname.startsWith("/embed/compact")
  )
    return "embed";
  return navItems.some((item) => item.route === value)
    ? (value as Route)
    : "overview";
}

function titleForRoute(route: Route): string {
  if (route === "pr-ci") return "PR/CI";
  if (route === "hermes") return "Hermes Adapter";
  if (route === "campaign-queue") return "Campaign Queue";
  if (route === "goals") return "Goals";
  if (route === "workers") return "Worker Pool";
  if (route === "tasks") return "Task Queue";
  return route.charAt(0).toUpperCase() + route.slice(1);
}

function adapterLabels(
  adapters: Awaited<ReturnType<SkyBridgeClient["listAdapters"]>>,
  role: string,
): string {
  const labels = adapters
    .filter((adapter) => adapter.role === role)
    .map((adapter) => adapter.label);
  return labels.length ? labels.join(", ") : "none";
}

function badgeClass(kind: "ok" | "bad") {
  return `skybridge-state ${kind === "bad" ? "skybridge-state--bad" : ""}`;
}

function formatDateTime(input: string | undefined): string {
  return input ? new Date(input).toLocaleString() : "not yet";
}

createRoot(document.getElementById("root")!).render(<App />);
