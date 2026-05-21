import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { normalize, redactUnknown, summarizeToolInput } from "./index.js";

const fixtureCases = [
  ["session-start-startup.json", "session.started"],
  ["session-start-resume.json", "session.started"],
  ["user-prompt-submit.json", "run.started"],
  ["pre-tool-use-bash.json", "tool.started"],
  ["post-tool-use-bash-success.json", "tool.completed"],
  ["post-tool-use-bash-failure.json", "tool.failed"],
  ["pre-tool-use-apply-patch.json", "tool.started"],
  ["permission-request.json", "approval.requested"],
  ["stop.json", "turn.completed"],
  ["malformed-minimal.json", "agent.idle"]
] as const;

function fixture(name: string): unknown {
  return JSON.parse(readFileSync(join(import.meta.dirname, "fixtures", name), "utf8"));
}

describe("codex hook adapter", () => {
  it.each(fixtureCases)("normalizes fixture %s safely", (fixtureName, expectedType) => {
    const events = normalize(fixture(fixtureName));
    const [event] = events;

    expect(event?.schema).toBe("skybridge.agent_event.v1");
    expect(event?.type).toBe(expectedType);
    expect(event?.source).toMatchObject({ platform: "codex", adapter: "codex-hook" });
    expect(JSON.stringify(events)).not.toMatch(/secret-token|hunter2|sk-test-secret|OPENAI_API_KEY=secret|abc123/);
  });

  it("normalizes hook events into SkyBridge events", () => {
    const [event] = normalize({
      hook_event_name: "PreToolUse",
      session_id: "session-1",
      run_id: "run-1",
      tool_call_id: "tool-1",
      cwd: "V:\\src\\skybridge-agent-hub",
      tool_input: { name: "Shell", command: "pnpm check", path: "package.json" }
    });

    expect(event?.schema).toBe("skybridge.agent_event.v1");
    expect(event?.type).toBe("tool.started");
    expect(event?.source.platform).toBe("codex");
    expect(event?.correlation?.run_id).toBe("run-1");
    expect(event?.payload.tool_name).toBe("Shell");
  });

  it("redacts command content while preserving bounded tool metadata", () => {
    const summary = summarizeToolInput({
      name: "Shell",
      command: "echo token=super-secret-token",
      stderr: "secret error",
      stdout: "secret output",
      file_path: "apps/server/src/index.ts"
    });

    expect(summary).toMatchObject({
      name: "Shell",
      command_present: true,
      command_length: "echo token=super-secret-token".length,
      file_path: "apps/server/src/index.ts"
    });
    expect(JSON.stringify(summary)).not.toContain("super-secret-token");
    expect(JSON.stringify(summary)).toContain("[REDACTED]");
  });

  it("marks permission requests as approval notifications", () => {
    const [event] = normalize({ hook_event_name: "PermissionRequest", session_id: "s1" });

    expect(event?.type).toBe("approval.requested");
    expect(event?.severity).toBe("warning");
  });

  it("falls back to conversation or session identifiers for grouping", () => {
    const [conversationEvent] = normalize({ hook_event_name: "UserPromptSubmit", conversation_id: "conversation-1" });
    const [sessionEvent] = normalize({ hook_event_name: "UserPromptSubmit", session_id: "session-1" });

    expect(conversationEvent?.correlation?.run_id).toBe("conversation-1");
    expect(sessionEvent?.correlation?.run_id).toBe("session-1");
  });

  it("handles malformed payloads without throwing", () => {
    expect(normalize(null)).toEqual([]);
    expect(normalize("not json")).toEqual([]);
    expect(normalize({})).toHaveLength(1);
    expect(normalize({}).at(0)?.type).toBe("agent.idle");
  });

  it("adds file and diff events for apply_patch without retaining patch content", () => {
    const events = normalize(fixture("pre-tool-use-apply-patch.json"));

    expect(events.map((event) => event.type)).toEqual(["tool.started", "file.edited", "diff.updated"]);
    expect(JSON.stringify(events)).not.toContain("OPENAI_API_KEY");
  });

  it("redacts nested secret-like fields and bounds unknown nested payloads", () => {
    const redacted = redactUnknown({
      Authorization: "Bearer secret-token",
      nested: { password: "hunter2", values: Array.from({ length: 30 }, (_, index) => ({ index, token: `t-${index}` })) }
    });

    const text = JSON.stringify(redacted);
    expect(text).not.toContain("secret-token");
    expect(text).not.toContain("hunter2");
    expect(text).not.toContain("t-29");
    expect(text).toContain("[REDACTED]");
  });
});
