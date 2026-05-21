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

  it("rejects oversized event payloads before persistence", async () => {
    const server = await testServer();
    const response = await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "message.completed",
        source: { platform: "custom", adapter: "oversized-test" },
        payload: { summary: "x".repeat(140_000) }
      })
    });

    expect(response.statusCode).toBe(400);
    expect(response.json<{ issues: Array<{ code: string }> }>().issues[0]?.code).toBe("too_big");
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

  it("filters events and returns a detailed run view", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.started",
        source: { platform: "skybridge", adapter: "yolo-runner", agent_id: "runner-agent", node_id: "node-1", cwd: "V:\\src\\skybridge-agent-hub" },
        correlation: { session_id: "runner-session", run_id: "runner-001-demo" },
        payload: { goalId: "001", goalFile: "001-demo.md", goal: "Demo goal", branch: "ai/001-demo", lifecycle: "goal.claimed" }
      })
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "tool.completed",
        source: { platform: "skybridge", adapter: "yolo-runner", agent_id: "runner-agent", node_id: "node-1" },
        correlation: { session_id: "runner-session", run_id: "runner-001-demo", tool_call_id: "check-0" },
        payload: { lifecycle: "check.finished", command: "corepack pnpm check", exitCode: 0, message: "check passed" }
      })
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.started",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { session_id: "codex-session", run_id: "codex-run" },
        payload: {}
      })
    });

    const filtered = await server.inject({ method: "GET", url: "/v1/events?run_id=runner-001-demo" });
    expect(filtered.json<{ events: StoredEvent[] }>().events.map((event) => event.source.adapter)).toEqual(["yolo-runner", "yolo-runner"]);

    const detail = await server.inject({ method: "GET", url: "/v1/runs/runner-001-demo" });
    const body = detail.json<{ summary: { title?: string; branch?: string; cwd?: string; goal?: string; tool_call_count: number; active_tool_count: number; latest_message_summary?: string }; events: StoredEvent[] }>();
    expect(detail.statusCode).toBe(200);
    expect(body.summary).toMatchObject({
      title: "001-demo.md",
      branch: "ai/001-demo",
      cwd: "V:\\src\\skybridge-agent-hub",
      goal: "Demo goal",
      tool_call_count: 1,
      active_tool_count: 0,
      latest_message_summary: "check passed"
    });
    expect(body.events).toHaveLength(2);
  });

  it("filters events by source, adapter, type and time window", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:00:00.000Z",
        type: "run.started",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { run_id: "codex-filtered" },
        payload: {}
      })
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T01:00:00.000Z",
        type: "tool.started",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { run_id: "codex-filtered" },
        payload: {}
      })
    });

    const response = await server.inject({
      method: "GET",
      url: "/v1/events?source_platform=codex&source_adapter=codex-hook&type=tool.started&from=2026-05-21T00:30:00.000Z&to=2026-05-21T01:30:00.000Z"
    });

    const events = response.json<{ events: StoredEvent[] }>().events;
    expect(events).toHaveLength(1);
    expect(events[0]?.type).toBe("tool.started");
  });

  it("supports console event filters and clean invalid query responses", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:00:00.000Z",
        type: "approval.requested",
        severity: "warning",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { session_id: "session-filtered", run_id: "run-filtered" },
        payload: {}
      })
    });

    const filtered = await server.inject({
      method: "GET",
      url: "/v1/events?platform=codex&adapter=codex-hook&session_id=session-filtered&severity=warning&limit=1&offset=0"
    });
    expect(filtered.statusCode).toBe(200);
    expect(filtered.json<{ events: StoredEvent[] }>().events).toHaveLength(1);

    const invalidLimit = await server.inject({ method: "GET", url: "/v1/events?limit=not-a-number" });
    expect(invalidLimit.statusCode).toBe(400);
    expect(invalidLimit.json<{ error: string; issues: Array<{ field: string }> }>()).toMatchObject({
      error: "invalid_query",
      issues: [{ field: "limit" }]
    });

    const invalidTime = await server.inject({ method: "GET", url: "/v1/events?from=2026-05-21" });
    expect(invalidTime.statusCode).toBe(400);
    expect(invalidTime.json<{ error: string; issues: Array<{ field: string }> }>().issues[0]?.field).toBe("from");
  });

  it("filters run summaries for dashboard list views", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:00:00.000Z",
        type: "run.started",
        source: { platform: "codex", adapter: "codex-exec-json" },
        correlation: { run_id: "console-run" },
        payload: { branch: "ai/console", goal: "Operator console", lifecycle: "running" }
      })
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:01:00.000Z",
        type: "run.completed",
        source: { platform: "codex", adapter: "codex-exec-json" },
        correlation: { run_id: "console-run" },
        payload: { lifecycle: "completed" }
      })
    });

    const response = await server.inject({
      method: "GET",
      url: "/v1/runs?platform=codex&adapter=codex-exec-json&status=completed&branch=ai/console&goal=console"
    });

    expect(response.statusCode).toBe(200);
    expect(response.json<{ runs: Array<{ run_id: string }> }>().runs.map((run) => run.run_id)).toEqual(["console-run"]);

    const invalid = await server.inject({ method: "GET", url: "/v1/runs?status=stuck" });
    expect(invalid.statusCode).toBe(400);
  });

  it("returns v1 health, dashboard summary and filtered notifications", async () => {
    const previousTopic = process.env.NTFY_TOPIC_URL;
    delete process.env.NTFY_TOPIC_URL;
    try {
      const server = await testServer();
      const health = await server.inject({ method: "GET", url: "/v1/health" });
      expect(health.statusCode).toBe(200);
      expect(health.json<{ service: string }>().service).toBe("skybridge-server");

      await server.inject({
        method: "POST",
        url: "/v1/events",
        payload: createEvent({
          type: "run.failed",
          severity: "error",
          source: { platform: "skybridge", adapter: "yolo-runner" },
          correlation: { run_id: "attention-run" },
          payload: {}
        })
      });
      await waitForNotifications(server);

      const notifications = await server.inject({ method: "GET", url: "/v1/notifications?status=skipped&provider=placeholder" });
      expect(notifications.statusCode).toBe(200);
      expect(notifications.json<{ notifications: StoredNotification[] }>().notifications[0]).toMatchObject({
        provider: "placeholder",
        status: "skipped",
        category: "run",
        severity: "error"
      });

      const summary = await server.inject({ method: "GET", url: "/v1/summary" });
      expect(summary.json<{ totals: { failed_runs: number; attention_items: number }; sources: Array<{ adapter: string }> }>()).toMatchObject({
        totals: { failed_runs: 1, attention_items: 2 },
        sources: [{ adapter: "yolo-runner" }]
      });
    } finally {
      if (previousTopic === undefined) delete process.env.NTFY_TOPIC_URL;
      else process.env.NTFY_TOPIC_URL = previousTopic;
    }
  });

  it("exposes notification provider matrix and routing rules without secrets", async () => {
    const server = await testServer();
    const providers = await server.inject({ method: "GET", url: "/v1/notifications/providers" });
    expect(providers.statusCode).toBe(200);
    expect(providers.json<{ providers: Array<{ provider: string; status: string; credential_values_exposed: boolean }> }>().providers).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ provider: "ntfy", status: "skipped", credential_values_exposed: false }),
        expect.objectContaining({ provider: "gotify", status: "skipped", credential_values_exposed: false })
      ])
    );

    const rules = await server.inject({ method: "GET", url: "/v1/notifications/rules" });
    expect(rules.statusCode).toBe(200);
    expect(rules.json<{ rules: Array<{ event_type_patterns: string[]; dedupe: boolean }> }>().rules[0]).toMatchObject({
      event_type_patterns: expect.arrayContaining(["run.failed", "approval.requested"]),
      dedupe: true
    });
  });

  it("exposes source capability metadata", async () => {
    const server = await testServer();
    const response = await server.inject({ method: "GET", url: "/v1/sources" });
    expect(response.statusCode).toBe(200);
    expect(response.json<{ sources: Array<{ platform: string; adapters: string[] }> }>().sources).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ platform: "codex", adapters: expect.arrayContaining(["codex-hook"]) }),
        expect.objectContaining({ platform: "opencode", adapters: expect.arrayContaining(["opencode-plugin"]) }),
        expect.objectContaining({ platform: "hermes", adapters: expect.arrayContaining(["hermes-api"]) })
      ])
    );
  });

  it("summarizes remote node heartbeat events without command execution", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:00:00.000Z",
        type: "node.heartbeat",
        source: { platform: "skybridge", adapter: "sidecar", node_id: "node-local-1" },
        correlation: { session_id: "node-local-1" },
        payload: {
          node_id: "node-local-1",
          host: "devbox",
          labels: ["local", "sidecar"],
          capabilities: ["event-forwarding", "heartbeat"],
          sidecar_version: "0.1.0"
        }
      })
    });

    const response = await server.inject({ method: "GET", url: "/v1/nodes" });
    expect(response.statusCode).toBe(200);
    expect(response.json<{ nodes: Array<{ node_id: string; status: string; capabilities: string[] }> }>().nodes[0]).toMatchObject({
      node_id: "node-local-1",
      status: "stale",
      capabilities: ["event-forwarding", "heartbeat"]
    });
  });

  it("supports approval queue listing and safe local resolution", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "approval.requested",
        severity: "warning",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { run_id: "approval-run" },
        payload: { approval_id: "approval-1", title: "Edit file" }
      })
    });

    const pending = await server.inject({ method: "GET", url: "/v1/approvals" });
    expect(pending.json<{ approvals: Array<{ approval_id: string; status: string }> }>().approvals[0]).toMatchObject({
      approval_id: "approval-1",
      status: "pending"
    });

    const resolved = await server.inject({
      method: "POST",
      url: "/v1/approvals/approval-1/resolve",
      payload: { decision: "denied", actor: "operator", reason: "safe test" }
    });
    expect(resolved.statusCode).toBe(202);

    const detail = await server.inject({ method: "GET", url: "/v1/approvals/approval-1" });
    expect(detail.json<{ approval: { status: string } }>().approval.status).toBe("denied");
  });

  it("returns operational metrics", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.failed",
        severity: "error",
        source: { platform: "hermes", adapter: "hermes-api" },
        correlation: { run_id: "metrics-run" },
        payload: {}
      })
    });

    const response = await server.inject({ method: "GET", url: "/v1/metrics" });
    expect(response.statusCode).toBe(200);
    expect(response.json<{ total_events: number; runs_by_status: Record<string, number>; runs_by_source: Record<string, number> }>()).toMatchObject({
      total_events: 1,
      runs_by_status: { failed: 1 },
      runs_by_source: { hermes: 1 }
    });
  });

  it("returns a safe derived audit trail without raw payloads", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "approval.requested",
        severity: "warning",
        source: { platform: "opencode", adapter: "opencode-plugin", agent_id: "opencode-local" },
        correlation: { run_id: "audit-run" },
        payload: { approval_id: "approval-audit-1", title: "Edit file", prompt: "should stay out of audit response" }
      })
    });
    await server.inject({
      method: "POST",
      url: "/v1/approvals/approval-audit-1/resolve",
      payload: { decision: "denied", actor: "operator", reason: "safe audit test" }
    });

    const response = await server.inject({ method: "GET", url: "/v1/audit" });
    expect(response.statusCode).toBe(200);
    const audit = response.json<{ audit: Array<{ action: string; actor: string; source_adapter: string; safety_decision: string; raw_payload_included: boolean }> }>().audit;
    expect(audit).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          action: "approval.denied",
          actor: "operator",
          source_adapter: "skybridge/approval-api",
          safety_decision: "operator_denied",
          raw_payload_included: false
        }),
        expect.objectContaining({
          action: "approval.requested",
          source_adapter: "opencode/opencode-plugin",
          safety_decision: "approval_required_remote_execution_disabled",
          raw_payload_included: false
        })
      ])
    );
    expect(JSON.stringify(audit)).not.toContain("should stay out");
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
