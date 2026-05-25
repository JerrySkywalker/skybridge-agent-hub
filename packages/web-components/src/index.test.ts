import { describe, expect, it } from "vitest";
import { renderAgentStatusHtml } from "./index.js";

describe("agent status web component", () => {
  it("renders compact status markup", () => {
    const html = renderAgentStatusHtml({
      state: "attention",
      events: 12,
      runs: 3,
      activeRuns: 1,
      failedRuns: 1,
      openPrs: 2,
      ciFailed: 1,
      hermesStatus: "degraded",
      lastNotification: "ntfy/sent",
      source: "codex/codex-hook",
      lastSeen: "2026-05-21T00:00:00.000Z",
      compact: true
    });

    expect(html).toContain("Operator Status");
    expect(html).toContain("attention");
    expect(html).toContain("PR/CI");
    expect(html).toContain("Hermes");
    expect(html).toContain("ntfy/sent");
    expect(html).not.toContain("Active</dt>");
  });

  it("escapes offline error text", () => {
    const html = renderAgentStatusHtml({
      state: "offline",
      events: 0,
      runs: 0,
      activeRuns: 0,
      failedRuns: 0,
      error: "<offline>"
    });

    expect(html).toContain("&lt;offline&gt;");
  });
});
