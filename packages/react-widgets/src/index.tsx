import React, { useEffect, useMemo, useState } from "react";
import {
  SkyBridgeClient,
  type EventListQuery,
  type NotificationListQuery,
  type RunListQuery,
  type ApprovalSummary,
  type MetricsResponse,
  type SkyBridgeHealth,
  type SupervisorNextAction,
  type SupervisorStatus,
  type StoredNotification,
} from "@skybridge-agent-hub/client";
import type {
  IterationRun,
  RunDetail,
  RunSummary,
  SkyBridgeEvent,
  SkyBridgeSeverity,
  SkyBridgeSourcePlatform,
} from "@skybridge-agent-hub/event-schema";

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

export function useSkyBridge(
  apiBase: string,
  filters: SourceFilters = {},
): SkyBridgeState {
  const [health, setHealth] = useState<SkyBridgeHealth | undefined>();
  const [events, setEvents] = useState<SkyBridgeEvent[]>([]);
  const [runs, setRuns] = useState<RunSummary[]>([]);
  const [notifications, setNotifications] = useState<StoredNotification[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | undefined>();
  const [streamState, setStreamState] =
    useState<SkyBridgeState["streamState"]>("connecting");
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);
  const queryKey = JSON.stringify(filters);

  const refresh = useMemo(
    () => async () => {
      setLoading(true);
      try {
        const [nextHealth, nextEvents, nextRuns, nextNotifications] =
          await Promise.all([
            client.getHealth(),
            client.listEvents(toEventQuery(filters)),
            client.listRuns(toRunQuery(filters)),
            client.listNotifications(),
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
    },
    [client, queryKey],
  );

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
        void client
          .listRuns(toRunQuery(filters))
          .then(setRuns)
          .catch(() => undefined);
      },
    });

    return () => {
      closed = true;
      stream.close();
    };
  }, [client, refresh, queryKey]);

  return {
    health,
    events,
    runs,
    notifications,
    loading,
    error,
    streamState,
    refresh,
  };
}

export function LoadingState({ label = "Loading" }: { label?: string }) {
  return <p className="skybridge-state-note">{label}</p>;
}

export function ErrorState({ message }: { message: string }) {
  return <p className="skybridge-error">{message}</p>;
}

export function EmptyState({
  title = "No data",
  detail,
}: {
  title?: string;
  detail?: string;
}) {
  return (
    <div className="skybridge-empty">
      <strong>{title}</strong>
      {detail ? <p>{detail}</p> : null}
    </div>
  );
}

