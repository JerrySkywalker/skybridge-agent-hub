import type { IterationRun, RunDetail, RunSummary, SkyBridgeEvent, SkyBridgeEventType, SkyBridgeSeverity, SkyBridgeSourcePlatform, SourceCapability } from "@skybridge-agent-hub/event-schema";

export interface NotificationRequest {
  title: string;
  body: string;
  priority?: "low" | "default" | "high" | "urgent";
  url?: string;
}

export interface SkyBridgeHealth {
  ok: boolean;
  service: string;
  persistence: "memory" | "sqlite";
  dbFile?: string;
  jsonMigrationFile?: string;
  time: string;
}

export interface StoredNotification {
  id: string;
  category?: string;
  severity?: string;
  source_event_id?: string;
  target?: string;
  provider: "ntfy" | "apprise" | "gotify" | "bark" | "wecom" | "fcm" | "xiaomi-push" | "placeholder";
  dedupe_key?: string;
  status: "pending" | "sent" | "skipped" | "failed";
  retry_count?: number;
  message: NotificationRequest;
  createdAt: string;
  updatedAt?: string;
  error?: string;
}

export interface SummaryResponse {
  health: SkyBridgeHealth;
  totals: {
    events: number;
    runs: number;
    active_runs: number;
    failed_runs: number;
    open_prs?: number;
    ci_failed?: number;
    notifications: number;
    notification_failed?: number;
    notification_skipped?: number;
    nodes?: number;
    node_stale?: number;
    automerge_blocked?: number;
    attention_items: number;
  };
  latest?: {
    ci_state?: string;
    automerge_sweep?: AutoMergeSummary["latest_sweep"];
    iteration?: IterationRun;
    hermes_status?: string;
    notification?: StoredNotification;
    failure?: RunSummary;
    next_recommended_action?: string;
  };
  recent_failures?: RunSummary[];
  sources: Array<{
    platform: string;
    adapter: string;
    event_count: number;
    latest_event_at: string;
  }>;
}

export interface ProjectSummary {
  project_id: string;
  run_count: number;
  active_runs: number;
  failed_runs: number;
  iteration_count: number;
  latest_activity_at?: string;
}

export interface IterationsSummary {
  total: number;
  active: number;
  blocked: number;
  failed: number;
  repair_attempts: number;
  latest?: IterationRun;
  recent: Array<IterationRun & { blocked_reason?: string; repair_attempts: number; raw_logs_included: false }>;
}

export interface PrSummaryItem {
  pr_number: number;
  branch?: string;
  repo?: string;
  state: "open" | "merged" | "blocked" | "unknown";
  ci_state: string;
  required_checks: Array<{ name: string; status: string; summary?: string }>;
  eligibility: "eligible" | "blocked" | "pending" | "unknown";
  risk: "low" | "needs_review" | "blocked" | "unknown";
  reasons: string[];
  updated_at: string;
}

export interface PrsSummary {
  total: number;
  open: number;
  merged: number;
  blocked: number;
  eligible: number;
  ci_failed: number;
  latest_ci_state: string;
  prs: PrSummaryItem[];
}

export interface NotificationsSummary {
  total: number;
  sent: number;
  skipped: number;
  failed: number;
  pending: number;
  by_severity: Record<string, number>;
  providers: Array<{ provider: string; configured: boolean; status: string; required_env: string; credential_values_exposed: boolean }>;
  bootstrap_fallback: {
    status: string;
    script: string;
    real_send_requires_explicit_send: boolean;
  };
  latest?: StoredNotification;
  recent: StoredNotification[];
}

export interface HermesSummary {
  status: "available" | "degraded" | "placeholder";
  tunnel: { status: string; public_exposure: false };
  api: { health: string; base_publicly_exposed: false };
  capabilities: string[];
  last_safe_run?: { event_id: string; run_id?: string; time: string };
  nightly_report?: { event_id: string; time: string; summary: string };
  sweep_dry_run?: { event_id: string; time: string; summary: string };
  degraded_reason?: string;
  related_iterations: IterationRun[];
}

export interface AutoMergeSummary {
  enabled_by_default: false;
  dry_run_default: true;
  total_prs: number;
  eligible: number;
  blocked: number;
  pending: number;
  merged_history: AuditEntry[];
  latest_sweep?: {
    event_id: string;
    time: string;
    mode: string;
    dry_run: boolean;
    summary?: string;
    eligible?: number;
    blocked?: number;
  };
  decisions: Array<{
    pr_number: number;
    eligibility: PrSummaryItem["eligibility"];
    risk: PrSummaryItem["risk"];
    reasons: string[];
    required_checks: PrSummaryItem["required_checks"];
  }>;
}

