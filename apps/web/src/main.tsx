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
  fixtureBoincV1ControlledTrialStatus,
  fixtureBoincV1Status,
  fixtureBoincV1AlphaStatus,
  fixtureBoincV1ReleaseApproval,
  fixtureBoincV1ReleaseReport,
  fixtureBoincV1ReleaseStatus,
  fixtureTrustedDocsAutoMergeGate,
  fixtureCoreEngineStatus,
  fixtureDesktopResidentState,
  fixtureLocalResourcePolicyEnforcement,
  fixtureManagedModeRepeatabilitySummary,
  fixtureManagedModeRunRegistry,
  fixtureManagedModeV0Status,
  fixtureOneAtATimeManagedModeGate,
  fixtureLocalExecutionGuard,
  fixtureLocalResourcePolicy,
  fixtureLocalWorkerSupervisorState,
  fixtureMultiWorkerReadiness,
  fixtureGoalQueueReviewSummary,
  fixtureOperatorApprovalGate,
  fixtureOperatorApprovalRequest,
  fixtureOperatorApprovalState,
  fixtureAuditReport,
  fixtureEvidenceRetentionReport,
  fixtureFailureBudgetReport,
  fixtureSafeExportGate,
  fixtureServerApprovedWorkunitStatus,
  fixtureProposedGoalReviewSummary,
  fixtureProjectProfileReviewSummary,
  fixtureQueueControlState,
  fixtureRepoExclusiveLock,
  fixtureSchedulingPreview,
  fixtureWorkerHeartbeat,
  fixtureWorkerPairingPreview,
  fixtureWorkerRegistration,
  fixtureWorkerPairingRecord,
  fixtureOperatorApprovalRecord,
  fixtureResidentPollingReport,
  fixtureStaleCampaignLock,
  fixtureWorkunitCandidatePack,
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
  type BoincV1ReleaseReportSummary,
  type BoincV1ReleaseStatusSummary,
  type TrustedDocsAutoMergeGateSummary,
  type CoreEngineStatus,
  type DesktopResidentState,
  type ManagedModeRepeatabilitySummary,
  type ManagedModeRunRegistry,
  type OneAtATimeManagedModeGate,
  type LocalExecutionGuard,
  type LocalResourcePolicy,
  type LocalResourcePolicyEnforcement,
  type LocalWorkerSupervisorState,
  type ManagedModeV0Status,
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
  type ControlPlaneOperatorApprovalGate,
  type ControlPlaneOperatorApprovalRequest,
  type ControlPlaneOperatorApprovalState,
  type ControlPlaneWorkerHeartbeat,
  type ControlPlaneWorkerPairingPreview,
  type ControlPlaneWorkerRegistration,
  type AuditTrailSummary,
  type EvidenceRetentionSummary,
  type FailureBudgetSummary,
  type SafeExportGateSummary,
  type ServerApprovedWorkunitStatusSummary,
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
  | "control-plane"
  | "local-session"
  | "product-readiness"
  | "first-run"
  | "release"
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
  { route: "control-plane", label: "Control Plane" },
  { route: "local-session", label: "Local Session" },
  { route: "product-readiness", label: "Product Readiness" },
  { route: "first-run", label: "First-run" },
  { route: "release", label: "Release" },
  { route: "tasks", label: "Task Queue" },
  { route: "pr-ci", label: "PR/CI" },
  { route: "notifications", label: "Notifications" },
  { route: "hermes", label: "Hermes Adapter" },
  { route: "sources", label: "Sources/Audit" },
  { route: "audit", label: "Reliability Audit" },
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
        {route === "control-plane" ? <ControlPlanePage apiBase={apiBase} /> : null}
        {route === "local-session" ? <LocalSessionPage /> : null}
        {route === "product-readiness" ? <ProductReadinessPage /> : null}
        {route === "first-run" ? <FirstRunWizardPage /> : null}
        {route === "release" ? <BoincV1ReleaseDashboard /> : null}
        {route === "tasks" ? <TaskQueuePage apiBase={apiBase} /> : null}
        {route === "pr-ci" ? <PrCiPage apiBase={apiBase} /> : null}
        {route === "notifications" ? (
          <NotificationsPage apiBase={apiBase} />
        ) : null}
        {route === "hermes" ? <HermesPage apiBase={apiBase} /> : null}
        {route === "sources" ? <SourcesAuditPage apiBase={apiBase} /> : null}
        {route === "audit" ? <ReliabilityAuditPage /> : null}
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

function LocalSessionPage() {
  return (
    <div className="route-stack local-session-page">
      <section className="hero-panel">
        <div>
          <h2>Manual Local Session</h2>
          <p>Bounded non-worker preview for Web, server/control-plane, Desktop metadata, supervisor heartbeat, resident polling, diagnostics, product readiness and smoke-matrix status.</p>
        </div>
        <span className={badgeClass("ok")}>preview safe</span>
      </section>
      <section className="kpi-grid">
        <Kpi label="Session schema" value="skybridge.local_session.v1" />
        <Kpi label="Component schema" value="skybridge.local_session_component.v1" />
        <Kpi label="Lifecycle schema" value="skybridge.local_session_lifecycle.v1" />
        <Kpi label="token_printed" value="false" />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <WebLauncherSupervisorPanel />
          <WebPortableBundlePanel />
          <WebPortablePackagePanel />
          <WebSandboxInstallPanel />
          <WebReleaseWorkflowGuardPanel />
          <WebInstallerCandidatePanel />
          <WebSandboxInstalledRuntimePanel />
          <WebInstallSoakPanel />
          <WebRecoverySandboxPanel />
          <WebOperatorAcceptanceV3Panel />
          <WebSandboxUpgradeRollbackPanel />
          <WebSandboxSoakStabilityPanel />
          <WebOperatorAcceptancePanel />
          <WebLocalSessionPanel />
          <WebOperatorWalkthroughPanel />
          <ProductTable
            title="Local session components"
            rows={[
              ["web-preview", "preview", "port 5173", "worker=false"],
              ["server-control-plane-preview", "preview", "port 8787", "apply=false"],
              ["desktop-dev-metadata", "metadata", "port n/a", "claim=false"],
              ["local-supervisor-heartbeat-preview", "heartbeat", "bounded", "queue=false"],
              ["resident-polling-preview", "poll preview", "bounded", "execute=false"],
              ["diagnostics", "safe metadata", "no raw logs", "token_printed=false"],
            ]}
          />
        </div>
        <aside className="dashboard-grid__side">
          <SummaryCard
            title="doctor summary"
            state="check available"
            lines={[
              "repo clean checked",
              "bootstrap-complete checked",
              "local productization RC checked",
              "ports and locks checked",
              "no env dump persisted",
              "token_printed=false",
            ]}
          />
          <SummaryCard
            title="Disabled capabilities"
            state="execution off"
            lines={[
              "remote_execution_enabled=false",
              "arbitrary_command_enabled=false",
              "execution_enabled=false",
              "queue_apply_enabled=false",
              "task claim/create/apply disabled",
            ]}
          />
        </aside>
      </section>
    </div>
  );
}

