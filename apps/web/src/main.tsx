import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ActiveRunsPanel,
  ApprovalQueuePanel,
  EventTimeline,
  NotificationList,
  ProviderStatusPanel,
  RunDetailPanel,
  SkyBridgeHealthCard,
  SourceFilterBar,
  type SourceFilters
} from "@skybridge-agent-hub/react-widgets";
import {
  SkyBridgeClient,
  type AutoMergeSummary,
  type AuditEntry,
  type HermesSummary,
  type IterationsSummary,
  type NotificationsSummary,
  type PrsSummary,
  type ProjectSummary,
  type SummaryResponse
} from "@skybridge-agent-hub/client";
import type { IterationRun, RunSummary, SkyBridgeEvent } from "@skybridge-agent-hub/event-schema";
import "./style.css";

type Route = "overview" | "runs" | "iterations" | "pr-ci" | "notifications" | "hermes" | "sources" | "audit" | "settings" | "embed";

const navItems: Array<{ route: Route; label: string }> = [
  { route: "overview", label: "Overview" },
  { route: "runs", label: "Runs" },
  { route: "iterations", label: "Iterations" },
  { route: "pr-ci", label: "PR/CI" },
  { route: "notifications", label: "Notifications" },
  { route: "hermes", label: "Hermes" },
  { route: "sources", label: "Sources/Audit" },
  { route: "settings", label: "Settings" }
];

function App() {
  const apiBase = import.meta.env.VITE_SKYBRIDGE_API_BASE || "http://127.0.0.1:8787";
  const route = useHashRoute();
  const [filters, setFilters] = useState<SourceFilters>({ platform: "all", severity: "all", status: "all" });
  const [selectedRunId, setSelectedRunId] = useState<string | undefined>();

  if (route === "embed") {
    return (
      <main className="embed-page">
        <SkyBridgeHealthCard apiBase={apiBase} />
      </main>
    );
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <strong>SkyBridge</strong>
          <span>Agent Hub</span>
        </div>
        <nav className="sidebar-nav" aria-label="Operator Console">
          {navItems.map((item) => (
            <a key={item.route} className={route === item.route ? "is-active" : ""} href={`#/${item.route}`}>
              {item.label}
            </a>
          ))}
        </nav>
        <a className="sidebar-embed" href="#/embed/compact">Compact embed</a>
      </aside>

      <main className="page">
        <header className="topbar">
          <div>
            <p className="eyebrow">SkyBridge Agent Hub</p>
            <h1>{titleForRoute(route)}</h1>
          </div>
          <div className="topbar__meta">
            <code>{apiBase}</code>
          </div>
        </header>

        {route === "overview" ? <OverviewPage apiBase={apiBase} /> : null}
        {route === "runs" ? (
          <RunsPage apiBase={apiBase} filters={filters} onFilters={setFilters} selectedRunId={selectedRunId} onSelectRun={setSelectedRunId} />
        ) : null}
        {route === "iterations" ? <IterationsPage apiBase={apiBase} /> : null}
        {route === "pr-ci" ? <PrCiPage apiBase={apiBase} /> : null}
        {route === "notifications" ? <NotificationsPage apiBase={apiBase} /> : null}
        {route === "hermes" ? <HermesPage apiBase={apiBase} /> : null}
        {route === "sources" ? <SourcesAuditPage apiBase={apiBase} /> : null}
        {route === "settings" ? <SettingsPage apiBase={apiBase} /> : null}
      </main>
    </div>
  );
}

function OverviewPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  const summary = data.summary;

  return (
    <div className="route-stack">
      <section className="hero-panel">
        <div>
          <h2>Daily operator picture</h2>
          <p>{summary?.latest?.next_recommended_action ?? "Connect the server or seed demo data to populate the operator picture."}</p>
        </div>
        <span className={badgeClass(summary?.totals.attention_items ? "bad" : "ok")}>{summary?.totals.attention_items ?? 0} attention</span>
      </section>
      <section className="kpi-grid">
        <Kpi label="Health" value={summary?.health.ok ? "online" : "unknown"} />
        <Kpi label="Open PRs" value={summary?.totals.open_prs ?? 0} />
        <Kpi label="Latest CI" value={summary?.latest?.ci_state ?? "unknown"} />
        <Kpi label="Auto-merge blocked" value={summary?.totals.automerge_blocked ?? 0} />
        <Kpi label="Latest iteration" value={summary?.latest?.iteration?.state ?? "idle"} />
        <Kpi label="Hermes" value={summary?.latest?.hermes_status ?? "placeholder"} />
        <Kpi label="Latest notification" value={summary?.latest?.notification?.status ?? "none"} />
        <Kpi label="Recent failures" value={summary?.recent_failures?.length ?? 0} />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <SkyBridgeHealthCard apiBase={apiBase} />
          <FailureList failures={summary?.recent_failures ?? []} />
          <ProductTable title="Open PR/CI" rows={(data.prs?.prs ?? []).slice(0, 6).map((pr) => [`#${pr.pr_number}`, pr.ci_state, pr.eligibility, pr.reasons[0] ?? "no blocker"])} />
        </div>
        <aside className="dashboard-grid__side">
          <SummaryCard title="Auto-merge" state={`${data.automerge?.eligible ?? 0} eligible`} lines={[
            `Dry-run default: ${data.automerge?.dry_run_default ? "yes" : "no"}`,
            `Blocked: ${data.automerge?.blocked ?? 0}`,
            `Latest sweep: ${data.automerge?.latest_sweep?.summary ?? "none"}`
          ]} />
          <SummaryCard title="Hermes" state={data.hermes?.status ?? "placeholder"} lines={[
            `Tunnel: ${data.hermes?.tunnel.status ?? "unknown"}`,
            `API: ${data.hermes?.api.health ?? "unknown"}`,
            `Degraded: ${data.hermes?.degraded_reason ?? "no"}`
          ]} />
          <NotificationList apiBase={apiBase} />
        </aside>
      </section>
      {data.error ? <p className="skybridge-error">{data.error}</p> : null}
    </div>
  );
}

function RunsPage(props: {
  apiBase: string;
  filters: SourceFilters;
  selectedRunId?: string;
  onFilters: (filters: SourceFilters) => void;
  onSelectRun: (runId: string) => void;
}) {
  return (
    <div className="route-stack">
      <SourceFilterBar filters={props.filters} onChange={props.onFilters} />
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <ActiveRunsPanel apiBase={props.apiBase} filters={props.filters} selectedRunId={props.selectedRunId} onSelectRun={props.onSelectRun} />
          <EventTimeline apiBase={props.apiBase} filters={props.filters} />
        </div>
        <aside className="dashboard-grid__side">
          <RunDetailPanel apiBase={props.apiBase} runId={props.selectedRunId} />
        </aside>
      </section>
    </div>
  );
}

function IterationsPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Total" value={data.iterations?.total ?? 0} />
        <Kpi label="Active" value={data.iterations?.active ?? 0} />
        <Kpi label="Blocked" value={data.iterations?.blocked ?? 0} />
        <Kpi label="Repair attempts" value={data.iterations?.repair_attempts ?? 0} />
      </section>
      <IterationList iterations={data.iterations?.recent ?? []} />
    </div>
  );
}

function PrCiPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Open PRs" value={data.prs?.open ?? 0} />
        <Kpi label="CI failed" value={data.prs?.ci_failed ?? 0} />
        <Kpi label="Eligible" value={data.prs?.eligible ?? 0} />
        <Kpi label="Blocked" value={data.automerge?.blocked ?? data.prs?.blocked ?? 0} />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <PrTable prs={data.prs} />
        </div>
        <aside className="dashboard-grid__side">
          <AutoMergePanel summary={data.automerge} />
          <ApprovalQueuePanel apiBase={apiBase} />
        </aside>
      </section>
    </div>
  );
}

function NotificationsPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Sent" value={data.notifications?.sent ?? 0} />
        <Kpi label="Skipped" value={data.notifications?.skipped ?? 0} />
        <Kpi label="Failed" value={data.notifications?.failed ?? 0} />
        <Kpi label="Bootstrap" value={data.notifications?.bootstrap_fallback.status ?? "unknown"} />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <NotificationList apiBase={apiBase} />
          <ProductTable title="Recent notification attempts" rows={(data.notifications?.recent ?? []).map((item) => [item.message.title, item.provider, item.status, item.error ?? item.severity ?? "metadata"])} />
        </div>
        <aside className="dashboard-grid__side">
          <ProviderStatusPanel apiBase={apiBase} />
          <DocLinks links={[
            ["Bootstrap setup", "docs/notifications/BOOTSTRAP_NOTIFICATIONS.md"],
            ["Dashboard quickstart", "docs/product/QUICKSTART_DASHBOARD.md"]
          ]} />
        </aside>
      </section>
    </div>
  );
}

function HermesPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  const hermes = data.hermes;
  return (
    <div className="route-stack">
      <section className="kpi-grid">
        <Kpi label="Status" value={hermes?.status ?? "placeholder"} />
        <Kpi label="Tunnel" value={hermes?.tunnel.status ?? "unknown"} />
        <Kpi label="API health" value={hermes?.api.health ?? "unknown"} />
        <Kpi label="Public exposure" value={hermes?.tunnel.public_exposure ? "yes" : "no"} />
      </section>
      <section className="dashboard-grid">
        <div className="dashboard-grid__main">
          <SummaryCard title="Supervisor" state={hermes?.status ?? "placeholder"} lines={[
            `Capabilities: ${hermes?.capabilities.join(", ") || "none observed"}`,
            `Last safe run: ${hermes?.last_safe_run?.run_id ?? "none"}`,
            `Nightly report: ${hermes?.nightly_report?.summary ?? "none"}`,
            `Sweep dry-run: ${hermes?.sweep_dry_run?.summary ?? "none"}`,
            `Degraded reason: ${hermes?.degraded_reason ?? "none"}`
          ]} />
          <EventTimeline apiBase={apiBase} filters={{ platform: "hermes" }} />
        </div>
        <aside className="dashboard-grid__side">
          <DocLinks links={[["Cloud supervisor runbook", "docs/hermes/CLOUD_SUPERVISOR_RUNBOOK.md"]]} />
        </aside>
      </section>
    </div>
  );
}

function SourcesAuditPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <ProductTable title="Sources and adapters" rows={(data.summary?.sources ?? []).map((source) => [source.platform, source.adapter, `${source.event_count} events`, formatDateTime(source.latest_event_at)])} />
      <ProductTable title="Audit trail" rows={(data.audit ?? []).map((entry) => [entry.action, entry.actor, entry.safety_decision, entry.raw_payload_included ? "raw" : "metadata only"])} />
    </div>
  );
}

function SettingsPage({ apiBase }: { apiBase: string }) {
  const data = useProductData(apiBase);
  return (
    <div className="route-stack">
      <section className="skybridge-panel">
        <div className="skybridge-card__header">
          <div>
            <p className="skybridge-kicker">Settings</p>
            <h2>Local product console</h2>
          </div>
          <span className="skybridge-state">{data.summary?.health.persistence ?? "unknown"}</span>
        </div>
        <dl className="settings-list">
          <div><dt>API base</dt><dd>{apiBase}</dd></div>
          <div><dt>Database</dt><dd>{data.summary?.health.dbFile ?? "memory or unavailable"}</dd></div>
          <div><dt>Secrets shown</dt><dd>no</dd></div>
          <div><dt>Auto-merge default</dt><dd>{data.automerge?.enabled_by_default ? "enabled" : "disabled"}</dd></div>
          <div><dt>Hermes public exposure</dt><dd>{data.hermes?.tunnel.public_exposure ? "yes" : "no"}</dd></div>
        </dl>
      </section>
      <DocLinks links={[
        ["Product spec", "docs/product/OPERATOR_CONSOLE_PRODUCT_SPEC.md"],
        ["Dashboard quickstart", "docs/product/QUICKSTART_DASHBOARD.md"],
        ["API overview", "docs/api/API_OVERVIEW.md"],
        ["Security", "SECURITY.md"]
      ]} />
    </div>
  );
}

