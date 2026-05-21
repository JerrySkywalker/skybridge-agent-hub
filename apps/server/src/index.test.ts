import { afterEach, describe, expect, it } from "vitest";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createEvent } from "@skybridge-agent-hub/event-schema";
import { createServer, type StoredEvent, type StoredNotification } from "./index.js";

const servers: Awaited<ReturnType<typeof createServer>>[] = [];
const tempDirs: string[] = [];

afterEach(async () => {
  await Promise.all(servers.map((server) => server.close()));
  servers.length = 0;
  await Promise.all(tempDirs.map((dir) => rm(dir, { recursive: true, force: true })));
  tempDirs.length = 0;
});

async function testServer() {
  const server = await createServer({ dataFile: false, logger: false });
  servers.push(server);
  return server;
}

async function tempDir() {
  const dir = await mkdtemp(join(tmpdir(), "skybridge-server-"));
  tempDirs.push(dir);
  return dir;
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

  it("returns 400 with validation details for invalid event payloads", async () => {
    const server = await testServer();

    const response = await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: {
        schema: "skybridge.agent_event.v1",
        time: "not-a-date",
        type: "unknown.event",
        source: { platform: "codex", adapter: "codex-hook" },
        payload: {}
      }
    });

    const body = response.json<{ ok: boolean; error: string; issues: Array<{ path: string; message: string }> }>();
    expect(response.statusCode).toBe(400);
    expect(body).toMatchObject({ ok: false, error: "invalid_event" });
    expect(body.issues.map((issue) => issue.path)).toEqual(expect.arrayContaining(["time", "type"]));

    const list = await server.inject({ method: "GET", url: "/v1/events" });
    expect(list.json<{ events: StoredEvent[] }>().events).toHaveLength(0);
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

  it("persists events and notifications to SQLite across server restarts", async () => {
    const dir = await tempDir();
    const dbFile = join(dir, "skybridge.sqlite");
    const first = await createServer({ dbFile, logger: false, jsonMigrationFile: false });
    servers.push(first);

    await first.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.completed",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { session_id: "s1", run_id: "persisted-run" },
        payload: { summary: "done" }
      })
    });
    await first.inject({
      method: "POST",
      url: "/v1/notifications/send",
      payload: { title: "Saved notification", body: "SQLite should retain this" }
    });
    await first.close();
    servers.pop();

    const second = await createServer({ dbFile, logger: false, jsonMigrationFile: false });
    servers.push(second);
    const events = (await second.inject({ method: "GET", url: "/v1/events" })).json<{ events: StoredEvent[] }>().events;
    const notifications = (await second.inject({ method: "GET", url: "/v1/notifications" })).json<{ notifications: StoredNotification[] }>().notifications;

    expect(events.map((event) => event.correlation?.run_id)).toContain("persisted-run");
    expect(notifications.map((notification) => notification.message.title)).toContain("Saved notification");
  });

  it("migrates an existing local JSON MVP store into SQLite", async () => {
    const dir = await tempDir();
    const legacyJsonFile = join(dir, "skybridge-store.json");
    const dbFile = join(dir, "skybridge.sqlite");
    const legacyEvent: StoredEvent = {
      ...createEvent({
        type: "run.started",
        source: { platform: "skybridge", adapter: "legacy-json" },
        correlation: { run_id: "legacy-run" },
        payload: { source: "json" }
      }),
      id: "legacy-event-1",
      receivedAt: "2026-05-21T00:00:00.000Z"
    };
    await writeFile(legacyJsonFile, JSON.stringify({ events: [legacyEvent], notifications: [] }), "utf8");

    const server = await createServer({ dbFile, jsonMigrationFile: legacyJsonFile, logger: false });
    servers.push(server);

    const events = (await server.inject({ method: "GET", url: "/v1/events" })).json<{ events: StoredEvent[] }>().events;
    expect(events).toHaveLength(1);
    expect(events[0]?.id).toBe("legacy-event-1");
  });

  it("records notification trigger events as skipped placeholders when ntfy is not configured", async () => {
    const previousTopic = process.env.NTFY_TOPIC_URL;
    delete process.env.NTFY_TOPIC_URL;
    try {
      const server = await testServer();
      await server.inject({
        method: "POST",
        url: "/v1/events",
        payload: createEvent({
          type: "approval.requested",
          severity: "warning",
          source: { platform: "codex", adapter: "codex-hook" },
          correlation: { run_id: "needs-approval" },
          payload: {}
        })
      });

      const notifications = await waitForNotifications(server);
      expect(notifications[0]?.provider).toBe("placeholder");
      expect(notifications[0]?.status).toBe("skipped");
    } finally {
      if (previousTopic === undefined) delete process.env.NTFY_TOPIC_URL;
      else process.env.NTFY_TOPIC_URL = previousTopic;
    }
  });

  it("replays recent events to new SSE clients", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.started",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { run_id: "sse-run" },
        payload: {}
      })
    });
    await server.listen({ port: 0, host: "127.0.0.1" });
    const address = server.server.address();
    if (!address || typeof address === "string") throw new Error("server did not bind to a TCP port");

    const controller = new AbortController();
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/stream`, { signal: controller.signal });
    expect(response.ok).toBe(true);
    const text = await readUntil(response, "sse-run", controller);
    expect(text).toContain("event: connected");
    expect(text).toContain("event: skybridge.event");
    expect(text).toContain("sse-run");
  });
});

async function waitForNotifications(server: Awaited<ReturnType<typeof createServer>>) {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const response = await server.inject({ method: "GET", url: "/v1/notifications" });
    const notifications = response.json<{ notifications: StoredNotification[] }>().notifications;
    if (notifications.length > 0) return notifications;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return [];
}

async function readUntil(response: Response, needle: string, controller: AbortController) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error("SSE response did not expose a readable body");
  const decoder = new TextDecoder();
  let text = "";
  try {
    for (let attempt = 0; attempt < 20; attempt += 1) {
      const { value } = await reader.read();
      text += decoder.decode(value, { stream: true });
      if (text.includes(needle)) return text;
    }
    return text;
  } finally {
    controller.abort();
    reader.releaseLock();
  }
}
