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
  fixtureGoalQueueReviewSummary,
  fixtureQueueControlState,
  fixtureWorkerServiceState,
  queueControlActionMatrix,
  routeAttentionEvent,
  summarizeCampaignEvidence,
  type AttentionEvent,
  type WorkerServiceState,
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
      <GoalQueueReviewPanel />
      <WorkerServicePanel service={workerService} readiness={workerReadiness} />

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
        <button type="button" disabled aria-disabled="true" title="Bounded local supervisor apply remains CLI-only and disabled for Goal 195 review">
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
