import { createEvent, type SkyBridgeEvent, type SkyBridgeEventType } from "@skybridge-agent-hub/event-schema";

const typeMap: Record<string, SkyBridgeEventType> = {
  "session:start": "session.started",
  "session:end": "session.completed",
  "run:start": "run.started",
  "run:done": "run.completed",
  "run:error": "run.failed",
  "tool:start": "tool.started",
  "tool:end": "tool.completed",
  "approval:request": "approval.requested",
  "message": "message.completed"
};

export function normalize(input: unknown): SkyBridgeEvent[] {
  if (!input || typeof input !== "object") return [];
  const event = input as Record<string, unknown>;
  const rawType = typeof event.type === "string" ? event.type : "message";
  return [
    createEvent({
      type: typeMap[rawType] ?? "message.completed",
      severity: rawType.includes("error") ? "error" : "info",
      source: {
        platform: "opencode",
        adapter: "opencode-plugin",
        agent_id: typeof event.agent === "string" ? event.agent : "opencode",
        cwd: typeof event.cwd === "string" ? event.cwd : undefined
      },
      correlation: {
        session_id: typeof event.sessionId === "string" ? event.sessionId : undefined,
        run_id: typeof event.runId === "string" ? event.runId : undefined,
        tool_call_id: typeof event.toolCallId === "string" ? event.toolCallId : undefined
      },
      payload: {
        raw_type: rawType,
        summary: typeof event.summary === "string" ? event.summary : undefined
      }
    })
  ];
}
