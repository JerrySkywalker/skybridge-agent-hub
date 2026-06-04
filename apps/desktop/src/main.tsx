import React from "react";
import { createRoot } from "react-dom/client";
import { invoke } from "@tauri-apps/api/core";
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
  status_file: string;
  log_file: string;
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
  status_file: "",
  log_file: "",
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
  const [status, setStatus] = React.useState<DesktopStatus>(emptyStatus);
  const [busy, setBusy] = React.useState(false);
  const [message, setMessage] = React.useState("Standby");
  const [nowSeconds, setNowSeconds] = React.useState(() => Math.floor(Date.now() / 1000));

  const refresh = React.useCallback(async () => {
    setBusy(true);
    setMessage("Refreshing read-only status");
    try {
      const next = await invoke<DesktopStatus>("get_status");
      setStatus(next);
      setMessage("Status refreshed");
    } catch (error) {
      setMessage(`Refresh failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }, []);

  const heartbeat = React.useCallback(async () => {
    setBusy(true);
    setMessage("Sending heartbeat mutation only");
    try {
      const result = await invoke<HeartbeatResult>("heartbeat_now");
      setStatus(result.status);
      setMessage(`Heartbeat sent; worker is ${result.worker_status}`);
    } catch (error) {
      setMessage(`Heartbeat failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }, []);

  React.useEffect(() => {
    void refresh();
  }, [refresh]);

  React.useEffect(() => {
    const timer = window.setInterval(() => setNowSeconds(Math.floor(Date.now() / 1000)), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const refreshEpoch = parseUnixTimestamp(status.last_refresh_time);
  const statusAge = refreshEpoch === null ? "unknown" : `${Math.max(0, nowSeconds - refreshEpoch)}s`;
  const readinessClass = `readiness readiness-${status.pre190_readiness.state.toLowerCase()}`;

  return (
    <main className="shell">
      <header className="topbar">
        <div>
          <h1>SkyBridge Desktop</h1>
          <p>Local resident standby status and heartbeat tool</p>
        </div>
        <div className={readinessClass}>
          Pre-190 {status.pre190_readiness.state}
        </div>
      </header>

      <section className="mode-strip" aria-label="Desktop safety mode">
        <span>{status.mode_banner}</span>
        <span>{status.mutation_scope}</span>
        <span>{status.execution_disabled ? "EXECUTION DISABLED" : "EXECUTION STATE UNKNOWN"}</span>
      </section>

      <section className="toolbar" aria-label="Status actions">
        <button type="button" onClick={refresh} disabled={busy}>
          Refresh Status
        </button>
        <button type="button" className="heartbeat" onClick={heartbeat} disabled={busy}>
          Heartbeat Now (heartbeat-only)
        </button>
        <span>{message}</span>
      </section>

      <section className="panel">
        <h2>Campaign Status</h2>
        <dl>
          <StatusValue label="Project id" value={status.project_id} />
          <StatusValue label="Campaign id" value={status.campaign_id} />
          <StatusValue label="Current step id" value={status.current_step} />
          <StatusValue label="Current goal" value={`${status.current_goal_id} (${status.current_goal_status})`} />
          <StatusValue label="Previous goal" value={`${status.previous_goal_id} (${status.previous_goal_status})`} />
          <StatusValue label="Goal 190 task links" value={status.goal_190_linked_task_ids_count} />
          <StatusValue label="Goal 190 PR links" value={status.goal_190_linked_pr_urls_count} />
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
          <StatusValue label="Bridge warnings" value={status.warnings.length + status.errors.length} />
        </dl>
      </section>

      <section className={readinessClass}>
        <h2>Pre-190 Readiness</h2>
        <p>{status.pre190_readiness.reasons.join("; ")}</p>
      </section>

      <section className="panel">
        <h2>Local Metadata</h2>
        <dl>
          <StatusValue label="Status file" value={status.status_file || ".agent/desktop-client/status.json"} />
          <StatusValue label="Log file" value={status.log_file || ".agent/desktop-client/logs/desktop-client.log"} />
        </dl>
      </section>

      {status.warnings.length > 0 || status.errors.length > 0 ? (
        <section className="panel errors">
          <h2>Bridge Warnings</h2>
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

function formatKnownNumber(value: number | null) {
  return value === null ? "unknown" : value;
}

function parseUnixTimestamp(value: string) {
  if (!value.startsWith("unix:")) {
    return null;
  }
  const parsed = Number.parseInt(value.slice("unix:".length), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

createRoot(document.getElementById("root") as HTMLElement).render(<App />);
