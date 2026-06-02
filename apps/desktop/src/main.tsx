import React from "react";
import { createRoot } from "react-dom/client";
import { invoke } from "@tauri-apps/api/core";
import "./styles.css";

type DesktopStatus = {
  ok: boolean;
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
  active_tasks: number;
  stale_leases: number;
  token_printed: boolean;
  last_refresh_time: string;
  status_file: string;
  log_file: string;
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
  active_tasks: 0,
  stale_leases: 0,
  token_printed: false,
  last_refresh_time: "",
  status_file: "",
  log_file: "",
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

  const safeCurrent = status.current_goal_linked_task_ids.length === 0 && status.current_goal_linked_pr_urls.length === 0;

  return (
    <main className="shell">
      <header className="topbar">
        <div>
          <h1>SkyBridge Desktop</h1>
          <p>Read-only standby client</p>
        </div>
        <div className={safeCurrent ? "badge badge-safe" : "badge badge-warn"}>
          {safeCurrent ? "Goal 190 unexecuted" : "Goal 190 linked"}
        </div>
      </header>

      <section className="toolbar" aria-label="Status actions">
        <button type="button" onClick={refresh} disabled={busy}>
          Refresh Status
        </button>
        <button type="button" className="heartbeat" onClick={heartbeat} disabled={busy}>
          Heartbeat Now
        </button>
        <span>{message}</span>
      </section>

      <section className="panel">
        <h2>Control Plane</h2>
        <dl>
          <StatusValue label="Worker id" value={status.worker_id} />
          <StatusValue label="Worker status" value={status.worker_status} />
          <StatusValue label="Project id" value={status.project_id} />
          <StatusValue label="Campaign id" value={status.campaign_id} />
          <StatusValue label="Current step" value={`${status.current_goal_id} (${status.current_goal_status})`} />
          <StatusValue label="Previous step" value={`${status.previous_goal_id} (${status.previous_goal_status})`} />
          <StatusValue label="Active tasks" value={status.active_tasks} />
          <StatusValue label="Stale leases" value={status.stale_leases} />
          <StatusValue label="Token printed" value={String(status.token_printed)} />
          <StatusValue label="Last refresh" value={status.last_refresh_time || "not refreshed"} />
        </dl>
      </section>

      <section className="panel">
        <h2>Local Metadata</h2>
        <dl>
          <StatusValue label="Status file" value={status.status_file || ".agent/desktop-client/status.json"} />
          <StatusValue label="Log file" value={status.log_file || ".agent/desktop-client/logs/desktop-client.log"} />
        </dl>
      </section>

      {status.errors.length > 0 ? (
        <section className="panel errors">
          <h2>Bridge Warnings</h2>
          <ul>
            {status.errors.map((error) => (
              <li key={error}>{error}</li>
            ))}
          </ul>
        </section>
      ) : null}
    </main>
  );
}

createRoot(document.getElementById("root") as HTMLElement).render(<App />);
