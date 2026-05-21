import { createEvent, type SkyBridgeEvent } from "@skybridge-agent-hub/event-schema";

export function normalize(input: unknown): SkyBridgeEvent[] {
  if (!input || typeof input !== "object") return [];
  const event = input as Record<string, unknown>;
  const status = typeof event.status === "string" ? event.status : "running";
  return [
    createEvent({
      type: status === "failed" ? "run.failed" : status === "completed" ? "run.completed" : "run.started",
      severity: status === "failed" ? "error" : "info",
      source: { platform: "codex", adapter: "codex-appserver" },
      correlation: {
        session_id: typeof event.sessionId === "string" ? event.sessionId : undefined,
        run_id: typeof event.runId === "string" ? event.runId : undefined
      },
      payload: {
        status,
        title: typeof event.title === "string" ? event.title : undefined
      }
    })
  ];
}
