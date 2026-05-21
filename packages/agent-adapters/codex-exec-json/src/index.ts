import { createEvent, type SkyBridgeEvent } from "@skybridge-agent-hub/event-schema";

export function normalize(input: unknown): SkyBridgeEvent[] {
  if (!input || typeof input !== "object") return [];
  const event = input as Record<string, unknown>;
  const messageType = typeof event.type === "string" ? event.type : "message";
  return [
    createEvent({
      type: messageType === "error" ? "run.failed" : messageType === "result" ? "run.completed" : "message.completed",
      severity: messageType === "error" ? "error" : "info",
      source: { platform: "codex", adapter: "codex-exec-json" },
      correlation: {
        session_id: typeof event.session_id === "string" ? event.session_id : undefined,
        run_id: typeof event.run_id === "string" ? event.run_id : undefined
      },
      payload: {
        raw_type: messageType,
        summary: typeof event.summary === "string" ? event.summary : undefined
      }
    })
  ];
}
