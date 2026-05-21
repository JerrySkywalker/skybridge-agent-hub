import { describe, expect, it } from "vitest";
import { normalize } from "./index.js";

describe("codex exec json adapter", () => {
  it("normalizes result messages without retaining free-form summaries", () => {
    const [event] = normalize({
      type: "result",
      session_id: "session-1",
      run_id: "run-1",
      summary: "full command output: secret-token"
    });

    expect(event?.type).toBe("run.completed");
    expect(event?.correlation?.run_id).toBe("run-1");
    expect(event?.payload).toMatchObject({
      raw_type: "result",
      summary_present: true,
      summary_length: "full command output: secret-token".length
    });
    expect(JSON.stringify(event?.payload)).not.toContain("secret-token");
  });

  it("marks error messages as failed runs", () => {
    const [event] = normalize({ type: "error", run_id: "run-2" });

    expect(event?.type).toBe("run.failed");
    expect(event?.severity).toBe("error");
  });
});