export function SkyBridgeHealthCard({ apiBase }: WidgetProps) {
  const { health, runs, events, notifications, loading, error, streamState } =
    useSkyBridge(apiBase);
  const failedRuns = runs.filter((run) => run.status === "failed").length;
  const status = error
    ? "offline"
    : failedRuns
      ? "attention"
      : events.length
        ? "active"
        : "idle";

  return (
    <section className="skybridge-card">
      <PanelHeader
        kicker="System Health"
        title="SkyBridge"
        state={status}
        bad={status === "offline" || status === "attention"}
      />
      {loading && !health ? <LoadingState label="Checking API" /> : null}
      <dl className="skybridge-metrics">
        <Metric label="Persistence" value={health?.persistence ?? "unknown"} />
        <Metric label="Stream" value={streamState} />
        <Metric label="Runs" value={runs.length} />
        <Metric
          label="Attention"
          value={
            failedRuns +
            notifications.filter(
              (item) => item.status === "failed" || item.status === "skipped",
            ).length
          }
        />
      </dl>
      <p className="skybridge-runline">
        Last event: {events.at(-1)?.type ?? "none"} · Server time:{" "}
        {formatDateTime(health?.time)}
      </p>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function ActiveRunsPanel({
  apiBase,
  filters = {},
  selectedRunId,
  onSelectRun,
}: WidgetProps & {
  filters?: SourceFilters;
  selectedRunId?: string;
  onSelectRun?: (runId: string) => void;
}) {
  const { runs, loading, error } = useSkyBridge(apiBase, filters);

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Runs"
        title="Active And Recent"
        state={`${runs.length}`}
      />
      {loading && runs.length === 0 ? (
        <LoadingState label="Loading runs" />
      ) : null}
      {!loading && runs.length === 0 ? (
        <EmptyState
          title="No runs match"
          detail="Adjust the source filters or seed demo events."
        />
      ) : null}
      <ol className="skybridge-run-list">
        {runs.map((run) => (
          <li key={run.run_id}>
            <button
              className={selectedRunId === run.run_id ? "is-selected" : ""}
              type="button"
              onClick={() => onSelectRun?.(run.run_id)}
            >
              <span>
                <strong>{run.title ?? run.run_id}</strong>
                <small>
                  {run.source_platform}/{run.source_adapter} ·{" "}
                  {run.branch ?? run.goal ?? "no branch or goal"}
                </small>
              </span>
              <span
                className={`skybridge-state ${run.status === "failed" ? "skybridge-state--bad" : ""}`}
              >
                {run.status}
              </span>
              <small>
                {run.tool_call_count} tools · {run.failed_tool_count} failed ·{" "}
                {formatDateTime(run.last_seen_at)}
              </small>
            </button>
          </li>
        ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function EventTimeline({
  apiBase,
  filters = {},
}: WidgetProps & { filters?: SourceFilters }) {
  const { events, loading, error, streamState } = useSkyBridge(
    apiBase,
    filters,
  );

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Events"
        title="Timeline"
        state={streamState}
        bad={streamState === "unavailable"}
      />
      {loading && events.length === 0 ? (
        <LoadingState label="Loading events" />
      ) : null}
      {!loading && events.length === 0 ? (
        <EmptyState
          title="No events match"
          detail="The timeline will update when telemetry arrives."
        />
      ) : null}
      <ol className="skybridge-timeline">
        {events
          .slice(-50)
          .reverse()
          .map((event, index) => (
            <li key={event.event_id ?? `${event.time}-${index}`}>
              <span>
                <strong>{event.type}</strong>
                <small>
                  {event.severity} ·{" "}
                  {event.correlation?.run_id ??
                    event.correlation?.session_id ??
                    "uncorrelated"}
                </small>
              </span>
              <small>
                {event.source.platform}/{event.source.adapter} ·{" "}
                {formatDateTime(event.time)}
              </small>
            </li>
          ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function RunDetailPanel({
  apiBase,
  runId,
}: WidgetProps & { runId?: string }) {
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
    void client
      .getRun(runId, { limit: 100 })
      .then((nextDetail) => {
        setDetail(nextDetail);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      )
      .finally(() => setLoading(false));
  }, [client, runId]);

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Run Detail"
        title={detail?.summary.title ?? runId ?? "No run selected"}
        state={detail?.summary.status ?? "idle"}
        bad={detail?.summary.status === "failed"}
      />
      {!runId ? (
        <EmptyState
          title="Select a run"
          detail="Run details show safe metadata and recent events."
        />
      ) : null}
      {loading ? <LoadingState label="Loading run" /> : null}
      {detail ? (
        <>
          <dl className="skybridge-metrics skybridge-metrics--compact">
            <Metric
              label="Source"
              value={`${detail.summary.source_platform}/${detail.summary.source_adapter}`}
            />
            <Metric label="Tools" value={detail.summary.tool_call_count} />
            <Metric label="Failed" value={detail.summary.failed_tool_count} />
            <Metric label="Events" value={detail.summary.event_count} />
          </dl>
          <p className="skybridge-runline">
            {detail.summary.goal ??
              detail.summary.latest_message_summary ??
              "No safe summary yet"}
          </p>
          <ol className="skybridge-timeline skybridge-timeline--compact">
            {detail.events
              .slice(-12)
              .reverse()
              .map((event, index) => (
                <li key={event.event_id ?? `${event.time}-${index}`}>
                  <span>{event.type}</span>
                  <small>
                    {event.severity} · {formatDateTime(event.time)}
                  </small>
                </li>
              ))}
          </ol>
        </>
      ) : null}
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function NotificationList({
  apiBase,
  filters = {},
}: WidgetProps & { filters?: NotificationListQuery }) {
  const [items, setItems] = useState<StoredNotification[]>([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);
  const queryKey = JSON.stringify(filters);

  useEffect(() => {
    void client
      .listNotifications(filters)
      .then((notifications) => {
        setItems(notifications);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, [client, queryKey]);

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Attention"
        title="Notifications"
        state={`${items.length}`}
        bad={items.some((item) => item.status === "failed")}
      />
      {items.length === 0 ? (
        <EmptyState
          title="No notifications"
          detail="Failed runs, approvals and notification attempts appear here."
        />
      ) : null}
      <ol className="skybridge-timeline skybridge-timeline--compact">
        {items
          .slice(-20)
          .reverse()
          .map((item) => (
            <li key={item.id}>
              <span>
                <strong>{item.message.title}</strong>
                <small>
                  {item.provider} · {item.status}
                  {item.error ? ` · ${item.error}` : ""}
                </small>
              </span>
              <small>{formatDateTime(item.createdAt)}</small>
            </li>
          ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function ApprovalQueuePanel({ apiBase }: WidgetProps) {
  const [items, setItems] = useState<ApprovalSummary[]>([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    void client
      .listApprovals()
      .then((approvals) => {
        setItems(approvals);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, [client]);

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Operator"
        title="Approval Queue"
        state={`${items.length}`}
        bad={items.length > 0}
      />
      {items.length === 0 ? (
        <EmptyState
          title="No pending approvals"
          detail="Remote execution remains disabled; approvals are recorded for operator workflow testing."
        />
      ) : null}
      <ol className="skybridge-timeline skybridge-timeline--compact">
        {items.map((item) => (
          <li key={item.approval_id}>
            <span>
              <strong>{item.title ?? item.approval_id}</strong>
              <small>
                {item.source} ·{" "}
                {item.run_id ?? item.session_id ?? "uncorrelated"}
              </small>
            </span>
            <small>{formatDateTime(item.requested_at)}</small>
          </li>
        ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function OperationsSummaryPanel({ apiBase }: WidgetProps) {
  const [metrics, setMetrics] = useState<MetricsResponse | undefined>();
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    void client
      .getMetrics()
      .then((nextMetrics) => {
        setMetrics(nextMetrics);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, [client]);

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Operations"
        title="Metrics Summary"
        state={`${metrics?.total_events ?? 0}`}
      />
      <dl className="skybridge-metrics skybridge-metrics--compact">
        <Metric label="Events" value={metrics?.total_events ?? 0} />
        <Metric label="Running" value={metrics?.runs_by_status.running ?? 0} />
        <Metric label="Failed" value={metrics?.runs_by_status.failed ?? 0} />
        <Metric
          label="Nodes"
          value={Object.values(metrics?.node_status_counts ?? {}).reduce(
            (sum, count) => sum + count,
            0,
          )}
        />
      </dl>
      <p className="skybridge-runline">
        Sources:{" "}
        {Object.keys(metrics?.runs_by_source ?? {}).join(", ") || "none"}
      </p>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function ProviderStatusPanel({ apiBase }: WidgetProps) {
  const [providers, setProviders] = useState<
    Array<{
      provider: string;
      configured: boolean;
      status: string;
      required_env: string;
    }>
  >([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    void client
      .listNotificationProviders()
      .then((items) => {
        setProviders(items);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, [client]);

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Providers"
        title="Notification Matrix"
        state={`${providers.filter((provider) => provider.configured).length}/${providers.length}`}
      />
      {providers.length === 0 ? (
        <EmptyState
          title="No provider status"
          detail="Provider configuration status appears when the server is reachable."
        />
      ) : null}
      <ol className="skybridge-timeline skybridge-timeline--compact">
        {providers.map((provider) => (
          <li key={provider.provider}>
            <span>
              <strong>{provider.provider}</strong>
              <small>{provider.required_env}</small>
            </span>
            <span
              className={`skybridge-state ${provider.configured ? "" : "skybridge-state--bad"}`}
            >
              {provider.status}
            </span>
          </li>
        ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function IterationStatusCard({ apiBase }: WidgetProps) {
  const [iterations, setIterations] = useState<IterationRun[]>([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    void client
      .listIterations()
      .then((items) => {
        setIterations(items);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, [client]);

  const current = iterations[0];
  const bad =
    current?.state === "blocked" ||
    current?.state === "failed" ||
    current?.state === "ci_failed";

  return (
    <section className="skybridge-panel skybridge-iteration-status">
      <PanelHeader
        kicker="Autonomous Iteration"
        title="Current Iteration"
        state={current?.state ?? "idle"}
        bad={bad}
      />
      {current ? (
        <>
          <dl className="skybridge-metrics skybridge-metrics--compact">
            <Metric
              label="Attempts"
              value={`${current.attempts}/${current.max_attempts}`}
            />
            <Metric
              label="PR"
              value={current.pr_number ? `#${current.pr_number}` : "none"}
            />
            <Metric label="Branch" value={current.branch} />
            <Metric
              label="Auto-merge"
              value={current.auto_merge_enabled ? "enabled" : "off"}
            />
          </dl>
          <p className="skybridge-runline">
            {current.project_id} · {current.goal_id ?? "manual goal"} ·{" "}
            {current.last_error ?? "no blocked reason"}
          </p>
        </>
      ) : (
        <EmptyState
          title="No iteration"
          detail="Controller state appears after a dry run or one-shot iteration is recorded."
        />
      )}
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function IterationTimeline({ apiBase }: WidgetProps) {
  const [events, setEvents] = useState<
    Array<{ type: string; time: string; payload: Record<string, unknown> }>
  >([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    void client
      .listIterations()
      .then(async (items) => {
        const latest = items[0];
        if (!latest) {
          setEvents([]);
          return;
        }
        const detail = await client.getIteration(latest.iteration_id);
        setEvents(detail.events ?? []);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, [client]);

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Iteration"
        title="State Timeline"
        state={`${events.length}`}
      />
      {events.length === 0 ? (
        <EmptyState
          title="No timeline"
          detail="Iteration events appear when controller scripts emit state changes."
        />
      ) : null}
      <ol className="skybridge-timeline skybridge-timeline--compact">
        {events.slice(-8).map((event, index) => (
          <li key={`${event.type}-${event.time}-${index}`}>
            <span>
              <strong>{event.type}</strong>
              <small>
                {safePayloadString(event.payload.state) ??
                  safePayloadString(event.payload.reason) ??
                  "metadata only"}
              </small>
            </span>
            <small>{formatDateTime(event.time)}</small>
          </li>
        ))}
      </ol>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function CIGuardianPanel({ apiBase }: WidgetProps) {
  const [iterations, setIterations] = useState<IterationRun[]>([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    void client
      .listIterations()
      .then((items) => {
        setIterations(items);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, [client]);

  const current =
    iterations.find((item) => item.state.startsWith("ci_") || item.pr_number) ??
    iterations[0];
  const ciState = current?.state.startsWith("ci_")
    ? current.state
    : current
      ? "pr_opened"
      : "idle";

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="CI Guardian"
        title="PR Review Loop"
        state={ciState}
        bad={ciState === "ci_failed"}
      />
      {current ? (
        <dl className="skybridge-metrics skybridge-metrics--compact">
          <Metric
            label="PR"
            value={current.pr_number ? `#${current.pr_number}` : "none"}
          />
          <Metric
            label="Repairs"
            value={`${current.attempts}/${current.max_attempts}`}
          />
          <Metric label="Checks" value={current.checks.length} />
          <Metric label="Blocked" value={current.last_error ?? "no"} />
        </dl>
      ) : (
        <EmptyState
          title="No PR state"
          detail="CI Guardian state appears after PR checks are observed."
        />
      )}
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function AutonomousIterationOperatorPanel({ apiBase }: WidgetProps) {
  const [iterations, setIterations] = useState<IterationRun[]>([]);
  const [supervisor, setSupervisor] = useState<SupervisorStatus | undefined>();
  const [nextAction, setNextAction] = useState<
    SupervisorNextAction | undefined
  >();
  const [providers, setProviders] = useState<
    Array<{ provider: string; configured: boolean; status: string }>
  >([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    void Promise.all([
      client.listIterations(),
      client.getSupervisorStatus(),
      client.getSupervisorNextAction(),
      client.listNotificationProviders(),
    ])
      .then(([nextIterations, nextSupervisor, action, nextProviders]) => {
        setIterations(nextIterations);
        setSupervisor(nextSupervisor);
        setNextAction(action);
        setProviders(nextProviders);
        setError(undefined);
      })
      .catch((err) =>
        setError(err instanceof Error ? err.message : String(err)),
      );
  }, [client]);

  const latest = supervisor?.iterations.latest ?? iterations[0];
  const ciStatus = latest?.state?.startsWith("ci_")
    ? latest.state
    : latest?.pr_number
      ? "pr_opened"
      : "idle";
  const hermesStatus = supervisor?.ok
    ? supervisor.iterations.blocked > 0
      ? "attention"
      : "observing"
    : "offline";
  const bootstrapStatus =
    supervisor?.notification_path?.skybridge_notification_center_required ===
    false
      ? "bootstrap-direct"
      : "check setup";
  const ntfy = providers.find((provider) => provider.provider === "ntfy");
  const blockedReason =
    latest?.last_error ??
    (latest?.state === "blocked" || latest?.state === "failed"
      ? "blocked without reason"
      : "none");
  const bad =
    latest?.state === "blocked" ||
    latest?.state === "failed" ||
    latest?.state === "ci_failed";

  return (
    <section className="skybridge-panel skybridge-autonomy-panel">
      <PanelHeader
        kicker="Autonomous Operations"
        title="Iteration Control"
        state={latest?.state ?? "idle"}
        bad={bad}
      />
      {latest ? (
        <>
          <dl className="skybridge-metrics skybridge-metrics--compact">
            <Metric label="Latest" value={latest.state} />
            <Metric
              label="Open PR"
              value={latest.pr_number ? `#${latest.pr_number}` : "none"}
            />
            <Metric label="CI Guardian" value={ciStatus} />
            <Metric label="Hermes" value={hermesStatus} />
            <Metric label="Bootstrap" value={bootstrapStatus} />
            <Metric
              label="ntfy"
              value={
                ntfy?.configured ? "configured" : (ntfy?.status ?? "unknown")
              }
            />
            <Metric label="Blocked" value={blockedReason} />
            <Metric label="Next" value={nextAction?.action ?? "observe"} />
          </dl>
          <p className="skybridge-runline">
            {latest.branch} · attempts {latest.attempts}/{latest.max_attempts} ·{" "}
            {nextAction?.reason ?? nextAction?.state ?? "metadata only"}
          </p>
        </>
      ) : (
        <EmptyState
          title="No autonomous iteration"
          detail="Run the controller smoke or a dry-run iteration to populate operator state."
        />
      )}
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function SourceFilterBar({
  filters,
  onChange,
}: {
  filters: SourceFilters;
  onChange: (filters: SourceFilters) => void;
}) {
  return (
    <section className="skybridge-filterbar" aria-label="Source filters">
      <label>
        Platform
        <select
          value={filters.platform ?? "all"}
          onChange={(event) =>
            onChange({
              ...filters,
              platform: event.currentTarget.value as SourceFilters["platform"],
            })
          }
        >
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
        <input
          value={filters.adapter ?? ""}
          placeholder="any adapter"
          onChange={(event) =>
            onChange({
              ...filters,
              adapter: event.currentTarget.value || undefined,
            })
          }
        />
      </label>
      <label>
        Severity
        <select
          value={filters.severity ?? "all"}
          onChange={(event) =>
            onChange({
              ...filters,
              severity: event.currentTarget.value as SourceFilters["severity"],
            })
          }
        >
          <option value="all">All</option>
          <option value="info">Info</option>
          <option value="warning">Warning</option>
          <option value="error">Error</option>
          <option value="critical">Critical</option>
        </select>
      </label>
      <label>
        Run status
        <select
          value={filters.status ?? "all"}
          onChange={(event) =>
            onChange({
              ...filters,
              status: event.currentTarget.value as SourceFilters["status"],
            })
          }
        >
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

export function summarizeCodexIntegration(
  runs: RunSummary[],
  events: SkyBridgeEvent[],
): CodexIntegrationSummary {
  const codexRuns = runs.filter((run) => run.source_platform === "codex");
  const hookEvents = events.filter(
    (event) =>
      event.source.platform === "codex" &&
      event.source.adapter === "codex-hook",
  );
  const latestHookEvent = hookEvents.at(-1);
  const failedToolCount = codexRuns.reduce(
    (sum, run) => sum + run.failed_tool_count,
    0,
  );
  const activeToolCount = codexRuns.reduce(
    (sum, run) => sum + run.active_tool_count,
    0,
  );
  const spoolCount = latestSpoolCount(hookEvents);

  return {
    status:
      failedToolCount > 0
        ? "attention"
        : hookEvents.length > 0 ||
            codexRuns.some((run) => run.status === "running")
          ? "active"
          : "idle",
    recent_runs: codexRuns.slice(0, 5),
    latest_hook_event: latestHookEvent,
    hook_event_count: hookEvents.length,
    failed_tool_count: failedToolCount,
    active_tool_count: activeToolCount,
    spool_count: spoolCount,
  };
}

export function CodexIntegrationStatus({ apiBase }: WidgetProps) {
  const { events, runs, error } = useSkyBridge(apiBase, { platform: "codex" });
  const summary = summarizeCodexIntegration(runs, events);

  return (
    <section className="skybridge-panel skybridge-codex-integration">
      <PanelHeader
        kicker="Executor Adapter"
        title="Codex Status"
        state={summary.status}
        bad={summary.status === "attention"}
      />
      <dl className="skybridge-metrics skybridge-metrics--compact">
        <Metric label="Runs" value={summary.recent_runs.length} />
        <Metric label="Hook events" value={summary.hook_event_count} />
        <Metric label="Active tools" value={summary.active_tool_count} />
        <Metric label="Failed tools" value={summary.failed_tool_count} />
      </dl>
      <p className="skybridge-runline">
        Last hook: {summary.latest_hook_event?.type ?? "none"} · Spool:{" "}
        {summary.spool_count ?? "local only"}
      </p>
      {error ? <ErrorState message={error} /> : null}
    </section>
  );
}

export function summarizeSelfObservation(
  runs: RunSummary[],
  events: SkyBridgeEvent[],
): SelfObservationSummary {
  const selfEvents = events.filter(
    (event) =>
      event.source.platform === "codex" ||
      event.source.platform === "skybridge",
  );
  const latestLifecycle = [...selfEvents]
    .reverse()
    .map((event) => safePayloadString(event.payload.lifecycle))
    .find(Boolean);
  const failedRuns = runs.filter((run) => run.status === "failed").length;
  const activeRuns = runs.filter((run) => run.status === "running").length;

  return {
    status:
      failedRuns > 0
        ? "attention"
        : selfEvents.length > 0 || activeRuns > 0
          ? "observing"
          : "idle",
    active_runs: activeRuns,
    failed_runs: failedRuns,
    codex_events: selfEvents.filter(
      (event) => event.source.platform === "codex",
    ).length,
    runner_events: selfEvents.filter(
      (event) => event.source.adapter === "yolo-runner",
    ).length,
    smoke_events: selfEvents.filter(
      (event) => event.source.adapter === "self-observation-smoke",
    ).length,
    notification_events: selfEvents.filter((event) =>
      event.type.startsWith("notification."),
    ).length,
    latest_lifecycle: latestLifecycle,
  };
}

export function SelfObservationPanel({ apiBase }: WidgetProps) {
  const { events, runs, error } = useSkyBridge(apiBase);
  const summary = summarizeSelfObservation(runs, events);

  return (
    <section className="skybridge-panel skybridge-self-observation">
      <PanelHeader
        kicker="Dogfooding Loop"
        title="Self-Observation"
        state={summary.status}
        bad={summary.status === "attention"}
      />
      <dl className="skybridge-metrics skybridge-metrics--compact">
        <Metric label="Codex" value={summary.codex_events} />
        <Metric label="Runner" value={summary.runner_events} />
        <Metric label="Smoke" value={summary.smoke_events} />
        <Metric label="Notify" value={summary.notification_events} />
      </dl>
      <p className="skybridge-runline">
        {summary.active_runs} active · {summary.failed_runs} failed ·{" "}
        {summary.latest_lifecycle ?? "no lifecycle yet"}
      </p>
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
    unknown: runs.filter((run) => run.status === "unknown").length,
  };
  const total = Math.max(runs.length, 1);

  return (
    <section className="skybridge-panel">
      <PanelHeader
        kicker="Pipeline"
        title="Run Distribution"
        state={`${runs.length}`}
      />
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
      <p className="skybridge-runline">
        {counts.running} running · {counts.completed} completed ·{" "}
        {counts.failed} failed
      </p>
    </section>
  );
}

export function CodexIntegrationPanel(props: WidgetProps) {
  return <CodexIntegrationStatus {...props} />;
}

function PanelHeader({
  kicker,
  title,
  state,
  bad = false,
}: {
  kicker: string;
  title: string;
  state: string;
  bad?: boolean;
}) {
  return (
    <div className="skybridge-card__header">
      <div>
        <p className="skybridge-kicker">{kicker}</p>
        <h2>{title}</h2>
      </div>
      <span className={`skybridge-state ${bad ? "skybridge-state--bad" : ""}`}>
        {state}
      </span>
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
    platform:
      filters.platform && filters.platform !== "all"
        ? filters.platform
        : undefined,
    adapter: filters.adapter,
    severity:
      filters.severity && filters.severity !== "all"
        ? filters.severity
        : undefined,
    type: filters.type as EventListQuery["type"],
    limit: 200,
  };
}

function toRunQuery(filters: SourceFilters): RunListQuery {
  return {
    platform:
      filters.platform && filters.platform !== "all"
        ? filters.platform
        : undefined,
    adapter: filters.adapter,
    status:
      filters.status && filters.status !== "all" ? filters.status : undefined,
    limit: 200,
  };
}

function matchesFilters(
  event: SkyBridgeEvent,
  filters: SourceFilters,
): boolean {
  if (
    filters.platform &&
    filters.platform !== "all" &&
    event.source.platform !== filters.platform
  )
    return false;
  if (filters.adapter && event.source.adapter !== filters.adapter) return false;
  if (
    filters.severity &&
    filters.severity !== "all" &&
    event.severity !== filters.severity
  )
    return false;
  if (filters.type && event.type !== filters.type) return false;
  return true;
}

function formatDateTime(input: string | undefined): string {
  return input ? new Date(input).toLocaleString() : "not yet";
}

function safePayloadString(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 && input.length <= 120
    ? input
    : undefined;
}

function latestSpoolCount(events: SkyBridgeEvent[]): number | undefined {
  for (const event of [...events].reverse()) {
    const value = event.payload.spool_count ?? event.payload.queued_spool_count;
    if (typeof value === "number" && Number.isFinite(value)) return value;
  }
  return undefined;
}
