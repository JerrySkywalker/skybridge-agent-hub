import React, { useEffect, useMemo, useState } from "react";
import { SkyBridgeClient } from "@skybridge-agent-hub/client";
import type { RunSummary, SkyBridgeEvent } from "@skybridge-agent-hub/event-schema";

export interface WidgetProps {
  apiBase: string;
}

export function useSkyBridge(apiBase: string) {
  const [events, setEvents] = useState<SkyBridgeEvent[]>([]);
  const [runs, setRuns] = useState<RunSummary[]>([]);
  const [error, setError] = useState<string | undefined>();
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);

  useEffect(() => {
    let closed = false;

    async function refresh() {
      try {
        const [nextEvents, nextRuns] = await Promise.all([client.listEvents(), client.listRuns()]);
        if (!closed) {
          setEvents(nextEvents);
          setRuns(nextRuns);
          setError(undefined);
        }
      } catch (err) {
        if (!closed) setError(err instanceof Error ? err.message : String(err));
      }
    }

    void refresh();
    const stream = client.streamEvents((event) => {
      setEvents((prev) => [...prev.slice(-99), event]);
      void client.listRuns().then(setRuns).catch(() => undefined);
    });
    stream.onerror = () => setError("SSE stream disconnected; retrying.");

    return () => {
      closed = true;
      stream.close();
    };
  }, [client]);

  return { events, runs, error };
}

export function AgentStatusCard({ apiBase }: WidgetProps) {
  const { events, runs, error } = useSkyBridge(apiBase);
  const latest = events.at(-1);
  const failedRuns = runs.filter((run) => run.status === "failed").length;

  return (
    <section className="skybridge-card">
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">SkyBridge Agent Hub</p>
          <h2>Agent Status</h2>
        </div>
        <span className={`skybridge-state ${failedRuns ? "skybridge-state--bad" : "skybridge-state--ok"}`}>
          {failedRuns ? "attention" : latest ? "active" : "idle"}
        </span>
      </div>
      <dl className="skybridge-metrics">
        <div>
          <dt>Runs</dt>
          <dd>{runs.length}</dd>
        </div>
        <div>
          <dt>Events</dt>
          <dd>{events.length}</dd>
        </div>
        <div>
          <dt>Last event</dt>
          <dd>{latest?.type ?? "none"}</dd>
        </div>
        <div>
          <dt>Last seen</dt>
          <dd>{latest ? new Date(latest.time).toLocaleString() : "not yet"}</dd>
        </div>
      </dl>
      {error ? <p className="skybridge-error">{error}</p> : null}
    </section>
  );
}

export function AgentTimeline({ apiBase }: WidgetProps) {
  const { events } = useSkyBridge(apiBase);
  return (
    <section className="skybridge-panel">
      <h2>Timeline</h2>
      <ol className="skybridge-timeline">
        {events.slice(-25).reverse().map((event, index) => (
          <li key={event.event_id ?? `${event.time}-${index}`}>
            <span>{event.type}</span>
            <small>{event.source.platform}/{event.source.adapter} · {new Date(event.time).toLocaleTimeString()}</small>
          </li>
        ))}
      </ol>
    </section>
  );
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
      <h2>Pipeline</h2>
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
        {counts.running} running · {counts.completed} completed · {counts.failed} failed
      </p>
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
      <div className="skybridge-card__header">
        <div>
          <p className="skybridge-kicker">Local Loop</p>
          <h2>Self-Observation</h2>
        </div>
        <span className={`skybridge-state ${summary.status === "attention" ? "skybridge-state--bad" : ""}`}>
          {summary.status}
        </span>
      </div>
      <dl className="skybridge-metrics skybridge-metrics--compact">
        <div>
          <dt>Codex</dt>
          <dd>{summary.codex_events}</dd>
        </div>
        <div>
          <dt>Runner</dt>
          <dd>{summary.runner_events}</dd>
        </div>
        <div>
          <dt>Smoke</dt>
          <dd>{summary.smoke_events}</dd>
        </div>
        <div>
          <dt>Notify</dt>
          <dd>{summary.notification_events}</dd>
        </div>
      </dl>
      <p className="skybridge-runline">
        {summary.active_runs} active · {summary.failed_runs} failed · {summary.latest_lifecycle ?? "no lifecycle yet"}
      </p>
      {error ? <p className="skybridge-error">{error}</p> : null}
    </section>
  );
}

function safePayloadString(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 && input.length <= 120 ? input : undefined;
}
