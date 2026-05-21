import { describe, expect, it } from "vitest";
import { normalize, summarizeToolInput } from "./index.js";

describe("codex hook adapter", () => {
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

  it("redacts command content while preserving safe tool metadata", () => {
    const summary = summarizeToolInput({
      name: "Shell",
      command: "echo super-secret-token",
      stderr: "secret error",
      stdout: "secret output",
      file_path: "apps/server/src/index.ts"
    });

    expect(summary).toMatchObject({
      name: "Shell",
      command_present: true,
      command_length: "echo super-secret-token".length,
      file_path: "apps/server/src/index.ts"
    });
    expect(JSON.stringify(summary)).not.toContain("super-secret-token");
    expect(JSON.stringify(summary)).not.toContain("secret output");
    expect(JSON.stringify(summary)).not.toContain("secret error");
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
});
