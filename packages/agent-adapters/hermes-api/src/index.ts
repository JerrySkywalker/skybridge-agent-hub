import { createEvent, type SkyBridgeEvent, type SkyBridgeEventType } from "@skybridge-agent-hub/event-schema";

const statusMap: Record<string, SkyBridgeEventType> = {
  queued: "run.started",
  running: "run.started",
  succeeded: "run.completed",
  completed: "run.completed",
  failed: "run.failed",
  error: "run.failed",
  waiting_for_approval: "approval.requested"
};

export function normalize(input: unknown): SkyBridgeEvent[] {
  if (!input || typeof input !== "object") return [];
  const event = input as Record<string, unknown>;
  const status = typeof event.status === "string" ? event.status : "running";
  return [
    createEvent({
      type: statusMap[status] ?? "run.started",
      severity: status === "failed" || status === "error" ? "error" : "info",
      source: {
        platform: "hermes",
        adapter: "hermes-api",
        agent_id: typeof event.agentId === "string" ? event.agentId : "hermes"
      },
      correlation: {
        session_id: typeof event.sessionId === "string" ? event.sessionId : undefined,
        run_id: typeof event.runId === "string" ? event.runId : typeof event.id === "string" ? event.id : undefined
      },
      payload: {
        status,
        title: typeof event.title === "string" ? event.title : undefined,
        detail: typeof event.detail === "string" ? event.detail : undefined
      }
    })
  ];
}
