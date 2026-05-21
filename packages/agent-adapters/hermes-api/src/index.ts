import { createEvent, type SkyBridgeEvent, type SkyBridgeEventType } from "@skybridge-agent-hub/event-schema";

const statusMap: Record<string, SkyBridgeEventType> = {
  created: "run.started",
  queued: "run.started",
  running: "run.started",
  succeeded: "run.completed",
  completed: "run.completed",
  failed: "run.failed",
  error: "run.failed",
  waiting_for_approval: "approval.requested",
  tool_started: "tool.started",
  tool_completed: "tool.completed",
  tool_failed: "tool.failed"
};

export function normalize(input: unknown): SkyBridgeEvent[] {
  if (!input || typeof input !== "object") return [];
  const event = input as Record<string, unknown>;
  const explicitStatus = firstString(event.status, event.state, event.event_type, event.type);
  const status = explicitStatus ?? "running";
  const normalizedType = explicitStatus ? statusMap[explicitStatus] ?? typeFromStream(event) : typeFromStream(event);
  return [
    createEvent({
      type: normalizedType,
      severity: normalizedType === "run.failed" || normalizedType === "tool.failed" || status === "error" ? "error" : normalizedType === "approval.requested" ? "warning" : "info",
      source: {
        platform: "hermes",
        adapter: "hermes-api",
        agent_id: firstString(event.agentId, event.agent_id, event.agent) ?? "hermes",
        node_id: firstString(event.nodeId, event.node_id)
      },
      correlation: {
        session_id: firstString(event.sessionId, event.session_id),
        run_id: firstString(event.runId, event.run_id, event.id),
        tool_call_id: firstString(event.toolCallId, event.tool_call_id, event.tool_id)
      },
      payload: {
        status,
        title: boundedString(firstString(event.title, event.name), 120),
        detail: boundedString(firstString(event.detail, event.message), 180),
        queue: boundedString(firstString(event.queue, event.queue_name), 80),
        tool_name: boundedString(firstString(event.tool, event.toolName, event.tool_name), 80),
        exit_code: typeof event.exitCode === "number" ? event.exitCode : undefined,
        redaction: "adapter omits raw prompts, stdout, stderr and tool result bodies"
      }
    })
  ];
}

function typeFromStream(event: Record<string, unknown>): SkyBridgeEventType {
  const kind = firstString(event.kind, event.event);
  if (kind === "tool") return "tool.completed";
  if (kind === "status") return "message.completed";
  return "run.started";
}

function firstString(...values: unknown[]): string | undefined {
  return values.find((value): value is string => typeof value === "string" && value.length > 0);
}

function boundedString(value: string | undefined, max: number): string | undefined {
  if (!value) return undefined;
  return redactSecrets(value.length > max ? `${value.slice(0, max)}...` : value);
}

function redactSecrets(value: string): string {
  return value
    .replace(/(sk-[A-Za-z0-9_-]{12,})/g, "[REDACTED]")
    .replace(/(Bearer\s+)[A-Za-z0-9._-]+/gi, "$1[REDACTED]")
    .replace(/(token|password|secret|cookie)=\S+/gi, "$1=[REDACTED]");
}
