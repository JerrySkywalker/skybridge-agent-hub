import { describe, expect, it } from "vitest";
import { createEvent, isNotificationTrigger, parseEvent } from "./index.js";

describe("event schema", () => {
  it("creates a normalized event", () => {
    const event = createEvent({
      type: "run.started",
      source: { platform: "codex", adapter: "codex-hook" },
      severity: "info",
      payload: {}
    });

    expect(event.schema).toBe("skybridge.agent_event.v1");
    expect(event.type).toBe("run.started");
  });

  it("validates source families used by first-party adapters", () => {
    for (const platform of ["codex", "opencode", "hermes"] as const) {
      const event = parseEvent({
        schema: "skybridge.agent_event.v1",
        time: new Date().toISOString(),
        type: "run.started",
        severity: "info",
        source: { platform, adapter: `${platform}-adapter` },
        correlation: { session_id: "s1", run_id: "r1" },
        payload: { message: "started" }
      });

      expect(event.source.platform).toBe(platform);
    }
  });

  it("identifies critical notification trigger events", () => {
    expect(isNotificationTrigger({ type: "run.failed" })).toBe(true);
    expect(isNotificationTrigger({ type: "approval.requested" })).toBe(true);
    expect(isNotificationTrigger({ type: "tool.completed" })).toBe(false);
  });

  it("allows rich run summary metadata without changing event validation", () => {
    const summary = {
      run_id: "runner-001-demo",
      session_id: "runner-123",
      source_platform: "skybridge",
      source_adapter: "yolo-runner",
      source_agent_id: "skybridge-yolo-runner",
      status: "running",
      event_count: 3,
      tool_call_count: 1,
      failed_tool_count: 0,
      notification_count: 1,
      first_seen_at: new Date().toISOString(),
      last_seen_at: new Date().toISOString(),
      last_event_type: "notification.requested",
      title: "001-demo.md",
      lifecycle: "notification.requested",
      branch: "ai/001-demo",
      goal_id: "001"
    };

    expect(summary.run_id).toBe("runner-001-demo");
    expect(summary.tool_call_count).toBe(1);
  });
});
