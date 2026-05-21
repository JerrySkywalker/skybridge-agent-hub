import type { RunDetail, RunSummary, SkyBridgeEvent, SkyBridgeEventType, SkyBridgeSeverity, SkyBridgeSourcePlatform, SourceCapability } from "@skybridge-agent-hub/event-schema";

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
    notifications: number;
    notification_failed?: number;
    notification_skipped?: number;
    nodes?: number;
    node_stale?: number;
    attention_items: number;
  };
  sources: Array<{
    platform: string;
    adapter: string;
    event_count: number;
    latest_event_at: string;
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

  async listAuditEntries(): Promise<AuditEntry[]> {
    const json = await this.getJson<{ audit: AuditEntry[] }>("/v1/audit");
    return json.audit;
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