export interface NodeSummary {
  node_id: string;
  host?: string;
  labels: string[];
  capabilities: string[];
  sidecar_version?: string;
  last_seen: string;
  status: "connected" | "stale" | "disconnected";
  event_count: number;
}

export interface ApprovalSummary {
  approval_id: string;
  run_id?: string;
  session_id?: string;
  status: "pending" | "accepted" | "denied" | "expired";
  title?: string;
  requested_at: string;
  resolved_at?: string;
  source: string;
}

export interface MetricsResponse {
  total_events: number;
  runs_by_status: Record<string, number>;
  runs_by_source: Record<string, number>;
  notifications_by_status: Record<string, number>;
  notifications_by_severity: Record<string, number>;
  node_status_counts: Record<string, number>;
  recent_failures: RunSummary[];
}

export interface AuditEntry {
  audit_id: string;
  time: string;
  action: string;
  actor: string;
  source_adapter: string;
  run_id?: string;
  session_id?: string;
  safety_decision: string;
  immutable_event_id: string;
  redaction_policy_version: string;
  raw_payload_included: false;
}

export interface StreamEventsOptions {
  onEvent: (event: SkyBridgeEvent) => void;
  onOpen?: () => void;
  onError?: (error: Event) => void;
}

export class SkyBridgeClient {
  constructor(private readonly apiBase: string) {}

  async getHealth(): Promise<SkyBridgeHealth> {
    return this.getJson<SkyBridgeHealth>("/v1/health");
  }

  async sendEvent(event: SkyBridgeEvent): Promise<{ ok: boolean; id: string }> {
    const response = await fetch(this.url("/v1/events"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(event)
    });
    await assertOk(response, "event ingest");
    return response.json() as Promise<{ ok: boolean; id: string }>;
  }

  async listEvents(query: EventListQuery = {}): Promise<SkyBridgeEvent[]> {
    const json = await this.getJson<{ events: SkyBridgeEvent[] }>(`/v1/events${queryString(query)}`);
    return json.events;
  }

  async listRuns(query: RunListQuery = {}): Promise<RunSummary[]> {
    const json = await this.getJson<{ runs: RunSummary[] }>(`/v1/runs${queryString(query)}`);
    return json.runs;
  }

  async getRun(runId: string, query: { limit?: number } = {}): Promise<RunDetail> {
    return this.getJson<RunDetail>(`/v1/runs/${encodeURIComponent(runId)}${queryString(query)}`);
  }

  async listNotifications(query: NotificationListQuery = {}): Promise<StoredNotification[]> {
    const json = await this.getJson<{ notifications: StoredNotification[] }>(`/v1/notifications${queryString(query)}`);
    return json.notifications;
  }

  async getSummary(): Promise<SummaryResponse> {
    return this.getJson<SummaryResponse>("/v1/summary");
  }

  async listProjects(): Promise<ProjectSummary[]> {
    const json = await this.getJson<{ projects: ProjectSummary[] }>("/v1/projects");
    return json.projects;
  }

  async getIterationsSummary(): Promise<IterationsSummary> {
    return this.getJson<IterationsSummary>("/v1/iterations/summary");
  }

  async getPrsSummary(): Promise<PrsSummary> {
    return this.getJson<PrsSummary>("/v1/prs/summary");
  }

  async getNotificationsSummary(): Promise<NotificationsSummary> {
    return this.getJson<NotificationsSummary>("/v1/notifications/summary");
  }

  async getHermesSummary(): Promise<HermesSummary> {
    return this.getJson<HermesSummary>("/v1/hermes/summary");
  }

  async getAutoMergeSummary(): Promise<AutoMergeSummary> {
    return this.getJson<AutoMergeSummary>("/v1/automerge/summary");
  }

  async listSources(): Promise<SourceCapability[]> {
    const json = await this.getJson<{ sources: SourceCapability[] }>("/v1/sources");
    return json.sources;
  }

  async listNodes(): Promise<NodeSummary[]> {
    const json = await this.getJson<{ nodes: NodeSummary[] }>("/v1/nodes");
    return json.nodes;
  }

  async listNotificationProviders(): Promise<Array<{ provider: string; configured: boolean; status: string; required_env: string; credential_values_exposed: boolean }>> {
    const json = await this.getJson<{ providers: Array<{ provider: string; configured: boolean; status: string; required_env: string; credential_values_exposed: boolean }> }>("/v1/notifications/providers");
    return json.providers;
  }

  async getMetrics(): Promise<MetricsResponse> {
    return this.getJson<MetricsResponse>("/v1/metrics");
  }