function useProductData(apiBase: string) {
  const client = useMemo(() => new SkyBridgeClient(apiBase), [apiBase]);
  const [summary, setSummary] = useState<SummaryResponse | undefined>();
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [iterations, setIterations] = useState<IterationsSummary | undefined>();
  const [prs, setPrs] = useState<PrsSummary | undefined>();
  const [notifications, setNotifications] = useState<NotificationsSummary | undefined>();
  const [hermes, setHermes] = useState<HermesSummary | undefined>();
  const [automerge, setAutoMerge] = useState<AutoMergeSummary | undefined>();
  const [audit, setAudit] = useState<AuditEntry[]>([]);
  const [error, setError] = useState<string | undefined>();

  useEffect(() => {
    let cancelled = false;
    void Promise.all([
      client.getSummary(),
      client.listProjects(),
      client.getIterationsSummary(),
      client.getPrsSummary(),
      client.getNotificationsSummary(),
      client.getHermesSummary(),
      client.getAutoMergeSummary(),
      client.listAuditEntries({ limit: 20 })
    ]).then(([nextSummary, nextProjects, nextIterations, nextPrs, nextNotifications, nextHermes, nextAutoMerge, nextAudit]) => {
      if (cancelled) return;
      setSummary(nextSummary);
      setProjects(nextProjects);
      setIterations(nextIterations);
      setPrs(nextPrs);
      setNotifications(nextNotifications);
      setHermes(nextHermes);
      setAutoMerge(nextAutoMerge);
      setAudit(nextAudit);
      setError(undefined);
    }).catch((err) => {
      if (!cancelled) setError(err instanceof Error ? err.message : String(err));
    });
    return () => {
      cancelled = true;
    };
  }, [client]);

  return { summary, projects, iterations, prs, notifications, hermes, automerge, audit, error };
}

function IterationList({ iterations }: { iterations: IterationsSummary["recent"] }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div><p className="skybridge-kicker">Iterations</p><h2>Controller history</h2></div>
        <span className="skybridge-state">{iterations.length}</span>
      </div>
      {iterations.length === 0 ? <p className="skybridge-state-note">No iterations recorded.</p> : null}
      <ol className="rich-list">
        {iterations.map((iteration) => (
          <li key={iteration.iteration_id}>
            <div>
              <strong>{iteration.iteration_id}</strong>
              <small>{iteration.project_id} · {iteration.branch} · PR {iteration.pr_number ? `#${iteration.pr_number}` : "none"}</small>
              <small>Blocked reason: {iteration.blocked_reason ?? "none"} · repairs {iteration.repair_attempts}/{iteration.max_attempts}</small>
            </div>
            <span className={badgeClass(iteration.state === "blocked" || iteration.state === "failed" || iteration.state === "ci_failed" ? "bad" : "ok")}>{iteration.state}</span>
          </li>
        ))}
      </ol>
    </section>
  );
}

function PrTable({ prs }: { prs?: PrsSummary }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div><p className="skybridge-kicker">Pull Requests</p><h2>PR and CI readiness</h2></div>
        <span className="skybridge-state">{prs?.open ?? 0} open</span>
      </div>
      <div className="data-table">
        <div className="data-table__head"><span>PR</span><span>CI</span><span>Eligibility</span><span>Risk / reason</span></div>
        {(prs?.prs ?? []).map((pr) => (
          <div className="data-table__row" key={pr.pr_number}>
            <span>#{pr.pr_number}<small>{pr.branch ?? "unknown branch"}</small></span>
            <span>{pr.ci_state}<small>{pr.required_checks.map((check) => `${check.name}:${check.status}`).join(", ") || "no checks"}</small></span>
            <span>{pr.eligibility}</span>
            <span>{pr.risk}<small>{pr.reasons.join("; ") || "no classifier reason"}</small></span>
          </div>
        ))}
      </div>
    </section>
  );
}

