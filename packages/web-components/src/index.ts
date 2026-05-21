interface EventsResponse {
  events: Array<{
    type: string;
    time: string;
    source: { platform: string; adapter: string };
  }>;
}

export class AgentStatusElement extends HTMLElement {
  private timer: number | undefined;

  connectedCallback() {
    this.render({ state: "loading", events: 0 });
    void this.refresh();
    this.timer = window.setInterval(() => void this.refresh(), 15_000);
  }

  disconnectedCallback() {
    if (this.timer) window.clearInterval(this.timer);
  }

  private get apiBase() {
    return this.getAttribute("api-base") ?? "http://127.0.0.1:8787";
  }

  private async refresh() {
    try {
      const response = await fetch(`${this.apiBase}/v1/events`);
      const json = await response.json() as EventsResponse;
      const latest = json.events.at(-1);
      this.render({
        state: latest?.type ?? "idle",
        events: json.events.length,
        source: latest ? `${latest.source.platform}/${latest.source.adapter}` : "none",
        lastSeen: latest ? new Date(latest.time).toLocaleString() : "not yet"
      });
    } catch (error) {
      this.render({ state: "offline", events: 0, source: error instanceof Error ? error.message : String(error) });
    }
  }

  private render(data: { state: string; events: number; source?: string; lastSeen?: string }) {
    this.innerHTML = `<section style="font-family: system-ui, sans-serif; border: 1px solid #dbe4ef; border-radius: 8px; padding: 14px; background: #fff; color: #172033;">
      <div style="display:flex; justify-content:space-between; gap:10px; align-items:start;">
        <strong>SkyBridge Agent Hub</strong>
        <span style="font-size:12px; border:1px solid #d4deeb; border-radius:999px; padding:3px 7px;">${data.state}</span>
      </div>
      <dl style="display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:10px; margin:12px 0 0;">
        <div><dt style="font-size:12px; color:#52627a;">Events</dt><dd style="margin:0; font-weight:650;">${data.events}</dd></div>
        <div><dt style="font-size:12px; color:#52627a;">Source</dt><dd style="margin:0; font-weight:650;">${data.source ?? "none"}</dd></div>
        <div style="grid-column:1 / -1;"><dt style="font-size:12px; color:#52627a;">Last seen</dt><dd style="margin:0; font-weight:650;">${data.lastSeen ?? "not yet"}</dd></div>
      </dl>
    </section>`;
  }
}

if (!customElements.get("agent-status-card")) {
  customElements.define("agent-status-card", AgentStatusElement);
}
