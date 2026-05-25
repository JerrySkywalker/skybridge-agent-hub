interface HealthResponse {
  ok: boolean;
  service: string;
  persistence: string;
  time: string;
}

interface EventsResponse {
  events: Array<{
    type: string;
    time: string;
    severity?: string;
    source: { platform: string; adapter: string };
  }>;
}

interface RunsResponse {
  runs: Array<{
    status: "running" | "completed" | "failed" | "unknown";
  }>;
}

interface ProductSummaryResponse {
  totals: {
    events: number;
    runs: number;
    active_runs: number;
    failed_runs: number;
    open_prs?: number;
    ci_failed?: number;
  };
  latest?: {
    hermes_status?: string;
    notification?: { status: string; provider: string; message?: { title?: string } };
  };
}

export interface AgentStatusViewModel {
  state: string;
  service?: string;
  persistence?: string;
  stream?: string;
  events: number;
  runs: number;
  activeRuns: number;
  failedRuns: number;
  openPrs?: number;
  ciFailed?: number;
  hermesStatus?: string;
  lastNotification?: string;
  source?: string;
  lastSeen?: string;
  error?: string;
  compact?: boolean;
}

const HTMLElementBase = globalThis.HTMLElement ?? class {};

export class AgentStatusElement extends HTMLElementBase {
  private timer: number | undefined;

  connectedCallback() {
    this.render({ state: "loading", events: 0, runs: 0, activeRuns: 0, failedRuns: 0, compact: this.compact });
    void this.refresh();
    this.timer = window.setInterval(() => void this.refresh(), this.refreshMs);
  }

  disconnectedCallback() {
    if (this.timer) window.clearInterval(this.timer);
  }

  private get apiBase() {
    return this.getAttribute("api-base") ?? "http://127.0.0.1:8787";
  }

  private get compact() {
    return this.hasAttribute("compact") || this.getAttribute("mode") === "compact";
  }

  private get refreshMs() {
    const parsed = Number(this.getAttribute("refresh-ms"));
    return Number.isFinite(parsed) && parsed >= 5_000 ? parsed : 15_000;
  }

  private async refresh() {
    try {
      const [health, eventJson, runJson] = await Promise.all([
        fetch(`${this.apiBase}/v1/health`).then((response) => response.json() as Promise<HealthResponse>),
        fetch(`${this.apiBase}/v1/events?limit=25`).then((response) => response.json() as Promise<EventsResponse>),
        fetch(`${this.apiBase}/v1/runs?limit=25`).then((response) => response.json() as Promise<RunsResponse>)
      ]);
      const productSummary = await fetch(`${this.apiBase}/v1/summary`)
        .then((response) => response.ok ? response.json() as Promise<ProductSummaryResponse> : undefined)
        .catch(() => undefined);
      const latest = eventJson.events.at(-1);
      const failedRuns = runJson.runs.filter((run) => run.status === "failed").length;
      const activeRuns = runJson.runs.filter((run) => run.status === "running").length;
      this.render({
        state: failedRuns ? "attention" : latest ? "active" : "idle",
        service: health.service,
        persistence: health.persistence,
        events: eventJson.events.length,
        runs: runJson.runs.length,
        activeRuns,
        failedRuns,
        openPrs: productSummary?.totals.open_prs,
        ciFailed: productSummary?.totals.ci_failed,
        hermesStatus: productSummary?.latest?.hermes_status,
        lastNotification: productSummary?.latest?.notification ? `${productSummary.latest.notification.provider}/${productSummary.latest.notification.status}` : undefined,
        source: latest ? `${latest.source.platform}/${latest.source.adapter}` : "none",
        lastSeen: latest ? new Date(latest.time).toLocaleString() : "not yet",
        compact: this.compact
      });
    } catch (error) {
      this.render({
        state: "offline",
        events: 0,
        runs: 0,
        activeRuns: 0,
        failedRuns: 0,
        source: "unavailable",
        error: error instanceof Error ? error.message : String(error),
        compact: this.compact
      });
    }
  }

  private render(data: AgentStatusViewModel) {
    this.innerHTML = renderAgentStatusHtml(data);
  }
}

export function renderAgentStatusHtml(data: AgentStatusViewModel): string {
  const statusColor = data.state === "offline" || data.state === "attention" ? "#a83225" : "#1f6b3d";
  const statusBg = data.state === "offline" || data.state === "attention" ? "#fff0ef" : "#e9f7ef";
  const compactStyle = data.compact ? "max-width:360px;" : "";
  const metrics = data.compact
    ? `<div><dt>Runs</dt><dd>${data.runs}</dd></div><div><dt>PR/CI</dt><dd>${data.openPrs ?? 0}/${data.ciFailed ?? 0}</dd></div>`
    : `<div><dt>Runs</dt><dd>${data.runs}</dd></div><div><dt>Active</dt><dd>${data.activeRuns}</dd></div><div><dt>Failed</dt><dd>${data.failedRuns}</dd></div><div><dt>PR/CI</dt><dd>${data.openPrs ?? 0}/${data.ciFailed ?? 0}</dd></div>`;

  return `<section style="${compactStyle}font-family: system-ui, sans-serif; border: 1px solid #dbe4ef; border-radius: 8px; padding: 14px; background: #fff; color: #172033;">
    <div style="display:flex; justify-content:space-between; gap:10px; align-items:start;">
      <div>
        <div style="font-size:12px; color:#52627a; text-transform:uppercase;">SkyBridge Agent Hub</div>
        <strong>Operator Status</strong>
      </div>
      <span style="font-size:12px; border:1px solid ${statusColor}; border-radius:999px; color:${statusColor}; background:${statusBg}; padding:3px 7px;">${escapeHtml(data.state)}</span>
    </div>
    <dl style="display:grid; grid-template-columns:repeat(${data.compact ? 2 : 4},minmax(0,1fr)); gap:10px; margin:12px 0 0;">
      ${metrics}
      <div style="grid-column:1 / -1;"><dt style="font-size:12px; color:#52627a;">Hermes</dt><dd style="margin:0; font-weight:650;">${escapeHtml(data.hermesStatus ?? "unknown")}</dd></div>
      <div style="grid-column:1 / -1;"><dt style="font-size:12px; color:#52627a;">Last notification</dt><dd style="margin:0; font-weight:650;">${escapeHtml(data.lastNotification ?? "none")}</dd></div>
      <div style="grid-column:1 / -1;"><dt style="font-size:12px; color:#52627a;">Last source</dt><dd style="margin:0; font-weight:650;">${escapeHtml(data.source ?? "none")}</dd></div>
      <div style="grid-column:1 / -1;"><dt style="font-size:12px; color:#52627a;">Last seen</dt><dd style="margin:0; font-weight:650;">${escapeHtml(data.lastSeen ?? "not yet")}</dd></div>
    </dl>
    ${data.error ? `<p style="color:#a83225; margin:12px 0 0;">${escapeHtml(data.error)}</p>` : ""}
  </section>`;
}

function escapeHtml(input: string): string {
  return input.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

if (globalThis.customElements && !customElements.get("agent-status-card")) {
  customElements.define("agent-status-card", AgentStatusElement as CustomElementConstructor);
}
