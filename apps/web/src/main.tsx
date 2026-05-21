import React from "react";
import { createRoot } from "react-dom/client";
import { AgentPipelineBar, AgentStatusCard, AgentTimeline } from "@skybridge-agent-hub/react-widgets";
import "./style.css";

function App() {
  const apiBase = import.meta.env.VITE_SKYBRIDGE_API_BASE || "http://127.0.0.1:8787";

  return (
    <main className="page">
      <section className="topbar">
        <div>
          <p className="eyebrow">SkyBridge Agent Hub</p>
          <h1>Agent Operations</h1>
        </div>
        <code>{apiBase}</code>
      </section>

      <div className="grid">
        <AgentStatusCard apiBase={apiBase} />
        <AgentPipelineBar apiBase={apiBase} />
      </div>
      <AgentTimeline apiBase={apiBase} />
    </main>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