function AutoMergePanel({ summary }: { summary?: AutoMergeSummary }) {
  return (
    <SummaryCard title="Auto-merge dry-run" state={`${summary?.eligible ?? 0} eligible`} lines={[
      `Enabled by default: ${summary?.enabled_by_default ? "yes" : "no"}`,
      `Dry-run default: ${summary?.dry_run_default ? "yes" : "no"}`,
      `Blocked: ${summary?.blocked ?? 0}`,
      `Pending: ${summary?.pending ?? 0}`
    ]} />
  );
}

function FailureList({ failures }: { failures: RunSummary[] }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div><p className="skybridge-kicker">Failures</p><h2>Recent failures</h2></div>
        <span className={badgeClass(failures.length ? "bad" : "ok")}>{failures.length}</span>
      </div>
      {failures.length === 0 ? <p className="skybridge-state-note">No recent failed runs.</p> : null}
      <ol className="rich-list">
        {failures.map((run) => (
          <li key={run.run_id}>
            <div>
              <strong>{run.title ?? run.run_id}</strong>
              <small>{run.source_platform}/{run.source_adapter} · {run.latest_message_summary ?? "safe metadata only"}</small>
            </div>
            <span className="skybridge-state skybridge-state--bad">failed</span>
          </li>
        ))}
      </ol>
    </section>
  );
}

function ProductTable({ title, rows }: { title: string; rows: Array<Array<React.ReactNode>> }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div><p className="skybridge-kicker">Product data</p><h2>{title}</h2></div>
        <span className="skybridge-state">{rows.length}</span>
      </div>
      {rows.length === 0 ? <p className="skybridge-state-note">No local records yet.</p> : null}
      <div className="product-rows">
        {rows.map((row, index) => (
          <div className="product-row" key={index}>
            {row.map((cell, cellIndex) => <span key={cellIndex}>{cell}</span>)}
          </div>
        ))}
      </div>
    </section>
  );
}

function SummaryCard({ title, state, lines }: { title: string; state: string; lines: string[] }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div><p className="skybridge-kicker">Summary</p><h2>{title}</h2></div>
        <span className={badgeClass(state.includes("degraded") || state.includes("blocked") ? "bad" : "ok")}>{state}</span>
      </div>
      <ul className="summary-lines">
        {lines.map((line) => <li key={line}>{line}</li>)}
      </ul>
    </section>
  );
}

function DocLinks({ links }: { links: Array<[string, string]> }) {
  return (
    <section className="skybridge-panel">
      <div className="skybridge-card__header">
        <div><p className="skybridge-kicker">Docs</p><h2>Runbooks</h2></div>
      </div>
      <div className="doc-links">
        {links.map(([label, href]) => <a key={href} href={href}>{label}</a>)}
      </div>
    </section>
  );
}

function Kpi({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <section className="kpi-card">
      <span>{label}</span>
      <strong>{value}</strong>
    </section>
  );
}

function useHashRoute(): Route {
  const [route, setRoute] = useState<Route>(() => parseRoute());
  useEffect(() => {
    const onHashChange = () => setRoute(parseRoute());
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);
  return route;
}

function parseRoute(): Route {
  const value = window.location.hash.replace(/^#\/?/, "");
  if (value === "embed/compact" || window.location.pathname.startsWith("/embed/compact")) return "embed";
  return navItems.some((item) => item.route === value) ? value as Route : "overview";
}

function titleForRoute(route: Route): string {
  if (route === "pr-ci") return "PR/CI";
  return route.charAt(0).toUpperCase() + route.slice(1);
}

function badgeClass(kind: "ok" | "bad") {
  return `skybridge-state ${kind === "bad" ? "skybridge-state--bad" : ""}`;
}

function formatDateTime(input: string | undefined): string {
  return input ? new Date(input).toLocaleString() : "not yet";
}

createRoot(document.getElementById("root")!).render(<App />);
