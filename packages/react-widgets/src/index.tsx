import React, { useEffect, useMemo, useState } from "react";
import {
  SkyBridgeClient,
  type EventListQuery,
  type NotificationListQuery,
  type RunListQuery,
  type SkyBridgeHealth,
  type StoredNotification
} from "@skybridge-agent-hub/client";
import type { RunDetail, RunSummary, SkyBridgeEvent, SkyBridgeSeverity, SkyBridgeSourcePlatform } from "@skybridge-agent-hub/event-schema";

export interface WidgetProps {
  apiBase: string;
}

export interface SourceFilters {
  platform?: SkyBridgeSourcePlatform | "all";
  adapter?: string;
  severity?: SkyBridgeSeverity | "all";
  type?: string;
  status?: RunSummary["status"] | "all";
}

export interface SkyBridgeState {
  health?: SkyBridgeHealth;
  events: SkyBridgeEvent[];
  runs: RunSummary[];
  notifications: StoredNotification[];
  loading: boolean;
  error?: string;
  streamState: "connecting" | "connected" | "reconnecting" | "unavailable";
  refresh: () => Promise<void>;
}

export function useSkyBridge(apiBase: string, filters: SourceFilters = {}): SkyBridgeState {
  const [health, setHealth] = useState<SkyBridgeHealth | undefined>();
  const [events, setEvents] = useState<SkyBridgeEvent[]>([]);
  const [runs, setRuns] = useState<RunSummary[]>([]);
  const [notifications, setNotifications] = useState<StoredNotification[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | undefined>();
  const [streamState, setStreamState] = useState<SkyBridgeState["streamState"]>("connecting");
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);
  const queryKey = JSON.stringify(filters);

  const refresh = useMemo(() => async () => {
    setLoading(true);
    try {
      const [nextHealth, nextEvents, nextRuns, nextNotifications] = await Promise.all([
        client.getHealth(),
        client.listEvents(toEventQuery(filters)),
        client.listRuns(toRunQuery(filters)),
        client.listNotifications()
      ]);
      setHealth(nextHealth);
      setEvents(nextEvents);
      setRuns(nextRuns);
      setNotifications(nextNotifications);
      setError(undefined);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, [client, queryKey]);

  useEffect(() => {
    let closed = false;
    void refresh();

    if (typeof EventSource === "undefined") {
      setStreamState("unavailable");
      return () => {
        closed = true;
      };
    }

    const stream = client.streamEvents({
      onOpen: () => {
        if (!closed) setStreamState("connected");
      },
      onError: () => {
        if (!closed) {
          setStreamState("reconnecting");
          setError("SSE stream disconnected; retrying.");
        }
      },
      onEvent: (event) => {
        if (closed || !matchesFilters(event, filters)) return;
        setEvents((prev) => [...prev, event].slice(-200));
        void client.listRuns(toRunQuery(filters)).then(setRuns).catch(() => undefined);
      }
    });

    return () => {
      closed = true;
      stream.close();
    };
  }, [client, refresh, queryKey]);

  return { health, events, runs, notifications, loading, error, streamState, refresh };
}

export function LoadingState({ label = "Loading" }: { label?: string }) {
  return <p className="skybridge-state-note">{label}</p>;
}

export function ErrorState({ message }: { message: string }) {
  return <p className="skybridge-error">{message}</p>;
}

export function EmptyState({ title = "No data", detail }: { title?: string; detail?: string }) {
  return (
    <div className="skybridge-empty">
      <strong>{title}</strong>
      {detail ? <p>{detail}</p> : null}
    </div>
  );
}

export function SkyBridgeHealthCard({ apiBase }: WidgetProps) {
  const { health, runs, events, notifications, loading, error, streamState } = useSkyBridge(apiBase);
  const failedRuns = runs.filter((run) => run.status === "failed").length;
  const status = error ? "offline" : failedRuns ? "attention" : events.length ? "active" : "idle";

  return (
    <section className="skybridge-card">
      <PanelHeader kicker="System Health" title="SkyBridge" state={status} bad={status === "offline" || status === "attention"} />
      {loading && !health ? <LoadingState label="Checking API" /> : null}
      <dl className="skybridge-metrics">
        <Metric label="Persistence" value={health?.persistence ?? "unknown"} />
        <Metric label="Stream" value={streamState} />
        <Metric label="Runs" value={runs.length} />
        <Metric label="Attention" value={failedRuns + notifications.filter((item) => item.status === "failed" || item.status === "skipped").length} />
      </dl>
      <p className="skybridge-runline">Last event: {events.at(-1)?.type ?? "none"} · Server time: {formatDateTime(health?.time)}</p>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function ActiveRunsPanel({ apiBase, filters = {}, selectedRunId, onSelectRun }: WidgetProps & {
  filters?: SourceFilters;
  selectedRunId?: string;
  onSelectRun?: (runId: string) => void;
}) {
  const { runs, loading, error } = useSkyBridge(apiBase, filters);

  return (
    <section className="skybridge-panel">
      <PanelHeader kicker="Runs" title="Active And Recent" state={`${runs.length}`} />
      {loading && runs.length === 0 ? <LoadingState label="Loading runs" /> : null}
      {!loading && runs.length === 0 ? <EmptyState title="No runs match" detail="Adjust the source filters or seed demo events." /> : null}
      <ol className="skybridge-run-list">
        {runs.map((run) => (
          <li key={run.run_id}>
            <button className={selectedRunId === run.run_id ? "is-selected" : ""} type="button" onClick={() => onSelectRun?.(run.run_id)}>
              <span>
                <strong>{run.title ?? run.run_id}</strong>
                <small>{run.source_platform}/{run.source_adapter} · {run.branch ?? run.goal ?? "no branch or goal"}</small>
              </span>
              <span className={`skybridge-state ${run.status === "failed" ? "skybridge-state--bad" : ""}`}>{run.status}</span>
              <small>{run.tool_call_count} tools · {run.failed_tool_count} failed · {formatDateTime(run.last_seen_at)}</small>
            </button>
          </li>
        ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function EventTimeline({ apiBase, filters = {} }: WidgetProps & { filters?: SourceFilters }) {
  const { events, loading, error, streamState } = useSkyBridge(apiBase, filters);

  return (
    <section className="skybridge-panel">
      <PanelHeader kicker="Events" title="Timeline" state={streamState} bad={streamState === "unavailable"} />
      {loading && events.length === 0 ? <LoadingState label="Loading events" /> : null}
      {!loading && events.length === 0 ? <EmptyState title="No events match" detail="The timeline will update when telemetry arrives." /> : null}
      <ol className="skybridge-timeline">
        {events.slice(-50).reverse().map((event, index) => (
          <li key={event.event_id ?? `${event.time}-${index}`}>
            <span>
              <strong>{event.type}</strong>
              <small>{event.severity} · {event.correlation?.run_id ?? event.correlation?.session_id ?? "uncorrelated"}</small>
            </span>
            <small>{event.source.platform}/{event.source.adapter} · {formatDateTime(event.time)}</small>
          </li>
        ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function RunDetailPanel({ apiBase, runId }: WidgetProps & { runId?: string }) {
  const [detail, setDetail] = useState<RunDetail | undefined>();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    if (!runId) {
      setDetail(undefined);
      return;
    }
    setLoading(true);
    void client.getRun(runId, { limit: 100 })
      .then((nextDetail) => {
        setDetail(nextDetail);
        setError(undefined);
      })
      .catch((err) => setError(err instanceof Error ? err.message : String(err)))
      .finally(() => setLoading(false));
  }, [client, runId]);

  return (
    <section className="skybridge-panel">
      <PanelHeader kicker="Run Detail" title={detail?.summary.title ?? runId ?? "No run selected"} state={detail?.summary.status ?? "idle"} bad={detail?.summary.status === "failed"} />
      {!runId ? <EmptyState title="Select a run" detail="Run details show safe metadata and recent events." /> : null}
      {loading ? <LoadingState label="Loading run" /> : null}
      {detail ? (
        <>
          <dl className="skybridge-metrics skybridge-metrics--compact">
            <Metric label="Source" value={`${detail.summary.source_platform}/${detail.summary.source_adapter}`} />
            <Metric label="Tools" value={detail.summary.tool_call_count} />
            <Metric label="Failed" value={detail.summary.failed_tool_count} />
            <Metric label="Events" value={detail.summary.event_count} />
          </dl>
          <p className="skybridge-runline">{detail.summary.goal ?? detail.summary.latest_message_summary ?? "No safe summary yet"}</p>
          <ol className="skybridge-timeline skybridge-timeline--compact">
            {detail.events.slice(-12).reverse().map((event, index) => (
              <li key={event.event_id ?? `${event.time}-${index}`}>
                <span>{event.type}</span>
                <small>{event.severity} · {formatDateTime(event.time)}</small>
              </li>
            ))}
          </ol>
        </>
      ) : null}
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function NotificationList({ apiBase, filters = {} }: WidgetProps & { filters?: NotificationListQuery }) {
  const [items, setItems] = useState<StoredNotification[]>([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);
  const queryKey = JSON.stringify(filters);

  useEffect(() => {
    void client.listNotifications(filters)
      .then((notifications) => {
        setItems(notifications);
        setError(undefined);
      })
      .catch((err) => setError(err instanceof Error ? err.message : String(err)));
  }, [client, queryKey]);

  return (
    <section className="skybridge-panel">
      <PanelHeader kicker="Attention" title="Notifications" state={`${items.length}`} bad={items.some((item) => item.status === "failed")} />
      {items.length === 0 ? <EmptyState title="No notifications" detail="Failed runs, approvals and notification attempts appear here." /> : null}
      <ol className="skybridge-timeline skybridge-timeline--compact">
        {items.slice(-20).reverse().map((item) => (
          <li key={item.id}>
            <span>
              <strong>{item.message.title}</strong>
              <small>{item.provider} · {item.status}{item.error ? ` · ${item.error}` : ""}</small>
            </span>
            <small>{formatDateTime(item.createdAt)}</small>
          </li>
        ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function SourceFilterBar({ filters, onChange }: {
  filters: SourceFilters;
  onChange: (filters: SourceFilters) => void;
}) {
  return (
    <section className="skybridge-filterbar" aria-label="Source filters">
      <label>
        Platform
        <select value={filters.platform ?? "all"} onChange={(event) => onChange({ ...filters, platform: event.currentTarget.value as SourceFilters["platform"] })}>
          <option value="all">All</option>
          <option value="codex">Codex</option>
          <option value="skybridge">SkyBridge</option>
          <option value="opencode">OpenCode</option>
          <option value="hermes">Hermes</option>
          <option value="custom">Custom</option>
        </select>
      </label>
      <label>
        Adapter
        <input value={filters.adapter ?? ""} placeholder="any adapter" onChange={(event) => onChange({ ...filters, adapter: event.currentTarget.value || undefined })} />
      </label>
      <label>
        Severity
        <select value={filters.severity ?? "all"} onChange={(event) => onChange({ ...filters, severity: event.currentTarget.value as SourceFilters["severity"] })}>
          <option value="all">All</option>
          <option value="info">Info</option>
          <option value="warning">Warning</option>
          <option value="error">Error</option>
          <option value="critical">Critical</option>
        </select>
      </label>
      <label>
        Run status
        <select value={filters.status ?? "all"} onChange={(event) => onChange({ ...filters, status: event.currentTarget.value as SourceFilters["status"] })}>
          <option value="all">All</option>
          <option value="running">Running</option>
          <option value="completed">Completed</option>
          <option value="failed">Failed</option>
          <option value="unknown">Unknown</option>
        </select>
      </label>
    </section>
  );
}

export interface SelfObservationSummary {
  status: "idle" | "observing" | "attention";
  active_runs: number;
  failed_runs: number;
  codex_events: number;
  runner_events: number;
  smoke_events: number;
  notification_events: number;
  latest_lifecycle?: string;
}

export interface CodexIntegrationSummary {
  status: "idle" | "active" | "attention";
  recent_runs: RunSummary[];
  latest_hook_event?: SkyBridgeEvent;
  hook_event_count: number;
  failed_tool_count: number;
  active_tool_count: number;
  spool_count?: number;
}

export function summarizeCodexIntegration(runs: RunSummary[], events: SkyBridgeEvent[]): CodexIntegrationSummary {
  const codexRuns = runs.filter((run) => run.source_platform === "codex");
  const hookEvents = events.filter((event) => event.source.platform === "codex" && event.source.adapter === "codex-hook");
  const latestHookEvent = hookEvents.at(-1);
  const failedToolCount = codexRuns.reduce((sum, run) => sum + run.failed_tool_count, 0);
  const activeToolCount = codexRuns.reduce((sum, run) => sum + run.active_tool_count, 0);
  const spoolCount = latestSpoolCount(hookEvents);

  return {
    status: failedToolCount > 0 ? "attention" : hookEvents.length > 0 || codexRuns.some((run) => run.status === "running") ? "active" : "idle",
    recent_runs: codexRuns.slice(0, 5),
    latest_hook_event: latestHookEvent,
    hook_event_count: hookEvents.length,
    failed_tool_count: failedToolCount,
    active_tool_count: activeToolCount,
    spool_count: spoolCount
  };
}

export function CodexIntegrationStatus({ apiBase }: WidgetProps) {
  const { events, runs, error } = useSkyBridge(apiBase, { platform: "codex" });
  const summary = summarizeCodexIntegration(runs, events);

  return (
    <section className="skybridge-panel skybridge-codex-integration">
      <PanelHeader kicker="Codex Local" title="Integration Status" state={summary.status} bad={summary.status === "attention"} />
      <dl className="skybridge-metrics skybridge-metrics--compact">
        <Metric label="Runs" value={summary.recent_runs.length} />
        <Metric label="Hook events" value={summary.hook_event_count} />
        <Metric label="Active tools" value={summary.active_tool_count} />
        <Metric label="Failed tools" value={summary.failed_tool_count} />
      </dl>
      <p className="skybridge-runline">Last hook: {summary.latest_hook_event?.type ?? "none"} · Spool: {summary.spool_count ?? "local only"}</p>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function summarizeSelfObservation(runs: RunSummary[], events: SkyBridgeEvent[]): SelfObservationSummary {
  const selfEvents = events.filter((event) => event.source.platform === "codex" || event.source.platform === "skybridge");
  const latestLifecycle = [...selfEvents].reverse().map((event) => safePayloadString(event.payload.lifecycle)).find(Boolean);
  const failedRuns = runs.filter((run) => run.status === "failed").length;
  const activeRuns = runs.filter((run) => run.status === "running").length;

  return {
    status: failedRuns > 0 ? "attention" : selfEvents.length > 0 || activeRuns > 0 ? "observing" : "idle",
    active_runs: activeRuns,
    failed_runs: failedRuns,
    codex_events: selfEvents.filter((event) => event.source.platform === "codex").length,
    runner_events: selfEvents.filter((event) => event.source.adapter === "yolo-runner").length,
    smoke_events: selfEvents.filter((event) => event.source.adapter === "self-observation-smoke").length,
    notification_events: selfEvents.filter((event) => event.type.startsWith("notification.")).length,
    latest_lifecycle: latestLifecycle
  };
}

export function SelfObservationPanel({ apiBase }: WidgetProps) {
  const { events, runs, error } = useSkyBridge(apiBase);
  const summary = summarizeSelfObservation(runs, events);

  return (
    <section className="skybridge-panel skybridge-self-observation">
      <PanelHeader kicker="Local Loop" title="Self-Observation" state={summary.status} bad={summary.status === "attention"} />
      <dl className="skybridge-metrics skybridge-metrics--compact">
        <Metric label="Codex" value={summary.codex_events} />
        <Metric label="Runner" value={summary.runner_events} />
        <Metric label="Smoke" value={summary.smoke_events} />
        <Metric label="Notify" value={summary.notification_events} />
      </dl>
      <p className="skybridge-runline">{summary.active_runs} active · {summary.failed_runs} failed · {summary.latest_lifecycle ?? "no lifecycle yet"}</p>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function AgentStatusCard(props: WidgetProps) {
  return <SkyBridgeHealthCard {...props} />;
}

export function AgentTimeline(props: WidgetProps) {
  return <EventTimeline {...props} />;
}

export function AgentPipelineBar({ apiBase }: WidgetProps) {
  const { runs } = useSkyBridge(apiBase);
  const counts = {
    running: runs.filter((run) => run.status === "running").length,
    completed: runs.filter((run) => run.status === "completed").length,
    failed: runs.filter((run) => run.status === "failed").length,
    unknown: runs.filter((run) => run.status === "unknown").length
  };
  const total = Math.max(runs.length, 1);

  return (
    <section className="skybridge-panel">
      <PanelHeader kicker="Pipeline" title="Run Distribution" state={`${runs.length}`} />
      <div className="skybridge-pipeline" aria-label="Run status distribution">
        {Object.entries(counts).map(([status, count]) => (
          <span
            key={status}
            className={`skybridge-pipeline__segment skybridge-pipeline__segment--${status}`}
            style={{ width: `${(count / total) * 100}%` }}
            title={`${status}: ${count}`}
          />
        ))}
      </div>
      <p className="skybridge-runline">{counts.running} running · {counts.completed} completed · {counts.failed} failed</p>
    </section>
  );
}

export function CodexIntegrationPanel(props: WidgetProps) {
  return <CodexIntegrationStatus {...props} />;
}

function PanelHeader({ kicker, title, state, bad = false }: { kicker: string; title: string; state: string; bad?: boolean }) {
  return (
    <div className="skybridge-card__header">
      <div>
        <p className="skybridge-kicker">{kicker}</p>
        <h2>{title}</h2>
      </div>
      <span className={`skybridge-state ${bad ? "skybridge-state--bad" : ""}`}>{state}</span>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function toEventQuery(filters: SourceFilters): EventListQuery {
  return {
    platform: filters.platform && filters.platform !== "all" ? filters.platform : undefined,
    adapter: filters.adapter,
    severity: filters.severity && filters.severity !== "all" ? filters.severity : undefined,
    type: filters.type as EventListQuery["type"],
    limit: 200
  };
}

function toRunQuery(filters: SourceFilters): RunListQuery {
  return {
    platform: filters.platform && filters.platform !== "all" ? filters.platform : undefined,
    adapter: filters.adapter,
    status: filters.status && filters.status !== "all" ? filters.status : undefined,
    limit: 200
  };
}

function matchesFilters(event: SkyBridgeEvent, filters: SourceFilters): boolean {
  if (filters.platform && filters.platform !== "all" && event.source.platform !== filters.platform) return false;
  if (filters.adapter && event.source.adapter !== filters.adapter) return false;
  if (filters.severity && filters.severity !== "all" && event.severity !== filters.severity) return false;
  if (filters.type && event.type !== filters.type) return false;
  return true;
}

function formatDateTime(input: string | undefined): string {
  return input ? new Date(input).toLocaleString() : "not yet";
}

function safePayloadString(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 && input.length <= 120 ? input : undefined;
}

function latestSpoolCount(events: SkyBridgeEvent[]): number | undefined {
  for (const event of [...events].reverse()) {
    const value = event.payload.spool_count ?? event.payload.queued_spool_count;
    if (typeof value === "number" && Number.isFinite(value)) return value;
  }
  return undefined;
}