  async listAuditEntries(query: AuditListQuery = {}): Promise<AuditEntry[]> {
    const json = await this.getJson<{ audit: AuditEntry[] }>(`/v1/audit${queryString(query)}`);
    return json.audit;
  }

  async listIterations(): Promise<IterationRun[]> {
    const json = await this.getJson<{ iterations: IterationRun[] }>("/v1/iterations");
    return json.iterations;
  }

  async getIteration(iterationId: string): Promise<IterationRun & { events?: Array<{ type: string; time: string; payload: Record<string, unknown> }> }> {
    const json = await this.getJson<{ iteration: IterationRun & { events?: Array<{ type: string; time: string; payload: Record<string, unknown> }> } }>(`/v1/iterations/${encodeURIComponent(iterationId)}`);
    return json.iteration;
  }

  async getSupervisorStatus(): Promise<SupervisorStatus> {
    return this.getJson<SupervisorStatus>("/v1/supervisor/status");
  }

  async getSupervisorNextAction(): Promise<SupervisorNextAction> {
    return this.getJson<SupervisorNextAction>("/v1/supervisor/next-action");
  }

  async listApprovals(): Promise<ApprovalSummary[]> {
    const json = await this.getJson<{ approvals: ApprovalSummary[] }>("/v1/approvals");
    return json.approvals;
  }

  async sendNotification(message: NotificationRequest): Promise<{ ok: boolean; provider: string }> {
    const response = await fetch(this.url("/v1/notifications/send"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(message)
    });
    await assertOk(response, "notification request");
    return response.json() as Promise<{ ok: boolean; provider: string }>;
  }

  streamEvents(optionsOrHandler: StreamEventsOptions | ((event: SkyBridgeEvent) => void)): EventSource {
    const options = typeof optionsOrHandler === "function" ? { onEvent: optionsOrHandler } : optionsOrHandler;
    const source = new EventSource(this.url("/v1/stream"));
    if (options.onOpen) source.addEventListener("open", options.onOpen);
    if (options.onError) source.addEventListener("error", options.onError);
    source.addEventListener("skybridge.event", (message) => {
      options.onEvent(JSON.parse((message as MessageEvent).data) as SkyBridgeEvent);
    });
    return source;
  }

  private async getJson<T>(path: string): Promise<T> {
    const response = await fetch(this.url(path));
    await assertOk(response, "request");
    return response.json() as Promise<T>;
  }

  private url(path: string): string {
    return `${this.apiBase.replace(/\/$/, "")}${path}`;
  }
}

export interface EventListQuery {
  run_id?: string;
  session_id?: string;
  platform?: SkyBridgeSourcePlatform;
  adapter?: string;
  source_platform?: SkyBridgeSourcePlatform;
  source_adapter?: string;
  type?: SkyBridgeEventType;
  severity?: SkyBridgeSeverity;
  from?: string;
  to?: string;
  limit?: number;
  offset?: number;
}

export interface RunListQuery {
  platform?: SkyBridgeSourcePlatform;
  adapter?: string;
  source_platform?: SkyBridgeSourcePlatform;
  source_adapter?: string;
  status?: RunSummary["status"];
  lifecycle?: string;
  branch?: string;
  goal?: string;
  from?: string;
  to?: string;
  limit?: number;
}

export interface NotificationListQuery {
  status?: StoredNotification["status"];
  provider?: StoredNotification["provider"];
  severity?: SkyBridgeSeverity;
  limit?: number;
}

export interface AuditListQuery {
  action?: string;
  actor?: string;
  run_id?: string;
  from?: string;
  to?: string;
  limit?: number;
}

export interface SupervisorStatus {
  ok: boolean;
  raw_prompts_included: false;
  raw_logs_included: false;
  notification_path?: {
    primary_for_skybridge_development: string;
    skybridge_notification_center_required: boolean;
    migration_stage: string;
  };
  iterations: {
    total: number;
    active: number;
    blocked: number;
    latest?: IterationRun;
  };
  recent_iteration_events: SkyBridgeEvent[];
}

export interface SupervisorNextAction {
  action: string;
  reason?: string;
  iteration_id?: string;
  pr_number?: number;
  state?: string;
}

function queryString(query: object): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined) params.set(key, String(value));
  }
  const text = params.toString();
  return text ? `?${text}` : "";
}

async function assertOk(response: Response, label: string): Promise<void> {
  if (response.ok) return;
  let detail = "";
  try {
    detail = `: ${JSON.stringify(await response.json())}`;
  } catch {
    detail = "";
  }
  throw new Error(`${label} failed with HTTP ${response.status}${detail}`);
}
