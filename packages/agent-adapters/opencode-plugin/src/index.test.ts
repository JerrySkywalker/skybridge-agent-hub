import { describe, expect, it } from "vitest";
import { SkyBridgeEventSchema } from "@skybridge-agent-hub/event-schema";
import { normalize } from "./index.js";

const fixtures = [
  { type: "session:start", sessionId: "opencode-session-1", runId: "opencode-run-1", cwd: "C:\\Users\\jerry\\repo" },
  { type: "run:status", status: "idle", sessionId: "opencode-session-1", runId: "opencode-run-1" },
  { type: "run:error", summary: "token=abc123 failed", sessionId: "opencode-session-1", runId: "opencode-run-1" },
  { type: "tool:start", toolCallId: "tool-1", toolName: "bash", sessionId: "opencode-session-1", runId: "opencode-run-1" },
  { type: "tool:end", toolCallId: "tool-1", toolName: "bash", summary: "completed without stdout", sessionId: "opencode-session-1", runId: "opencode-run-1" },
  { type: "file:edited", path: "C:\\Users\\jerry\\repo\\src\\index.ts", sessionId: "opencode-session-1", runId: "opencode-run-1" },
  { type: "approval:request", permission: "edit", sessionId: "opencode-session-1", runId: "opencode-run-1" },
  { type: "approval:reply", decision: "denied", sessionId: "opencode-session-1", runId: "opencode-run-1" },
  { type: "todo:update", todos: [{ text: "one", done: true }, { text: "two", done: false }], sessionId: "opencode-session-1", runId: "opencode-run-1" }
];

describe("opencode plugin adapter", () => {
  it("normalizes representative OpenCode fixtures", () => {
    const events = fixtures.flatMap((fixture) => normalize(fixture));
    expect(events.map((event) => event.type)).toEqual([
      "session.started",
      "agent.idle",
      "run.failed",
      "tool.started",
      "tool.completed",
      "file.edited",
      "approval.requested",
      "approval.resolved",
      "todo.updated"
    ]);
    for (const event of events) expect(() => SkyBridgeEventSchema.parse(event)).not.toThrow();
  });

  it("handles malformed/minimal payloads and redacts obvious secrets", () => {
    expect(normalize(null)).toEqual([]);
    const [event] = normalize({ summary: "Bearer abc.def.ghi token=abc123" });
    expect(event?.type).toBe("message.completed");
    expect(JSON.stringify(event?.payload)).not.toContain("abc.def.ghi");
    expect(JSON.stringify(event?.payload)).not.toContain("abc123");
  });
});
