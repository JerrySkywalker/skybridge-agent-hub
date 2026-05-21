import { describe, expect, it } from "vitest";
import { createEvent } from "@skybridge-agent-hub/event-schema";
import { createSidecar, resolveNodeIdentity } from "./index.js";

describe("sidecar node foundation", () => {
  it("resolves local node identity with safe defaults", () => {
    const identity = resolveNodeIdentity({ host: "Dev Box", version: "0.9.0" });
    expect(identity).toMatchObject({
      node_id: "local-dev-box",
      host: "Dev Box",
      labels: ["local", "sidecar"],
      capabilities: ["event-forwarding", "heartbeat", "spool"],
      sidecar_version: "0.9.0"
    });
  });

  it("returns health and spools failed event forwarding safely", async () => {
    const app = await createSidecar({ cloudUrl: "http://127.0.0.1:1", nodeId: "node-test", host: "test", logger: false });
    try {
      const health = await app.inject({ method: "GET", url: "/health" });
      expect(health.statusCode).toBe(200);
      expect(health.json<{ node: { node_id: string }; remote_control: { enabled: boolean } }>()).toMatchObject({
        node: { node_id: "node-test" },
        remote_control: { enabled: false }
      });

      const event = createEvent({
        type: "node.heartbeat",
        source: { platform: "skybridge", adapter: "sidecar", node_id: "node-test" },
        correlation: { session_id: "node-test" },
        payload: { node_id: "node-test" }
      });
      const forwarded = await app.inject({ method: "POST", url: "/v1/local/events", payload: event });
      expect(forwarded.statusCode).toBe(202);
      expect(forwarded.json<{ ok: boolean; spooled: boolean }>()).toMatchObject({ ok: false, spooled: true });
    } finally {
      await app.close();
    }
  });
});