function WebPortablePackagePanel() {
  return (
    <section className="skybridge-panel web-portable-package-panel" aria-label="Web portable package panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Portable Package</p>
          <h2>Portable Package Candidate</h2>
        </div>
        <span className={badgeClass("ok")}>extract smoke ready</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Package schema</dt><dd>skybridge.portable_package.v1</dd></div>
        <div><dt>Manifest status</dt><dd>skybridge.portable_package_manifest.v1; exclusions verified</dd></div>
        <div><dt>Extraction smoke status</dt><dd>extracts under .agent/tmp/portable-package/extract-smoke only</dd></div>
        <div><dt>Install preview</dt><dd>copy, shortcut, Start Menu and PATH plans are preview-only</dd></div>
        <div><dt>Uninstall preview</dt><dd>detect/remove/cleanup plans are preview-only</dd></div>
        <div><dt>Disabled capabilities</dt><dd>install, upload, worker execution, workunit apply, claim and queue apply remain false</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Install disabled</button>
        <button type="button" disabled aria-disabled="true">Upload disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execute disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebOperatorAcceptancePanel() {
  return (
    <section className="skybridge-panel web-operator-acceptance-panel" aria-label="Web operator acceptance panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Operator Acceptance</p>
          <h2>Clean-room Acceptance</h2>
        </div>
        <span className={badgeClass("ok")}>read-only</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Acceptance schema</dt><dd>skybridge.operator_acceptance_report.v1</dd></div>
        <div><dt>Clean-room rehearsal status</dt><dd>portable package extracts and runs under .agent/tmp/portable-package/clean-room only</dd></div>
        <div><dt>Artifact integrity status</dt><dd>manifest checksum, package checksum and provenance are safe metadata</dd></div>
        <div><dt>Fixture soak status</dt><dd>bounded fixture-only local session soak; no background process left running</dd></div>
        <div><dt>Next safe action</dt><dd>Review operator acceptance report, then run post-merge smokes before tagging</dd></div>
        <div><dt>Disabled capabilities</dt><dd>install, upload, Codex worker, workunit apply, task claim and queue apply remain false</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Install disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execute disabled</button>
        <button type="button" disabled aria-disabled="true">Queue apply disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebSandboxInstallPanel() {
  return (
    <section className="skybridge-panel web-sandbox-install-panel" aria-label="Web sandbox install panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Sandbox Install</p>
          <h2>Install Sandbox</h2>
        </div>
        <span className={badgeClass("ok")}>read-only</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Schema</dt><dd>skybridge.install_sandbox.v1</dd></div>
        <div><dt>Sandbox root</dt><dd>.agent/tmp/install-sandbox/current only</dd></div>
        <div><dt>Apply mode</dt><dd>portable package extract to sandbox; no host install</dd></div>
        <div><dt>Validation</dt><dd>launcher status, start-preview, doctor, demo and safe-summary only</dd></div>
        <div><dt>Disabled controls</dt><dd>real install, worker execute, apply, start and claim controls disabled</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Real install disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execute disabled</button>
        <button type="button" disabled aria-disabled="true">Claim/apply disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebSandboxUpgradeRollbackPanel() {
  return (
    <section className="skybridge-panel web-sandbox-upgrade-rollback-panel" aria-label="Web sandbox upgrade rollback panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Sandbox Upgrade</p>
          <h2>Upgrade / Rollback</h2>
        </div>
        <span className={badgeClass("ok")}>local channel</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Upgrade schema</dt><dd>skybridge.sandbox_upgrade_plan.v1</dd></div>
        <div><dt>Rollback schema</dt><dd>skybridge.sandbox_rollback_plan.v1</dd></div>
        <div><dt>Migration preview</dt><dd>v1.5.0-portable-package-rc to v1.6.0-clean-room-portable-acceptance-rc</dd></div>
        <div><dt>Containment</dt><dd>current, previous, rollback and staging stay under .agent/tmp/install-sandbox</dd></div>
        <div><dt>Network</dt><dd>no update, no binary download, no GitHub release</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Network update disabled</button>
        <button type="button" disabled aria-disabled="true">Host rollback disabled</button>
        <button type="button" disabled aria-disabled="true">Queue apply disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebSandboxSoakStabilityPanel() {
  return (
    <section className="skybridge-panel web-sandbox-soak-stability-panel" aria-label="Web sandbox soak stability panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Soak / Stability</p>
          <h2>Fixture Soak</h2>
        </div>
        <span className={badgeClass("ok")}>bounded</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Soak schema</dt><dd>skybridge.extended_fixture_soak.v1</dd></div>
        <div><dt>Stability schema</dt><dd>skybridge.stability_cleanup_report.v1</dd></div>
        <div><dt>Bounds</dt><dd>default max iterations 5; max duration 180 seconds</dd></div>
        <div><dt>Cleanup</dt><dd>stale sandbox preview, orphan fixture detection and lock consistency check</dd></div>
        <div><dt>Disabled controls</dt><dd>no worker loop, no task claim, no workunit apply, no queue apply</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Worker loop disabled</button>
        <button type="button" disabled aria-disabled="true">Start queue disabled</button>
        <button type="button" disabled aria-disabled="true">Resume apply disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebReleaseWorkflowGuardPanel() {
  return (
    <section className="skybridge-panel web-release-workflow-guard-panel" aria-label="Web release workflow guard panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Release Guard</p>
          <h2>Release Workflow Guard</h2>
        </div>
        <span className={badgeClass("ok")}>tag gate</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Guard schema</dt><dd>skybridge.release_workflow_guard.v1</dd></div>
        <div><dt>Policy schema</dt><dd>skybridge.tag_publish_policy.v1</dd></div>
        <div><dt>Side effects</dt><dd>tag workflows may publish GHCR images and upload workflow artifacts after classification</dd></div>
        <div><dt>Manual release</dt><dd>GitHub Release creation and artifact upload remain disabled</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Create Release disabled</button>
        <button type="button" disabled aria-disabled="true">Manual upload disabled</button>
        <button type="button" disabled aria-disabled="true">Force tag disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebInstallerCandidatePanel() {
  return (
    <section className="skybridge-panel web-installer-candidate-panel" aria-label="Web installer candidate panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Installer</p>
          <h2>Installer Candidate</h2>
        </div>
        <span className={badgeClass("ok")}>sandbox only</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Candidate schema</dt><dd>skybridge.installer_candidate.v1</dd></div>
        <div><dt>Manifest schema</dt><dd>skybridge.installer_manifest.v1</dd></div>
        <div><dt>Install root</dt><dd>.agent/tmp/installer-candidate/install-root only</dd></div>
        <div><dt>Host boundary</dt><dd>registry, startup, scheduled task, service, powercfg and PATH writes disabled</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Real install disabled</button>
        <button type="button" disabled aria-disabled="true">Uninstall disabled</button>
        <button type="button" disabled aria-disabled="true">Update disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebSandboxInstalledRuntimePanel() {
  return (
    <section className="skybridge-panel web-sandbox-installed-runtime-panel" aria-label="Web sandbox-installed runtime panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Installed Runtime</p>
          <h2>Sandbox-installed Runtime</h2>
        </div>
        <span className={badgeClass("ok")}>rehearsal</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Report schema</dt><dd>skybridge.sandbox_installed_runtime_report.v1</dd></div>
        <div><dt>Validated commands</dt><dd>launcher status, start-preview, doctor, demo, smoke safe-summary, cleanup-preview</dd></div>
        <div><dt>Execution boundary</dt><dd>no worker execution, workunit apply, task claim or queue apply</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Start worker disabled</button>
        <button type="button" disabled aria-disabled="true">Claim disabled</button>
        <button type="button" disabled aria-disabled="true">Queue apply disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebInstallSoakPanel() {
  return (
    <section className="skybridge-panel web-install-soak-panel" aria-label="Web install soak panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Install Soak</p>
          <h2>Install / Upgrade / Rollback Soak</h2>
        </div>
        <span className={badgeClass("ok")}>bounded</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Soak schema</dt><dd>skybridge.install_soak_report.v1</dd></div>
        <div><dt>Bounds</dt><dd>default 3 cycles; max duration 240 seconds</dd></div>
        <div><dt>Metrics</dt><dd>cycle count, phase durations, file count, sandbox size, stale lock/PID counts, cleanup result</dd></div>
        <div><dt>Background process</dt><dd>background_process_left=false</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Host update disabled</button>
        <button type="button" disabled aria-disabled="true">Host rollback disabled</button>
        <button type="button" disabled aria-disabled="true">Worker loop disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebRecoverySandboxPanel() {
  return (
    <section className="skybridge-panel web-recovery-sandbox-panel" aria-label="Web recovery sandbox panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Recovery</p>
          <h2>Recovery Sandbox</h2>
        </div>
        <span className={badgeClass("ok")}>preview</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Recovery schema</dt><dd>skybridge.recovery_sandbox_report.v1</dd></div>
        <div><dt>Markers</dt><dd>fixture crash, interrupted install, interrupted upgrade and interrupted rollback markers under .agent/tmp/install-sandbox</dd></div>
        <div><dt>Cleanup hardening</dt><dd>orphan lock, stale staging, stale rollback and port conflict metadata</dd></div>
        <div><dt>Mutation boundary</dt><dd>no host mutation and no process kill</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Cleanup apply disabled</button>
        <button type="button" disabled aria-disabled="true">Process kill disabled</button>
        <button type="button" disabled aria-disabled="true">Host repair disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebOperatorAcceptanceV3Panel() {
  return (
    <section className="skybridge-panel web-operator-acceptance-v3-panel" aria-label="Web operator acceptance v3 panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Acceptance v3</p>
          <h2>Operator Acceptance v3</h2>
        </div>
        <span className={badgeClass("ok")}>read-only</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Acceptance schema</dt><dd>skybridge.operator_acceptance_v3_report.v1</dd></div>
        <div><dt>Coverage</dt><dd>release guard, installer candidate, runtime rehearsal, soak, recovery and cleanup hardening</dd></div>
        <div><dt>Next safe action</dt><dd>review PR CI, merge, run post-merge smokes, then tag safety gate</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Worker execute disabled</button>
        <button type="button" disabled aria-disabled="true">Apply disabled</button>
        <button type="button" disabled aria-disabled="true">Start queue disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebPortableBundlePanel() {
  return (
    <section className="skybridge-panel web-portable-bundle-panel" aria-label="Web portable bundle panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Portable Bundle</p>
          <h2>Portable Local Bundle</h2>
        </div>
        <span className={badgeClass("ok")}>manifest safe</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Bundle schema</dt><dd>skybridge.portable_local_bundle.v1</dd></div>
        <div><dt>Manifest schema</dt><dd>skybridge.portable_bundle_manifest.v1</dd></div>
        <div><dt>Verification</dt><dd>entrypoints, docs, fixtures and forbidden exclusions checked</dd></div>
        <div><dt>Excluded content</dt><dd>node_modules, target, caches, raw logs, env dumps, secrets and tokens</dd></div>
        <div><dt>Disabled capabilities</dt><dd>install, upload, host mutation, worker execution and queue apply remain false</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Install disabled</button>
        <button type="button" disabled aria-disabled="true">Upload disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execute disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebLauncherSupervisorPanel() {
  return (
    <section className="skybridge-panel web-launcher-supervisor-panel" aria-label="Web launcher and session supervisor panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Repo Launcher</p>
          <h2>Launcher / Supervisor</h2>
        </div>
        <span className={badgeClass("ok")}>router safe</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Launcher status panel</dt><dd>skybridge.repo_local_launcher.v1; status=ready</dd></div>
        <div><dt>Session supervisor panel</dt><dd>fixed allowlist routes only; arbitrary shell rejected</dd></div>
        <div><dt>Demo mode panel</dt><dd>fixtures/demo safe bundle; no raw logs</dd></div>
        <div><dt>Next safe action panel</dt><dd>Run start-preview, doctor, walkthrough, or demo</dd></div>
        <div><dt>Disabled capabilities</dt><dd>Codex worker, workunit apply, task claim and queue apply remain false</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Launcher start disabled</button>
        <button type="button" disabled aria-disabled="true">Supervisor route preview disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execute disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebOperatorWalkthroughPanel() {
  return (
    <section className="skybridge-panel web-operator-walkthrough-panel" aria-label="Web operator walkthrough panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Walkthrough</p>
          <h2>Operator Walkthrough</h2>
        </div>
        <span className={badgeClass("ok")}>safe flow</span>
      </div>
      <ul className="summary-lines">
        <li>bootstrap complete check</li>
        <li>productization RC check</li>
        <li>local config, doctor, start preview and demo mode</li>
        <li>diagnostics, smoke fast and next safe action</li>
        <li>token_printed=false</li>
      </ul>
    </section>
  );
}

function WebLocalSessionPanel() {
  return (
    <section className="skybridge-panel web-local-session-panel" aria-label="Web local session status panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Local Session</p>
          <h2>Manual Local Session</h2>
        </div>
        <span className={badgeClass("ok")}>bounded</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Session status</dt><dd>stopped or fixture_completed; no raw logs</dd></div>
        <div><dt>Component health</dt><dd>web preview, control-plane preview, desktop metadata and diagnostics are metadata-only</dd></div>
        <div><dt>doctor summary</dt><dd>check, explain, ports, locks, dependencies and cleanup-preview</dd></div>
        <div><dt>Port/lock status</dt><dd>.agent/tmp/local-session metadata; stale cleanup preview only</dd></div>
        <div><dt>Disabled execution capabilities</dt><dd>Codex worker, workunit apply, task claim, task PR creation and generic queue apply remain disabled</dd></div>
        <div><dt>Next safe action</dt><dd>Run start preview, then apply only with -Apply -Profile full-local-preview -Bounded</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true" title="Use scripts/powershell/skybridge-local-session.ps1 -Command start for preview">
          Start preview disabled
        </button>
        <button type="button" disabled aria-disabled="true" title="Stop is CLI metadata only for the manual local session">
          Stop preview disabled
        </button>
        <button type="button" disabled aria-disabled="true" title="Doctor is CLI metadata only">
          Doctor preview disabled
        </button>
      </div>
      <span>token_printed=false</span>
    </section>
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
  const residentState = report.desktop_resident_state ?? fixtureDesktopResidentState;

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
          <CoreEngineStatusPanel status={fixtureCoreEngineStatus} />
          <BoincV1AlphaPanel status={fixtureBoincV1AlphaStatus} />
          <BoincV1PreviewPanel status={fixtureBoincV1Status} />
          <WebResidentWorkerSummaryPanel resident={residentState} />
          <ManagedModeV0StatusPanel status={fixtureManagedModeV0Status} />
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
          <WebLocalResourceEnforcementPanel enforcement={fixtureLocalResourcePolicyEnforcement} />
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

function BoincV1PreviewPanel({ status }: { status: BoincV1Status }) {
  const resourceGate = status.apply_gate.resource_gate as { can_run_one_at_a_time?: boolean; blockers?: string[] };
  return (
    <section className="skybridge-panel boinc-v1-preview-panel" aria-label="BOINC-like v1 two-workunit preview panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">BOINC-like v1</p>
          <h2>Two-Workunit Preview</h2>
        </div>
        <span className={badgeClass(status.readiness.apply_disabled ? "bad" : "ok")}>apply disabled</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Preview workunits</dt>
          <dd>{status.preview.workunits.map((workunit) => `${workunit.queue_order}:${workunit.target_path}`).join("; ")}</dd>
        </div>
        <div>
          <dt>Blocked reason</dt>
          <dd>{status.preview.blocked_reason}</dd>
        </div>
        <div>
          <dt>Open review hold</dt>
          <dd>{String(status.preview.blocked_by_open_review)}</dd>
        </div>
        <div>
          <dt>Resource gate state</dt>
          <dd>{`can_run_one_at_a_time=${String(resourceGate.can_run_one_at_a_time ?? false)}; blockers=${(resourceGate.blockers ?? []).join("; ") || "none"}`}</dd>
        </div>
        <div>
          <dt>Drain / pause</dt>
          <dd>{`drain_after_current=${String(status.drain_pause_policy.drain_after_current)}; pause_new_claims=${String(status.drain_pause_policy.pause_new_claims)}`}</dd>
        </div>
        <div>
          <dt>Next safe action</dt>
          <dd>{status.readiness.next_safe_action}</dd>
        </div>
      </dl>
      <QueueList title="Readiness gaps" items={status.readiness.readiness_gaps_before_v1_apply} fallback="No gaps." />
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Apply disabled</button>
        <button type="button" disabled aria-disabled="true">No task creation</button>
        <button type="button" disabled aria-disabled="true">No task claim</button>
        <button type="button" disabled aria-disabled="true">No execution</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function WebResidentWorkerSummaryPanel({ resident }: { resident: DesktopResidentState }) {
  return (
    <section className="skybridge-panel web-resident-worker-summary-panel" aria-label="Web resident worker summary panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Desktop Resident Worker</p>
          <h2>Safe Preview Shell</h2>
        </div>
        <span className={badgeClass(resident.execution_enabled ? "bad" : "ok")}>execution disabled</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Resident enabled</dt>
          <dd>{String(resident.resident_enabled)}</dd>
        </div>
        <div>
          <dt>Execution / queue apply</dt>
          <dd>{`execution_enabled=${String(resident.execution_enabled)}; queue_apply_enabled=${String(resident.queue_apply_enabled)}`}</dd>
        </div>
        <div>
          <dt>No next execution</dt>
          <dd>{String(resident.no_next_execution_authorized)}</dd>
        </div>
        <div>
          <dt>Resource gate</dt>
          <dd>{`required=${String(resident.resource_gate_required)}; status=${resident.resource_gate_status}`}</dd>
        </div>
        <div>
          <dt>Preview controls</dt>
          <dd>{`pause=${String(resident.control_state.pause_after_current)}; drain=${String(resident.control_state.drain_after_current)}; emergency=${String(resident.control_state.emergency_stop_requested)}`}</dd>
        </div>
        <div>
          <dt>Completed alpha</dt>
          <dd>Workunit A completed; Workunit B completed; Workunit C absent</dd>
        </div>
      </dl>
      <span>token_printed=false</span>
    </section>
  );
}

function CoreEngineStatusPanel({ status }: { status: CoreEngineStatus }) {
  return (
    <section className="skybridge-panel core-engine-status-panel" aria-label="Core engine module status panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Core Engine</p>
          <h2>Shared Safety Kernel</h2>
        </div>
        <span className={badgeClass(status.no_next_execution_authorized ? "ok" : "bad")}>read-only</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Core Engine module status</dt>
          <dd>{`${status.module_status.modules_added.length} modules; preferred=${String(status.module_status.preferred_implementation_path)}`}</dd>
        </div>
        <div>
          <dt>completed run registry</dt>
          <dd>{status.completed_run_registry.completed_run_ids.join("; ")}</dd>
        </div>
        <div>
          <dt>Resource gate</dt>
          <dd>{`required=${String(status.resource_gate_status.resource_gate_required)}; blockers=${status.resource_gate_status.blockers.join("; ") || "none"}`}</dd>
        </div>
        <div>
          <dt>Two-workunit preview</dt>
          <dd>{`count=${status.two_workunit_preview_status.preview_workunit_count}; apply=${String(status.two_workunit_preview_status.apply_enabled)}`}</dd>
        </div>
        <div>
          <dt>Apply disabled</dt>
          <dd>{status.apply_disabled_status.reason}</dd>
        </div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Run apply disabled</button>
        <button type="button" disabled aria-disabled="true">Queue apply disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execution disabled</button>
      </div>
      <span>token_printed=false</span>
    </section>
  );
}

function BoincV1AlphaPanel({ status }: { status: BoincV1AlphaStatus }) {
  return (
    <section className="skybridge-panel boinc-v1-alpha-panel" aria-label="BOINC v1 alpha status panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">BOINC v1 Alpha</p>
          <h2>Workunit A Hold Path</h2>
        </div>
        <span className={badgeClass(status.apply_disabled ? "ok" : "bad")}>apply disabled</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Alpha id</dt>
          <dd>{status.alpha_id}</dd>
        </div>
        <div>
          <dt>Workunit A state</dt>
          <dd>{`${status.workunit_a.workunit_id}:${status.workunit_a.status}`}</dd>
        </div>
        <div>
          <dt>Workunit B state</dt>
          <dd>{`${status.workunit_b.workunit_id}:${status.workunit_b.status}`}</dd>
        </div>
        <div>
          <dt>Workunit B blocked reason</dt>
          <dd>{status.workunit_b_blocked_reason}</dd>
        </div>
        <div>
          <dt>Workunit B PR</dt>
          <dd>{status.workunit_b_pr_url ?? "none"}</dd>
        </div>
        <div>
          <dt>Readiness</dt>
          <dd>{status.readiness_state}</dd>
        </div>
        <div>
          <dt>Workunit C present</dt>
          <dd>{String(status.workunit_c_present)}</dd>
        </div>
        <div>
          <dt>No next execution authorized</dt>
          <dd>{String(status.no_next_execution_authorized)}</dd>
        </div>
        <div>
          <dt>Next safe action</dt>
          <dd>{status.next_safe_action}</dd>
        </div>
        <div>
          <dt>Resource gate</dt>
          <dd>{status.resource_gate_status}</dd>
        </div>
        <div>
          <dt>Drain / pause</dt>
          <dd>{`drain=${String(status.drain_pause_status.drain_after_current)}; pause_new_claims=${String(status.drain_pause_status.pause_new_claims)}`}</dd>
        </div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Alpha completed</button>
        <button type="button" disabled aria-disabled="true">General apply disabled</button>
        <button type="button" disabled aria-disabled="true">Workunit C absent</button>
      </div>
      <span>BOINC v1 alpha completed; Workunit C absent. token_printed=false</span>
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

function ManagedModeV0StatusPanel({ status }: { status: ManagedModeV0Status }) {
  return (
    <section className="skybridge-panel managed-mode-v0-status-panel" aria-label="Managed Mode v0 status panel">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Managed Mode v0</p>
          <h2>Release Status</h2>
        </div>
        <span className={badgeClass(status.release_readiness.release_ready ? "ok" : "bad")}>resource gate required</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Readiness id</dt>
          <dd>{status.release_readiness.readiness_id ?? status.operator_guidance.current_state}</dd>
        </div>
        <div>
          <dt>Completed runs</dt>
          <dd>{status.completed_runs.completed_run_ids.join("; ")}</dd>
        </div>
        <div>
          <dt>Release readiness</dt>
          <dd>{String(status.release_readiness.release_ready)}</dd>
        </div>
        <div>
          <dt>No next execution authorized</dt>
          <dd>{String(status.release_readiness.no_next_execution_authorized)}</dd>
        </div>
        <div>
          <dt>Resource gate integrated</dt>
          <dd>{String(status.release_readiness.resource_gate_integrated ?? false)}</dd>
        </div>
        <div>
          <dt>General bounded queue apply</dt>
          <dd>{String(status.release_readiness.general_bounded_queue_apply_enabled)}</dd>
        </div>
        <div>
          <dt>Next safe action</dt>
          <dd>{status.operator_guidance.next_safe_action}</dd>
        </div>
      </dl>
      <p className="skybridge-state-note">Execution disabled banner: no start/run/apply controls. token_printed=false</p>
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

function WebLocalResourceEnforcementPanel({ enforcement }: { enforcement: LocalResourcePolicyEnforcement }) {
  return (
    <section className="skybridge-panel web-local-resource-enforcement-summary" aria-label="Web local resource enforcement summary">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Resource Gate</p>
          <h2>Run Allowance</h2>
        </div>
        <span className={badgeClass(enforcement.can_run_one_at_a_time ? "ok" : "bad")}>enforcement gate</span>
      </div>
      <dl className="queue-definition-list">
        <div>
          <dt>Can run one-at-a-time</dt>
          <dd>{String(enforcement.can_run_one_at_a_time)}</dd>
        </div>
        <div>
          <dt>Observation</dt>
          <dd>{`${enforcement.observation.observation_source}; ac=${String(enforcement.observation.ac_power)}; network=${String(enforcement.observation.network_available)}`}</dd>
        </div>
        <div>
          <dt>Blockers</dt>
          <dd>{enforcement.blockers.map((blocker) => blocker.blocker_id).join("; ") || "none"}</dd>
        </div>
        <div>
          <dt>No mutation</dt>
          <dd>{`powercfg=${String(enforcement.no_powercfg_mutation)}; admin_required=${String(enforcement.admin_required)}`}</dd>
        </div>
      </dl>
      <p className="skybridge-state-note">Resource policy gate only: no task claim and no task execution. token_printed=false</p>
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

function ReliabilityAuditPage() {
  return (
    <div className="route-stack reliability-audit" data-no-remote-execution="true">
      <section className="hero-panel hero-panel--queue">
        <div>
          <h2>Failure Budget / Audit</h2>
          <p>No execution enabled; this surface is safe metadata only.</p>
        </div>
        <span className={badgeClass("bad")}>queue apply disabled</span>
      </section>
      <section className="kpi-grid">
        <Kpi label="remote_execution_enabled" value="false" />
        <Kpi label="arbitrary_command_enabled" value="false" />
        <Kpi label="queue_apply_enabled" value="false" />
        <Kpi label="token_printed" value="false" />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <FailureBudgetPanel report={fixtureFailureBudgetReport} />
          <EvidenceRetentionPanel report={fixtureEvidenceRetentionReport} />
          <AuditTrailPanel report={fixtureAuditReport} />
        </div>
        <aside className="dashboard-grid__side">
          <RetryReplacementGatePanel report={fixtureFailureBudgetReport} />
          <HashChainPanel report={fixtureEvidenceRetentionReport} />
          <RedactionScanPanel report={fixtureAuditReport} />
          <SafeExportGatePanel gate={fixtureSafeExportGate} />
          <V1ReadinessGapPanel />
        </aside>
      </section>
    </div>
  );
}

function BoincV1ReleaseDashboard() {
  return (
    <div className="route-stack boinc-v1-release-dashboard" data-no-remote-execution="true">
      <section className="hero-panel hero-panel--queue">
        <div>
          <h2>BOINC-like v1 Controlled Release</h2>
          <p>No execution enabled banner: release status is metadata only.</p>
        </div>
        <span className={badgeClass("bad")}>execution disabled</span>
      </section>
      <section className="kpi-grid">
        <Kpi label="Release" value={fixtureBoincV1ReleaseStatus.release_version} />
        <Kpi label="Gate" value={fixtureBoincV1ReleaseStatus.gate.gate_result} />
        <Kpi label="queue_apply_enabled" value="false" />
        <Kpi label="token_printed" value="false" />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <ReleaseReadinessPanel status={fixtureBoincV1ReleaseStatus} />
          <ReleaseApprovalPreviewPanel approval={fixtureBoincV1ReleaseApproval} />
          <BoincV1ControlledTrialPanel status={fixtureBoincV1ControlledTrialStatus} />
          <ServerApprovedWorkunitPanel status={fixtureServerApprovedWorkunitStatus} />
          <TrustedDocsAutoMergePanel gate={fixtureTrustedDocsAutoMergeGate} />
          <ServerApprovedTrial226Panel />
          <OperatorCockpitPanel />
          <ReleaseCompletedRunsPanel report={fixtureBoincV1ReleaseReport} />
          <InstallerPromotionRcPanel />
          <ReleasePostChecklistPanel />
        </div>
        <aside className="dashboard-grid__side">
          <ControlPlaneDisabledBanner />
          <ReleaseGatePanel status={fixtureBoincV1ReleaseStatus} />
          <ReleasePolicyPanel status={fixtureBoincV1ReleaseStatus} />
          <ReleaseReliabilityPanel />
          <SummaryCard
            title="No enabled execute/run/apply/start controls"
            state="disabled"
            lines={[
              "No arbitrary command input",
              "No raw logs",
              "No raw secrets",
              "remote_execution_enabled=false",
              "arbitrary_command_enabled=false",
              "token_printed=false",
            ]}
          />
        </aside>
      </section>
    </div>
  );
}

function ReleaseReadinessPanel({ status }: { status: BoincV1ReleaseStatusSummary }) {
  const readiness = status.gate.readiness;
  return (
    <section className="skybridge-panel" aria-label="Release readiness">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Release Dashboard</p>
          <h2>Release Readiness</h2>
        </div>
        <span className={badgeClass(status.status === "ready" ? "ok" : "bad")}>{status.status}</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Core / alpha</dt><dd>{`core=${String(readiness.core_engine_ready)}; alpha=${String(readiness.boinc_v1_alpha_completed)}`}</dd></div>
        <div><dt>Workunits</dt><dd>{readiness.completed_alpha_workunits.join("; ")}</dd></div>
        <div><dt>Desktop / server</dt><dd>{`desktop=${String(readiness.desktop_resident_worker_ready)}; server=${String(readiness.server_control_plane_ready)}`}</dd></div>
        <div><dt>Reliability</dt><dd>{`failure=${String(readiness.failure_budget_ready)}; evidence=${String(readiness.evidence_retention_hash_chain_ready)}; audit=${String(readiness.audit_redaction_ready)}`}</dd></div>
        <div><dt>Open task PR / active state</dt><dd>{`open_task_pr=${String(!readiness.no_open_task_pr)}; active=${readiness.active_tasks}; stale=${readiness.stale_leases}; lock=${readiness.runner_lock}`}</dd></div>
        <div><dt>token_printed</dt><dd>{String(readiness.token_printed)}</dd></div>
      </dl>
    </section>
  );
}

function ReleaseGatePanel({ status }: { status: BoincV1ReleaseStatusSummary }) {
  return (
    <SummaryCard
      title="Release Gate Summary"
      state={status.gate.gate_result}
      lines={[
        `can_execute_now=${String(status.gate.can_execute_now)}`,
        `can_create_workunit_now=${String(status.gate.can_create_workunit_now)}`,
        `can_claim_task_now=${String(status.gate.can_claim_task_now)}`,
        `deferred=${status.gate.blockers.map((blocker) => blocker.blocker_id).join(", ")}`,
        "token_printed=false",
      ]}
    />
  );
}

function ReleasePolicyPanel({ status }: { status: BoincV1ReleaseStatusSummary }) {
  const policy = status.gate.policy;
  return (
    <SummaryCard
      title="Controlled Release Policy"
      state="preview only"
      lines={[
        `operator_approval=${String(policy.require_operator_approval)}`,
        `resource_gate=${String(policy.require_resource_gate)}`,
        `human_review=${String(policy.require_human_review)}`,
        `finalizer=${String(policy.require_finalizer)}`,
        `failure_budget=${String(policy.require_failure_budget)}`,
        `evidence_retention=${String(policy.require_evidence_retention)}`,
        `audit=${String(policy.require_audit)}`,
      ]}
    />
  );
}

function ReleaseApprovalPreviewPanel({ approval }: { approval: BoincV1ReleaseApprovalSummary }) {
  return (
    <section className="skybridge-panel" aria-label="Approval preview">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Approval Preview</p>
          <h2>Controlled Release Approval</h2>
        </div>
        <span className={badgeClass("bad")}>can_execute_now=false</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Approval state</dt><dd>{approval.approval_state}</dd></div>
        <div><dt>Max workunits</dt><dd>{approval.max_workunits}</dd></div>
        <div><dt>Max parallel repo mutations</dt><dd>{approval.max_parallel_repo_mutations}</dd></div>
        <div><dt>Requires</dt><dd>resource gate, human review, finalizer, failure budget, evidence retention, audit, server approval and desktop resident state</dd></div>
        <div><dt>Expires</dt><dd>{approval.expires_at}</dd></div>
        <div><dt>token_printed</dt><dd>{String(approval.token_printed)}</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Release approve preview disabled</button>
        <button type="button" disabled aria-disabled="true">Release reject preview disabled</button>
      </div>
    </section>
  );
}

function ReleaseCompletedRunsPanel({ report }: { report: BoincV1ReleaseReportSummary }) {
  return (
    <ProductTable
      title="Completed runs and alpha"
      rows={report.completed_workunits_runs.map((item) => [item, "complete", "safe metadata", "token_printed=false"])}
    />
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
    <section className="skybridge-panel boinc-v1-controlled-trial-panel" aria-label="BOINC v1 controlled trial 221 status">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Controlled Trial 221</p>
          <h2>Controlled Trial Completed</h2>
        </div>
        <span className={badgeClass("ok")}>boinc_v1_controlled_trial_221_completed</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Trial / workunit</dt><dd>{`${status.trial_id}; ${status.workunit.workunit_id}`}</dd></div>
        <div><dt>Task</dt><dd>{`${status.workunit.task_id}; ${status.workunit.task_type}; ${status.workunit.risk}`}</dd></div>
        <div><dt>Target</dt><dd>{status.workunit.target_path}</dd></div>
        <div><dt>Gates</dt><dd>{`release=${String(releaseGate.release_gate_result)}; approval=${gate.approval_gate.approval_state}; resource=${String((gate.resource_gate as Record<string, unknown>).can_run_one_at_a_time)}`}</dd></div>
        <div><dt>Reliability</dt><dd>{`failure=${String(reliability.failure_budget_gate_result)}; evidence=${String(reliability.evidence_retention_gate_result)}; audit=${String(reliability.audit_redaction_gate_result)}`}</dd></div>
        <div><dt>Task PR URL</dt><dd>{taskPrUrl}</dd></div>
        <div><dt>Finalizer evidence</dt><dd>{finalizerEvidence}</dd></div>
        <div><dt>Safety</dt><dd>no_next_execution_authorized=true; remote_execution_enabled=false; queue_apply_enabled=false</dd></div>
        <div><dt>No enabled execution buttons</dt><dd>No raw logs, no command input, no apply controls, token_printed=false</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Trial apply disabled</button>
        <button type="button" disabled aria-disabled="true">Finalizer apply requires merged task PR</button>
      </div>
    </section>
  );
}

function ServerApprovedWorkunitPanel({ status }: { status: ServerApprovedWorkunitStatusSummary }) {
  const finalizerPreview = status.finalizer_preview as Record<string, unknown>;
  return (
    <section className="skybridge-panel" aria-label="Server-approved run 225">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Server-approved Run</p>
          <h2>Server-approved run 225</h2>
        </div>
        <span className={badgeClass("bad")}>Human review hold</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Run id</dt><dd>{status.run_id}</dd></div>
        <div><dt>Workunit</dt><dd>{status.workunit.workunit_id}</dd></div>
        <div><dt>Task</dt><dd>{status.workunit.task_id}</dd></div>
        <div><dt>Pairing / approval</dt><dd>{`pairing=${status.gate.pairing_gate_result}; approval=${status.gate.approval_gate_result}; consumed=${status.gate.approval_consumption_status}`}</dd></div>
        <div><dt>Resident polling / resource</dt><dd>{`polling=${status.gate.resident_polling_gate_result}; resource=${status.gate.resource_gate_result}`}</dd></div>
        <div><dt>Failure / evidence / audit</dt><dd>{`failure=${status.gate.failure_budget_gate_result}; evidence=${status.gate.evidence_retention_gate_result}; audit=${status.gate.audit_redaction_gate_result}`}</dd></div>
        <div><dt>task PR URL</dt><dd>{String(finalizerPreview.task_pr_url ?? "pending")}</dd></div>
        <div><dt>Human review hold</dt><dd>{String(finalizerPreview.status ?? "pending")}</dd></div>
        <div><dt>Execution boundary</dt><dd>{`remote_execution_enabled=${String(status.execution_boundary.remote_execution_enabled)}; arbitrary_command_enabled=${String(status.execution_boundary.arbitrary_command_enabled)}; queue_apply_enabled=false`}</dd></div>
        <div><dt>No enabled execution buttons</dt><dd>true</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Server-approved apply disabled</button>
        <button type="button" disabled aria-disabled="true">Finalizer apply requires merged task PR</button>
      </div>
    </section>
  );
}

function TrustedDocsAutoMergePanel({ gate }: { gate: TrustedDocsAutoMergeGateSummary }) {
  return (
    <section className="skybridge-panel trusted-docs-auto-merge-panel" aria-label="Trusted docs auto-merge preview">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Trusted Docs Preview</p>
          <h2>Auto-merge Disabled</h2>
        </div>
        <span className={badgeClass("bad")}>trusted_docs_auto_merge_enabled=false</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Policy</dt><dd>{`auto_merge_apply_enabled=${String(gate.policy.auto_merge_apply_enabled)}; max_files=${gate.policy.max_files}; max_additions=${gate.policy.max_additions}; max_deletions=${gate.policy.max_deletions}`}</dd></div>
        <div><dt>Allowed</dt><dd>{gate.policy.allowed_paths.join("; ")}</dd></div>
        <div><dt>Decision</dt><dd>{gate.decision.decision}</dd></div>
        <div><dt>Eligible preview</dt><dd>{`theoretical=${String(gate.decision.theoretically_eligible)}; auto_merge_allowed=${String(gate.decision.auto_merge_allowed)}`}</dd></div>
        <div><dt>Blockers</dt><dd>{gate.decision.blockers.join("; ")}</dd></div>
        <div><dt>Human review</dt><dd>{`required=${String(gate.decision.human_review_required)}; no auto-merge enabled`}</dd></div>
        <div><dt>Audit</dt><dd>{gate.audit.events.join("; ")}</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Auto-merge disabled</button>
        <button type="button" disabled aria-disabled="true">Human review required</button>
      </div>
    </section>
  );
}

function ServerApprovedTrial226Panel() {
  return (
    <section className="skybridge-panel server-approved-trial-226-panel" aria-label="Server-approved two-workunit trial 226">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Server-approved Trial</p>
          <h2>Trial 226 Completed</h2>
        </div>
        <span className={badgeClass("ok")}>no_next_execution_authorized=true</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Workunit A</dt><dd>A/B task PRs and merge commits are recorded in `.agent/tmp/server-approved-two-workunit-trial-226`.</dd></div>
        <div><dt>Workunit B</dt><dd>Runs only after Workunit A is merged and finalized; repo mutation is serialized.</dd></div>
        <div><dt>Trusted-docs scoped merge</dt><dd>Exact docs-only PR scope, green CI, redaction and audit required.</dd></div>
        <div><dt>Execution boundary</dt><dd>remote_execution_enabled=false; generic_bounded_queue_apply_enabled=false</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Remote execution disabled</button>
        <button type="button" disabled aria-disabled="true">Generic queue apply disabled</button>
      </div>
    </section>
  );
}

function OperatorCockpitPanel() {
  return (
    <section className="skybridge-panel operator-cockpit-panel" aria-label="Operator Cockpit">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Operator Cockpit</p>
          <h2>Bootstrap Complete</h2>
        </div>
        <span className={badgeClass("ok")}>controlled mode</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Release status</dt><dd>v1.0 bootstrap-complete candidate; controlled mode only</dd></div>
        <div><dt>Bootstrap-complete status</dt><dd>Goal 214 through Goal 226 chain verified</dd></div>
        <div><dt>Active/stale/lock state</dt><dd>active_tasks=0; stale_leases=0; runner_lock=none</dd></div>
        <div><dt>Worker pairing state</dt><dd>durable pairing evidence retained; worker execution remains disabled</dd></div>
        <div><dt>Approval state</dt><dd>server approval and finalizer evidence retained; human review remains required unless future scoped approval says otherwise</dd></div>
        <div><dt>Resident polling state</dt><dd>resident polling gate passed for controlled trials; no worker loop is running</dd></div>
        <div><dt>Resource gate state</dt><dd>one-at-a-time resource policy retained; no concurrent repo mutation authorized</dd></div>
        <div><dt>Queue/apply disabled state</dt><dd>remote_execution_enabled=false; arbitrary_command_enabled=false; execution_enabled=false; queue_apply_enabled=false</dd></div>
        <div><dt>Completed Runs</dt><dd>214, 216, 217, 218, 219, 220, 221, 223, 224, 225, 226</dd></div>
        <div><dt>Completed two-workunit trial</dt><dd>Workunit A and Workunit B merged and finalized; no Workunit C</dd></div>
        <div><dt>Evidence retention</dt><dd>hash-chain and safe export evidence retained as safe metadata only</dd></div>
        <div><dt>Audit/redaction</dt><dd>audit trail and redaction reports present; no raw logs or secrets displayed</dd></div>
        <div><dt>Trusted-docs Scoped Merge</dt><dd>explicit exact-PR docs-only scoped merge; global trusted-docs auto-merge disabled</dd></div>
        <div><dt>Blocked capabilities</dt><dd>start-all, start-queue, resume apply, generic bounded queue apply, remote execution and arbitrary command dispatch</dd></div>
        <div><dt>Next safe action</dt><dd>productization, installer, authenticated server pairing and controlled v1.1 planning; no_next_execution_authorized=true; token_printed=false</dd></div>
      </dl>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Cockpit read-only</button>
        <button type="button" disabled aria-disabled="true">Execution disabled</button>
      </div>
    </section>
  );
}

function ProductReadinessPage() {
  const disabledCapabilities = [
    "execution_enabled=false",
    "queue_apply_enabled=false",
    "remote_execution_enabled=false",
    "arbitrary_command_enabled=false",
    "trusted_docs_auto_merge_enabled=false",
  ];
  return (
    <div className="route-stack product-readiness-dashboard" data-no-remote-execution="true">
      <section className="hero-panel hero-panel--queue">
        <div>
          <h2>Product Readiness</h2>
          <p>Local product launch, diagnostics and packaging previews are read-only metadata surfaces.</p>
        </div>
        <span className={badgeClass("bad")}>execution disabled</span>
      </section>
      <section className="kpi-grid">
        <Kpi label="Health summary" value="safe" />
        <Kpi label="Launch profile summary" value="preview only" />
        <Kpi label="Diagnostics summary" value="metadata" />
        <Kpi label="token_printed" value="false" />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <ProductTable
            title="Launch Profiles"
            rows={[
              ["dev-preview", "desktop + web + server previews", "execution_enabled=false"],
              ["desktop-only", "Desktop preview", "queue_apply_enabled=false"],
              ["web-control-plane-preview", "Web and server previews", "remote_execution_enabled=false"],
              ["supervisor-heartbeat-preview", "Supervisor status preview", "arbitrary_command_enabled=false"],
              ["resident-polling-preview", "Resident polling preview", "trusted_docs_auto_merge_enabled=false"],
              ["full-local-preview", "All local previews", "token_printed=false"],
            ]}
          />
          <ProductTable
            title="Diagnostics Summary"
            rows={[
              [".agent/tmp/diagnostics/health-report.json", "health report", "no env dump"],
              [".agent/tmp/product-readiness/product-readiness-report.json", "product readiness report", "no raw logs"],
            ]}
          />
          <ProductTable
            title="Packaging preview status"
            rows={[
              [".agent/tmp/packaging-preview/desktop-packaging-preview.json", "metadata only", "uploads_artifacts=false"],
              ["Release artifact preview", "no GitHub release", "creates_github_release=false"],
            ]}
          />
          <ProductTable
            title="Windows launcher preview status"
            rows={[
              [".agent/tmp/windows-launcher-preview/windows-launcher-preview.json", "dry run", "registry_mutation=false"],
              ["Autostart preview", "not applied", "startup_folder_write=false"],
              ["Service preview", "not applied", "service_creation=false"],
            ]}
          />
        </div>
        <aside className="dashboard-grid__side">
          <SummaryCard
            title="Bootstrap-complete status"
            state="verified"
            lines={[
              "release tag v1.0.0-boinc-like-self-bootstrap-complete",
              "active_tasks=0",
              "stale_leases=0",
              "runner_lock=none",
              "no_next_execution_authorized=true",
            ]}
          />
          <SummaryCard
            title="Disabled capabilities"
            state="disabled"
            lines={disabledCapabilities}
          />
          <SummaryCard
            title="Next safe action"
            state="review"
            lines={[
              "Run productization smokes.",
              "Review generated safe reports.",
              "Do not start workers or create workunits.",
              "token_printed=false",
            ]}
          />
          <DocLinks
            links={[
              ["Product state layout", "docs/dev/PRODUCT_STATE_LAYOUT.md"],
              ["Local productization overview", "docs/dev/LOCAL_PRODUCTIZATION_OVERVIEW.md"],
              ["Operator daily checklist", "docs/dev/OPERATOR_DAILY_CHECKLIST.md"],
            ]}
          />
        </aside>
      </section>
    </div>
  );
}

const firstRunSteps = [
  ["Bootstrap complete status", "verified; active_tasks=0; stale_leases=0"],
  ["Product readiness status", "ready_for_local_preview"],
  ["Runtime profile selection", "preview-only profiles; no worker start"],
  ["Diagnostics health", ".agent/tmp/diagnostics/health-report.json"],
  ["Pairing/approval state", "metadata-only; no raw pairing codes"],
  ["Resident polling preview", "status preview only"],
  ["Packaging preview", "desktop package candidate metadata"],
  ["Backup/restore preview", "safe metadata only"],
  ["Disabled capabilities", "execution/apply/start/claim unavailable"],
  ["Next safe action", "run smokes and review reports"],
];

const firstRunConfigWizardRows = [
  ["schema", "skybridge.local_config.v1"],
  ["profile schema", "skybridge.local_config_profile.v1"],
  ["validation", "skybridge.local_config_validation.v1"],
  ["redaction", "skybridge.local_config_redaction.v1"],
  ["example", "fixtures/productization/local-config.example.json"],
  ["execution", "execution_enabled=false; queue_apply_enabled=false"],
  ["remote", "remote_execution_enabled=false; arbitrary_command_enabled=false"],
  ["trusted docs", "trusted_docs_auto_merge_enabled=false"],
];

function FirstRunWizardPage() {
  return (
    <div className="route-stack first-run-wizard" data-no-remote-execution="true">
      <section className="hero-panel hero-panel--queue">
        <div>
          <h2>First-run Wizard</h2>
          <p>Read-only onboarding for local product preview and safe runtime planning.</p>
        </div>
        <span className={badgeClass("bad")}>no execute controls</span>
      </section>
      <section className="kpi-grid">
        <Kpi label="Wizard schema" value="skybridge.first_run_wizard.v1" />
        <Kpi label="Onboarding" value="preview only" />
        <Kpi label="Runtime" value="dry run" />
        <Kpi label="token_printed" value="false" />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <ProductTable
            title="First-run steps"
            rows={firstRunSteps.map(([step, status], index) => [
              `${index + 1}. ${step}`,
              status,
              "skybridge.first_run_step.v1",
            ])}
          />
          <ProductTable
            title="Runtime and process health"
            rows={[
              [".agent/tmp/local-runtime/runtime-plan.json", "skybridge.local_runtime_plan.v1", "starts_unbounded_loop=false"],
              [".agent/tmp/local-runtime/runtime-health-report.json", "skybridge.local_runtime_health.v1", "raw_process_output_persisted=false"],
            ]}
          />
          <ProductTable
            title="First-run config wizard preview"
            rows={firstRunConfigWizardRows}
          />
        </div>
        <aside className="dashboard-grid__side">
          <SummaryCard
            title="Onboarding status"
            state="preview"
            lines={[
              "skybridge.onboarding_status.v1",
              "skybridge.next_safe_action.v1",
              "no raw logs",
              "no secrets",
              "token_printed=false",
            ]}
          />
          <SummaryCard
            title="Productization RC"
            state="candidate"
            lines={[
              "skybridge.local_productization_rc_report.v1",
              "v1.1.0-local-productization-rc",
              "bounded runtime candidate",
              "safe config validation",
              "token_printed=false",
            ]}
          />
          <SummaryCard
            title="Disabled controls"
            state="disabled"
            lines={[
              "execute disabled",
              "apply disabled",
              "start disabled",
              "claim disabled",
            ]}
          />
          <div className="queue-placeholder-controls">
            <button type="button" disabled aria-disabled="true">Start disabled</button>
            <button type="button" disabled aria-disabled="true">Apply disabled</button>
            <button type="button" disabled aria-disabled="true">Claim disabled</button>
          </div>
        </aside>
      </section>
    </div>
  );
}

function ReleaseReliabilityPanel() {
  return (
    <SummaryCard
      title="Reliability Audit"
      state="ready"
      lines={[
        "Failure budget ready",
        "Evidence retention ready",
        "Hash chain verified",
        "Audit/redaction ready",
        "Safe export gate ready",
      ]}
    />
  );
}

function ReleasePostChecklistPanel() {
  return (
    <SummaryCard
      title="Post-release checklist"
      state="pending tag"
      lines={[
        "Post-merge gate",
        "Post-release smokes",
        "Create immutable tag",
        "Write safe release reports",
        "No workunit execution",
      ]}
    />
  );
}

function InstallerPromotionRcPanel() {
  const rows = [
    ["Installer promotion panel", "skybridge.installer_promotion_report.v1", "artifact_promotion_gate_status=passed"],
    ["Release Artifact Manifest", "skybridge.release_artifact_candidate_manifest.v1", "manual_upload_performed=false"],
    ["Update Channel Manifest", "skybridge.update_channel_manifest_preview.v1", "network_update_allowed=false"],
    ["Host Mutation Gate", "skybridge.host_mutation_gate.v1", "host_mutation_allowed=false"],
    ["Long Soak", "skybridge.long_sandbox_soak_report.v1", "background_process_left=false"],
    ["Operator Acceptance v4", "skybridge.operator_acceptance_v4_report.v1", "token_printed=false"],
  ];
  return (
    <section className="skybridge-panel installer-promotion-rc-panel" aria-label="Installer promotion release candidate panels">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Installer Promotion RC</p>
          <h2>Release Candidate Surfaces</h2>
        </div>
        <span className={badgeClass("bad")}>host mutation disabled</span>
      </div>
      <div className="data-table data-table--workers">
        {rows.map(([name, schema, status]) => (
          <div className="data-table__row" key={name}>
            <span>{name}<small>{schema}</small></span>
            <span>{status}<small>safe report under .agent/tmp</small></span>
            <span>read-only<small>no install/update/upload/release control</small></span>
          </div>
        ))}
      </div>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Install disabled</button>
        <button type="button" disabled aria-disabled="true">Update disabled</button>
        <button type="button" disabled aria-disabled="true">Upload disabled</button>
        <button type="button" disabled aria-disabled="true">GitHub Release disabled</button>
        <button type="button" disabled aria-disabled="true">Worker execute disabled</button>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Next safe action</dt><dd>Open PR, wait for CI, merge, run post-merge smokes, then tag only after the tag safety gate passes.</dd></div>
        <div><dt>Disabled capabilities</dt><dd>real_install=false; network_update=false; manual_upload=false; manual_github_release=false; queue_apply_enabled=false</dd></div>
      </dl>
    </section>
  );
}

function FailureBudgetPanel({ report }: { report: FailureBudgetSummary }) {
  return (
    <section className="skybridge-panel web-audit-panel" aria-label="Failure budget status">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Failure Budget</p>
          <h2>Failure Budget Status</h2>
        </div>
        <span className={badgeClass("ok")}>no silent rerun</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Retry authorization</dt><dd>{String(report.policy.retry_requires_explicit_authorization)}</dd></div>
        <div><dt>Replacement authorization</dt><dd>{String(report.policy.replacement_requires_no_mutation_classification)}</dd></div>
        <div><dt>Max retries</dt><dd>{report.policy.max_retries_per_workunit}</dd></div>
        <div><dt>PR-created hold</dt><dd>{String(report.policy.no_retry_after_pr_created)}</dd></div>
        <div><dt>Raw artifact hold</dt><dd>{String(report.policy.no_retry_after_raw_artifact)}</dd></div>
        <div><dt>token_printed</dt><dd>{String(report.token_printed)}</dd></div>
      </dl>
    </section>
  );
}

function RetryReplacementGatePanel({ report }: { report: FailureBudgetSummary }) {
  return (
    <SummaryCard
      title="Retry / Replacement Gate Status"
      state="automatic retry refused"
      lines={[
        `retry_allowed=${String(report.retry_gate.retry_allowed)}`,
        `automatic_retry_allowed=${String(report.retry_gate.automatic_retry_allowed)}`,
        `replacement_allowed=${String(report.replacement_gate.replacement_allowed)}`,
        `automatic_replacement_allowed=${String(report.replacement_gate.automatic_replacement_allowed)}`,
        "explicit operator authorization required",
        "token_printed=false",
      ]}
    />
  );
}

function EvidenceRetentionPanel({ report }: { report: EvidenceRetentionSummary }) {
  return (
    <section className="skybridge-panel" aria-label="Evidence retention status">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Evidence</p>
          <h2>Evidence Retention Status</h2>
        </div>
        <span className={badgeClass(report.retention.safe_to_export ? "ok" : "bad")}>
          {report.entries.length} entries
        </span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Safe to export</dt><dd>{String(report.retention.safe_to_export)}</dd></div>
        <div><dt>Raw artifacts</dt><dd>{String(report.retention.raw_artifact)}</dd></div>
        <div><dt>Secret detected</dt><dd>{String(report.retention.secret_detected)}</dd></div>
        <div><dt>Indexed paths</dt><dd>{report.retention.indexed_paths.join("; ")}</dd></div>
        <div><dt>token_printed</dt><dd>{String(report.token_printed)}</dd></div>
      </dl>
    </section>
  );
}

function HashChainPanel({ report }: { report: EvidenceRetentionSummary }) {
  return (
    <SummaryCard
      title="Hash Chain Status"
      state={report.hash_chain.verified ? "verified" : "blocked"}
      lines={[
        `chain=${report.hash_chain.chain_id}`,
        `entries=${report.hash_chain.entries.length}`,
        `head=${report.hash_chain.head_hash.slice(0, 12)}`,
        "safe metadata only",
        "token_printed=false",
      ]}
    />
  );
}

function AuditTrailPanel({ report }: { report: AuditTrailSummary }) {
  return (
    <section className="skybridge-panel" aria-label="Audit trail summary">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Audit</p>
          <h2>Audit Trail Summary</h2>
        </div>
        <span className={badgeClass("ok")}>{report.audit_trail.events.length} events</span>
      </div>
      <ol className="rich-list">
        {report.audit_trail.events.map((event) => (
          <li key={event.event_id}>
            <div>
              <strong>{event.event_type}</strong>
              <small>{event.actor_type} · {event.reason}</small>
            </div>
            <span className={badgeClass("ok")}>metadata</span>
          </li>
        ))}
      </ol>
    </section>
  );
}

function RedactionScanPanel({ report }: { report: AuditTrailSummary }) {
  return (
    <SummaryCard
      title="Redaction Scan Status"
      state={report.redaction_scan.passed ? "passed" : "blocked"}
      lines={[
        `scanned=${report.redaction_scan.scanned_path_count}`,
        `violations=${report.redaction_scan.violations.length}`,
        "raw logs not shown",
        "secrets not shown",
        "token_printed=false",
      ]}
    />
  );
}

function SafeExportGatePanel({ gate }: { gate: SafeExportGateSummary }) {
  return (
    <SummaryCard
      title="Safe Export Gate Status"
      state={gate.safe_to_export ? "safe_to_export" : "blocked"}
      lines={[
        `raw_prompt_persisted=${String(gate.raw_prompt_persisted)}`,
        `raw_transcript_persisted=${String(gate.raw_transcript_persisted)}`,
        `raw_stdout_persisted=${String(gate.raw_stdout_persisted)}`,
        `raw_stderr_persisted=${String(gate.raw_stderr_persisted)}`,
        `raw_logs_persisted=${String(gate.raw_logs_persisted)}`,
        `authorization_persisted=${String(gate.authorization_persisted)}`,
        "token_printed=false",
      ]}
    />
  );
}

function V1ReadinessGapPanel() {
  return (
    <SummaryCard
      title="v1 Readiness Gap Closure Status"
      state="ready for Goal 220"
      lines={[
        "Failure budget policy present",
        "Evidence hash-chain present",
        "Audit trail present",
        "Redaction scan present",
        "Remote execution disabled",
        "Queue apply disabled",
      ]}
    />
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

function ControlPlanePage({ apiBase }: { apiBase: string }) {
  const data = useControlPlaneData(apiBase);
  const workers =
    data.workers.length > 0
      ? data.workers.map((worker) => worker.registration)
      : [fixtureWorkerRegistration];
  const heartbeat = data.workers[0]?.heartbeat ?? fixtureWorkerHeartbeat;
  const pairing = data.workers[0]?.pairing_preview ?? fixtureWorkerPairingPreview;
  const approvals =
    data.approvals.length > 0
      ? data.approvals
      : [
          {
            request: fixtureOperatorApprovalRequest,
            state: fixtureOperatorApprovalState,
            gate: fixtureOperatorApprovalGate,
          },
        ];

  return (
    <div className="route-stack server-control-plane" data-no-remote-execution="true">
      <section className="hero-panel hero-panel--queue">
        <div>
          <h2>Server Control Plane</h2>
          <p>No server-triggered task execution is available from this surface.</p>
        </div>
        <span className={badgeClass("bad")}>remote execution disabled</span>
      </section>
      <section className="kpi-grid">
        <Kpi label="remote_execution_enabled" value="false" />
        <Kpi label="arbitrary_command_enabled" value="false" />
        <Kpi label="execution_enabled" value="false" />
        <Kpi label="token_printed" value="false" />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <ControlPlaneWorkerListPanel workers={workers} />
          <ControlPlaneWorkerDetailPanel worker={workers[0] ?? fixtureWorkerRegistration} heartbeat={heartbeat} />
          <ControlPlanePairingStorePanel />
          <ControlPlaneApprovalPanel approvals={approvals} />
          <ControlPlaneApprovalStorePanel />
          <ControlPlaneCompletedRunsPanel />
        </div>
        <aside className="dashboard-grid__side">
          <ControlPlaneDisabledBanner />
          <ControlPlanePairingPanel pairing={pairing} />
          <ControlPlanePollingPreviewPanel />
          <ControlPlaneResourceBlockersPanel heartbeat={heartbeat} />
          <ControlPlaneQueuePreviewPanel heartbeat={heartbeat} />
          <ControlPlaneResidentStatePanel heartbeat={heartbeat} />
          <ControlPlaneEvidencePanel />
          <ControlPlaneReviewHoldsPanel heartbeat={heartbeat} />
        </aside>
      </section>
      {data.error ? <p className="skybridge-error">{data.error}</p> : null}
    </div>
  );
}

function ControlPlaneDisabledBanner() {
  return (
    <section className="skybridge-panel control-plane-disabled-banner" aria-label="No execution enabled banner">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Boundary</p>
          <h2>No Execution Enabled</h2>
        </div>
        <span className={badgeClass("bad")}>disabled</span>
      </div>
      <ul className="summary-lines">
        <li>Remote execution disabled banner: remote_execution_enabled=false</li>
        <li>Server dispatch disabled: arbitrary_command_enabled=false</li>
        <li>No arbitrary command banner: arbitrary_command_enabled=false</li>
        <li>Queue apply disabled: queue_apply_enabled=false</li>
        <li>No execute button, no run button, no apply button, no command text box, no raw logs</li>
      </ul>
    </section>
  );
}

function ControlPlaneWorkerListPanel({ workers }: { workers: ControlPlaneWorkerRegistration[] }) {
  return (
    <section className="skybridge-panel control-plane-worker-list" aria-label="Worker list">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Workers</p>
          <h2>Worker List</h2>
        </div>
        <span className="skybridge-state">{workers.length}</span>
      </div>
      <div className="data-table data-table--workers">
        <div className="data-table__head">
          <span>Worker</span>
          <span>Repo</span>
          <span>Capabilities</span>
          <span>Execution boundary</span>
        </div>
        {workers.map((worker) => (
          <div className="data-table__row" key={worker.worker_id}>
            <span>{worker.display_name}<small>{worker.worker_id} · {worker.device_id_hash}</small></span>
            <span>{worker.repo}<small>{worker.branch} · {worker.commit}</small></span>
            <span>{worker.capabilities.join(", ")}<small>{worker.resource_policy_summary}</small></span>
            <span>execution_enabled={String(worker.execution_enabled)}<small>remote_execution_enabled={String(worker.remote_execution_enabled)}</small></span>
          </div>
        ))}
      </div>
    </section>
  );
}

function ControlPlaneWorkerDetailPanel({
  worker,
  heartbeat,
}: {
  worker: ControlPlaneWorkerRegistration;
  heartbeat: ControlPlaneWorkerHeartbeat;
}) {
  return (
    <section className="skybridge-panel control-plane-worker-detail" aria-label="Worker detail status">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Status</p>
          <h2>Worker Detail / Status</h2>
        </div>
        <span className={badgeClass(heartbeat.resource_gate_status === "pass" ? "ok" : "bad")}>{heartbeat.resource_gate_status}</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Identity</dt><dd>{worker.worker_id}; paired={String(worker.paired)}; pairing_state={worker.pairing_state}</dd></div>
        <div><dt>Resident worker state</dt><dd>resident_enabled={String(heartbeat.resident_enabled)}; execution_enabled={String(heartbeat.execution_enabled)}</dd></div>
        <div><dt>Resource state</dt><dd>active_tasks={heartbeat.active_tasks}; stale_leases={heartbeat.stale_leases}; runner_lock={heartbeat.runner_lock}</dd></div>
        <div><dt>Safe ingest</dt><dd>raw logs=false; raw prompts=false; token_printed=false</dd></div>
      </dl>
    </section>
  );
}

function ControlPlanePairingPanel({ pairing }: { pairing: ControlPlaneWorkerPairingPreview }) {
  return (
    <SummaryCard
      title="Pairing preview"
      state={pairing.pairing_state}
      lines={[
        `paired=${String(pairing.paired)}`,
        `pairing_code_hash=${pairing.pairing_code_hash}`,
        `pairing_code_raw_persisted=${String(pairing.pairing_code_raw_persisted)}`,
        `execution_enabled=${String(pairing.execution_enabled)}`,
        `arbitrary_command_enabled=${String(pairing.arbitrary_command_enabled)}`,
      ]}
    />
  );
}

function ControlPlanePairingStorePanel() {
  const pairing = fixtureWorkerPairingRecord;
  return (
    <section className="skybridge-panel control-plane-pairing-store-list" aria-label="Pairing store list">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Pairing Store</p>
          <h2>Pairing store list</h2>
        </div>
        <span className={badgeClass("bad")}>{pairing.pairing_state}</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Pairing record detail</dt><dd>{`${pairing.pairing_id}; worker=${pairing.worker_id}`}</dd></div>
        <div><dt>Pairing expired/revoked status</dt><dd>{`expires=${formatDateTime(pairing.expires_at)}; revoked=${pairing.revoked_at ?? "none"}`}</dd></div>
        <div><dt>Secret persistence</dt><dd>{`raw_pairing_code_persisted=${String(pairing.raw_pairing_code_persisted)}; token_printed=${String(pairing.token_printed)}`}</dd></div>
        <div><dt>Execution flags</dt><dd>{`execution_enabled=${String(pairing.execution_enabled)}; remote_execution_enabled=${String(pairing.remote_execution_enabled)}; arbitrary_command_enabled=${String(pairing.arbitrary_command_enabled)}`}</dd></div>
      </dl>
    </section>
  );
}

function ControlPlaneApprovalStorePanel() {
  const approval = fixtureOperatorApprovalRecord;
  return (
    <section className="skybridge-panel control-plane-approval-store-list" aria-label="Approval store list">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Approval Store</p>
          <h2>Approval store list</h2>
        </div>
        <span className={badgeClass("bad")}>{approval.state}</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Approval detail</dt><dd>{`${approval.approval_id}; ${approval.requested_action}`}</dd></div>
        <div><dt>Approval audit state</dt><dd>{`audit_required=${String(approval.audit_required)}; redaction_required=${String(approval.redaction_required)}`}</dd></div>
        <div><dt>Execution decision</dt><dd>{`can_execute_now=${String(approval.can_execute_now)}; max_codex_executions=${approval.max_codex_executions}; max_task_prs=${approval.max_task_prs}`}</dd></div>
        <div><dt>Review gates</dt><dd>{`resource_gate_required=${String(approval.resource_gate_required)}; human_review_required=${String(approval.human_review_required)}`}</dd></div>
      </dl>
    </section>
  );
}

function ControlPlanePollingPreviewPanel() {
  const polling = fixtureResidentPollingReport;
  return (
    <section className="skybridge-panel control-plane-polling-preview-events" aria-label="Worker polling status">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Resident Polling</p>
          <h2>Worker polling status</h2>
        </div>
        <span className={badgeClass("bad")}>preview only</span>
      </div>
      <dl className="queue-definition-list">
        <div><dt>Polling preview events</dt><dd>{`iterations=${polling.iterations.length}; ${polling.status.last_poll_summary}`}</dd></div>
        <div><dt>Blockers</dt><dd>{polling.status.blockers.map((blocker) => blocker.blocker_id).join("; ") || "none"}</dd></div>
        <div><dt>No execution enabled</dt><dd>{`execution_enabled=${String(polling.policy.execution_enabled)}; claim_enabled=${String(polling.policy.claim_enabled)}; queue_apply_enabled=${String(polling.policy.queue_apply_enabled)}`}</dd></div>
        <div><dt>Next interval</dt><dd>{`${polling.policy.poll_interval_seconds}s; no_next_execution_authorized=${String(polling.policy.no_next_execution_authorized)}`}</dd></div>
      </dl>
    </section>
  );
}

function ControlPlaneResourceBlockersPanel({ heartbeat }: { heartbeat: ControlPlaneWorkerHeartbeat }) {
  return (
    <SummaryCard
      title="Resource blockers"
      state={heartbeat.resource_gate_status}
      lines={[
        `Blockers: ${heartbeat.resource_gate_blockers.join("; ") || "none"}`,
        `Active tasks: ${heartbeat.active_tasks}`,
        `Stale leases: ${heartbeat.stale_leases}`,
        `Open review hold: ${String(heartbeat.open_review_hold)}`,
      ]}
    />
  );
}

function ControlPlaneQueuePreviewPanel({ heartbeat }: { heartbeat: ControlPlaneWorkerHeartbeat }) {
  return (
    <SummaryCard
      title="Queue preview"
      state={`${heartbeat.queue_preview.queued_workunits} queued`}
      lines={[
        `Runnable: ${heartbeat.queue_preview.runnable_workunits}`,
        `would_create_tasks=${String(heartbeat.queue_preview.would_create_tasks)}`,
        `would_claim_tasks=${String(heartbeat.queue_preview.would_claim_tasks)}`,
        `would_execute_tasks=${String(heartbeat.queue_preview.would_execute_tasks)}`,
      ]}
    />
  );
}

function ControlPlaneResidentStatePanel({ heartbeat }: { heartbeat: ControlPlaneWorkerHeartbeat }) {
  return (
    <SummaryCard
      title="Resident worker state"
      state={heartbeat.resident_enabled ? "resident enabled" : "resident disabled"}
      lines={[
        `drain_pause_state=${String(heartbeat.drain_pause_state)}`,
        `emergency_stop_preview_state=${String(heartbeat.emergency_stop_preview_state)}`,
        `queue_apply_enabled=${String(heartbeat.queue_apply_enabled)}`,
        `token_printed=${String(heartbeat.token_printed)}`,
      ]}
    />
  );
}

function ControlPlaneApprovalPanel({
  approvals,
}: {
  approvals: Array<{
    request: ControlPlaneOperatorApprovalRequest;
    state: ControlPlaneOperatorApprovalState;
    gate: ControlPlaneOperatorApprovalGate;
  }>;
}) {
  return (
    <section className="skybridge-panel control-plane-approval-panel" aria-label="Pending approval">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Operator Approval</p>
          <h2>Pending Approval / Approval State</h2>
        </div>
        <span className="skybridge-state">{approvals.length}</span>
      </div>
      <ol className="rich-list">
        {approvals.map((approval) => (
          <li key={approval.request.approval_request_id}>
            <div>
              <strong>{approval.request.requested_action}</strong>
              <small>{approval.state.approval_state} · expires {formatDateTime(approval.request.expires_at)}</small>
              <small>approval_does_not_execute={String(approval.gate.approval_does_not_execute)}; allowed_to_execute={String(approval.gate.allowed_to_execute)}</small>
            </div>
            <span className={badgeClass("bad")}>preview controls only</span>
          </li>
        ))}
      </ol>
      <div className="queue-placeholder-controls">
        <button type="button" disabled aria-disabled="true">Approve preview disabled</button>
        <button type="button" disabled aria-disabled="true">Reject preview disabled</button>
      </div>
    </section>
  );
}

function ControlPlaneCompletedRunsPanel() {
  return (
    <SummaryCard
      title="Completed runs"
      state="safe evidence only"
      lines={[
        "Workunit A completed: true",
        "Workunit B completed: true",
        "No next execution authorized: true",
        "No raw logs or transcripts stored",
      ]}
    />
  );
}

function ControlPlaneEvidencePanel() {
  return (
    <SummaryCard
      title="Evidence summary"
      state="metadata only"
      lines={[
        "Schemas added for Goal 218",
        "Server preview routes do not execute",
        "Desktop heartbeat export matches worker_heartbeat.v1",
        "ready_for_goal_219 depends on checks",
      ]}
    />
  );
}

function ControlPlaneReviewHoldsPanel({ heartbeat }: { heartbeat: ControlPlaneWorkerHeartbeat }) {
  return (
    <SummaryCard
      title="Open review holds"
      state={heartbeat.open_review_hold ? "hold" : "none"}
      lines={[
        `open_review_hold=${String(heartbeat.open_review_hold)}`,
        "Human PR review remains required",
        "Approval cannot bypass finalizer",
        "Approval cannot bypass resource gate",
      ]}
    />
  );
}

function useControlPlaneData(apiBase: string) {
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);
  const [workers, setWorkers] = useState<
    Array<{
      registration: ControlPlaneWorkerRegistration;
      pairing_preview?: ControlPlaneWorkerPairingPreview;
      heartbeat?: ControlPlaneWorkerHeartbeat;
      token_printed: false;
    }>
  >([]);
  const [approvals, setApprovals] = useState<
    Array<{
      request: ControlPlaneOperatorApprovalRequest;
      state: ControlPlaneOperatorApprovalState;
      gate: ControlPlaneOperatorApprovalGate;
    }>
  >([]);
  const [error, setError] = useState<string | undefined>();

  useEffect(() => {
    let cancelled = false;
    void Promise.all([
      client.listControlPlaneWorkers(),
      client.listControlPlaneApprovals(),
    ])
      .then(([nextWorkers, nextApprovals]) => {
        if (cancelled) return;
        setWorkers(nextWorkers);
        setApprovals(nextApprovals);
        setError(undefined);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : String(err));
      });
    return () => {
      cancelled = true;
    };
  }, [client]);

  return { workers, approvals, error };
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
  if (route === "control-plane") return "Control Plane";
  if (route === "local-session") return "Local Session";
  if (route === "product-readiness") return "Product Readiness";
  if (route === "first-run") return "First-run";
  if (route === "release") return "Release";
  if (route === "audit") return "Reliability Audit";
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
