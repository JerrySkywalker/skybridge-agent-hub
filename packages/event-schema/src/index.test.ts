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
});
