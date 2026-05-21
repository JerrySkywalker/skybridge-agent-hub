import { describe, expect, it } from "vitest";
import { SkyBridgeEventSchema } from "@skybridge-agent-hub/event-schema";
import { normalize } from "./index.js";

const fixtures = [
  { id: "hermes-run-1", status: "created", title: "Hermes run created" },
  { id: "hermes-run-1", status: "queued", queue: "default" },
  { id: "hermes-run-1", status: "running" },
  { id: "hermes-run-1", status: "completed", detail: "finished" },
  { id: "hermes-run-2", status: "failed", detail: "password=abc123 failed" },
  { runId: "hermes-run-3", event_type: "tool_started", toolCallId: "tool-1", toolName: "shell" },
  { runId: "hermes-run-3", event_type: "tool_completed", toolCallId: "tool-1", toolName: "shell", exitCode: 0 },
  { runId: "hermes-run-3", kind: "status", message: "stream status" }
];

describe("hermes api adapter", () => {
  it("normalizes Hermes run and stream fixtures", () => {
    const events = fixtures.flatMap((fixture) => normalize(fixture));
    expect(events.map((event) => event.type)).toEqual([
      "run.started",
      "run.started",
      "run.started",
      "run.completed",
      "run.failed",
      "tool.started",
      "tool.completed",
      "message.completed"
    ]);
    for (const event of events) expect(() => SkyBridgeEventSchema.parse(event)).not.toThrow();
  });

  it("handles malformed/minimal payloads and redacts obvious secrets", () => {
    expect(normalize(undefined)).toEqual([]);
    const [event] = normalize({ status: "failed", detail: "Bearer abc.def token=abc123" });
    expect(event?.type).toBe("run.failed");
    expect(JSON.stringify(event?.payload)).not.toContain("abc.def");
    expect(JSON.stringify(event?.payload)).not.toContain("abc123");
  });
});
