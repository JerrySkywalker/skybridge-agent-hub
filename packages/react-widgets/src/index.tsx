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
