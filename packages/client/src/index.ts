import type { RunDetail, RunSummary, SkyBridgeEvent, SkyBridgeEventType } from "@skybridge-agent-hub/event-schema";

export interface NotificationRequest {
  title: string;
  body: string;
  priority?: "low" | "default" | "high" | "urgent";
  url?: string;
}

export class SkyBridgeClient {
  constructor(private readonly apiBase: string) {}

  async sendEvent(event: SkyBridgeEvent): Promise<{ ok: boolean; id: string }> {
    const response = await fetch(`${this.apiBase}/v1/events`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(event)
    });
    if (!response.ok) throw new Error(`event ingest failed with HTTP ${response.status}`);
    return response.json() as Promise<{ ok: boolean; id: string }>;
  }

  async listEvents(query: EventListQuery = {}): Promise<SkyBridgeEvent[]> {
    const response = await fetch(`${this.apiBase}/v1/events${queryString(query)}`);
    const json = await response.json() as { events: SkyBridgeEvent[] };
    return json.events;
  }

  async listRuns(): Promise<RunSummary[]> {
    const response = await fetch(`${this.apiBase}/v1/runs`);
    const json = await response.json() as { runs: RunSummary[] };
    return json.runs;
  }

  async getRun(runId: string): Promise<RunDetail> {
    const response = await fetch(`${this.apiBase}/v1/runs/${encodeURIComponent(runId)}`);
    if (!response.ok) throw new Error(`run lookup failed with HTTP ${response.status}`);
    return response.json() as Promise<RunDetail>;
  }

  async sendNotification(message: NotificationRequest): Promise<{ ok: boolean; provider: string }> {
    const response = await fetch(`${this.apiBase}/v1/notifications/send`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(message)
    });
    if (!response.ok) throw new Error(`notification request failed with HTTP ${response.status}`);
    return response.json() as Promise<{ ok: boolean; provider: string }>;
  }

  streamEvents(onEvent: (event: SkyBridgeEvent) => void): EventSource {
    const source = new EventSource(`${this.apiBase}/v1/stream`);
    source.addEventListener("skybridge.event", (message) => {
      onEvent(JSON.parse((message as MessageEvent).data));
    });
    return source;
  }
}

export interface EventListQuery {
  run_id?: string;
  session_id?: string;
  source_platform?: string;
  source_adapter?: string;
  type?: SkyBridgeEventType;
  from?: string;
  to?: string;
  limit?: number;
}

function queryString(query: EventListQuery): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined) params.set(key, String(value));
  }
  const text = params.toString();
  return text ? `?${text}` : "";
}
