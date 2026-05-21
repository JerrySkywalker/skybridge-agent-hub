import { afterEach, describe, expect, it } from "vitest";
import { createEvent } from "@skybridge-agent-hub/event-schema";
import { createServer, type StoredEvent } from "./index.js";

const servers: Awaited<ReturnType<typeof createServer>>[] = [];

afterEach(async () => {
  await Promise.all(servers.map((server) => server.close()));
  servers.length = 0;
});

async function testServer() {
  const server = await createServer({ dataFile: false, logger: false });
  servers.push(server);
  return server;
}

describe("server api", () => {
  it("accepts and lists normalized events", async () => {
    const server = await testServer();
    const event = createEvent({
      type: "run.started",
      source: { platform: "codex", adapter: "codex-hook" },
      correlation: { session_id: "s1", run_id: "r1" },
      payload: { summary: "started" }
    });

    const post = await server.inject({ method: "POST", url: "/v1/events", payload: event });
    expect(post.statusCode).toBe(202);

    const list = await server.inject({ method: "GET", url: "/v1/events" });
    const body = list.json<{ events: StoredEvent[] }>();
    expect(body.events).toHaveLength(1);
    expect(body.events[0]?.type).toBe("run.started");
  });

  it("summarizes runs", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.failed",
        severity: "error",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { session_id: "s1", run_id: "r1" },
        payload: {}
      })
    });

    const response = await server.inject({ method: "GET", url: "/v1/runs" });
    expect(response.json<{ runs: Array<{ status: string }> }>().runs[0]?.status).toBe("failed");
  });
});
