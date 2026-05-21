import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AgentPipelineBar, AgentStatusCard, AgentTimeline } from "./index.js";

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
});
