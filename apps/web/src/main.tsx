import React, { useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ActiveRunsPanel,
  ApprovalQueuePanel,
  CIGuardianPanel,
  CodexIntegrationStatus,
  EventTimeline,
  IterationStatusCard,
  IterationTimeline,
  NotificationList,
  OperationsSummaryPanel,
  ProviderStatusPanel,
  RunDetailPanel,
  SelfObservationPanel,
  SkyBridgeHealthCard,
  SourceFilterBar,
  type SourceFilters
} from "@skybridge-agent-hub/react-widgets";
import "./style.css";

function App() {
  const apiBase = import.meta.env.VITE_SKYBRIDGE_API_BASE || "http://127.0.0.1:8787";
  const route = window.location.pathname.startsWith("/embed/compact") || window.location.hash === "#/embed/compact" ? "embed" : "console";
  const [filters, setFilters] = useState<SourceFilters>({ platform: "all", severity: "all", status: "all" });
  const [selectedRunId, setSelectedRunId] = useState<string | undefined>();
  const filteredRunId = useMemo(() => selectedRunId, [selectedRunId]);

  if (route === "embed") {
    return (
      <main className="embed-page">
        <SkyBridgeHealthCard apiBase={apiBase} />
      </main>
    );
  }

  return (
    <main className="page">
      <header className="topbar">
        <div>
          <p className="eyebrow">SkyBridge Agent Hub</p>
          <h1>Operator Console</h1>
        </div>
        <div className="topbar__meta">
          <a href="#/embed/compact">Compact embed</a>
          <code>{apiBase}</code>
        </div>
      </header>

      <SourceFilterBar filters={filters} onChange={setFilters} />

      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <SkyBridgeHealthCard apiBase={apiBase} />
          <ActiveRunsPanel apiBase={apiBase} filters={filters} selectedRunId={filteredRunId} onSelectRun={setSelectedRunId} />
          <EventTimeline apiBase={apiBase} filters={filters} />
        </div>
        <aside className="dashboard-grid__side">
          <CodexIntegrationStatus apiBase={apiBase} />
          <IterationStatusCard apiBase={apiBase} />
          <IterationTimeline apiBase={apiBase} />
          <CIGuardianPanel apiBase={apiBase} />
          <OperationsSummaryPanel apiBase={apiBase} />
          <ApprovalQueuePanel apiBase={apiBase} />
          <NotificationList apiBase={apiBase} />
          <ProviderStatusPanel apiBase={apiBase} />
          <SelfObservationPanel apiBase={apiBase} />
          <RunDetailPanel apiBase={apiBase} runId={filteredRunId} />
        </aside>
      </section>
    </main>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
