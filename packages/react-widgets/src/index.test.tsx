import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AgentPipelineBar, AgentStatusCard, AgentTimeline, SelfObservationPanel, summarizeSelfObservation } from "./index.js";

describe("react widgets", () => {
  it("renders the status card shell without a browser runtime", () => {
    const html = renderToStaticMarkup(<AgentStatusCard apiBase="http://127.0.0.1:8787" />);

    expect(html).toContain("SkyBridge Agent Hub");
    expect(html).toContain("Agent Status");
    expect(html).toContain("idle");
  });

  it("renders pipeline and timeline empty states", () => {
    const pipeline = renderToStaticMarkup(<AgentPipelineBar apiBase="http://127.0.0.1:8787" />);
    const timeline = renderToStaticMarkup(<AgentTimeline apiBase="http://127.0.0.1:8787" />);

    expect(pipeline).toContain("Pipeline");
    expect(pipeline).toContain("0 running");
    expect(timeline).toContain("Timeline");
    expect(timeline).toContain("skybridge-timeline");
  });

  it("summarizes self-observation sources and failure state", () => {
    const summary = summarizeSelfObservation(
      [
        {
          run_id: "runner-001-demo",
          source_platform: "skybridge",
          source_adapter: "yolo-runner",
          status: "failed",
          event_count: 3,
          tool_call_count: 1,
          failed_tool_count: 1,
          notification_count: 1,
          first_seen_at: "2026-05-21T00:00:00.000Z",
          last_seen_at: "2026-05-21T00:00:01.000Z",
          last_event_type: "run.failed"
        }
      ],
      [
        {
          schema: "skybridge.agent_event.v1",
          time: "2026-05-21T00:00:00.000Z",
          type: "run.started",
          severity: "info",
          source: { platform: "skybridge", adapter: "yolo-runner" },
          correlation: { run_id: "runner-001-demo" },
          payload: { lifecycle: "goal.claimed" }
        },
        {
          schema: "skybridge.agent_event.v1",
          time: "2026-05-21T00:00:01.000Z",
          type: "notification.requested",
          severity: "warning",
          source: { platform: "skybridge", adapter: "self-observation-smoke" },
          correlation: { run_id: "runner-001-demo" },
          payload: { lifecycle: "smoke.notification.requested" }
        },
        {
          schema: "skybridge.agent_event.v1",
          time: "2026-05-21T00:00:02.000Z",
          type: "tool.completed",
          severity: "info",
          source: { platform: "codex", adapter: "codex-hook" },
          correlation: { run_id: "codex-run" },
          payload: {}
        }
      ]
    );

    expect(summary).toMatchObject({
      status: "attention",
      codex_events: 1,
      runner_events: 1,
      smoke_events: 1,
      notification_events: 1,
      latest_lifecycle: "smoke.notification.requested"
    });
  });

  it("renders the self-observation panel shell", () => {
    const html = renderToStaticMarkup(<SelfObservationPanel apiBase="http://127.0.0.1:8787" />);

    expect(html).toContain("Self-Observation");
    expect(html).toContain("Local Loop");
  });
});
