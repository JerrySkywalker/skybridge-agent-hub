import { afterEach, describe, expect, it, vi } from "vitest";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createEvent } from "@skybridge-agent-hub/event-schema";
import {
  createServer,
  type StoredAuditRecord,
  type StoredEvent,
  type StoredNotification,
} from "./index.js";

const servers: Awaited<ReturnType<typeof createServer>>[] = [];
const tempDirs: string[] = [];

afterEach(async () => {
  vi.restoreAllMocks();
  await Promise.all(servers.map((server) => server.close()));
  servers.length = 0;
  await Promise.all(
    tempDirs.map((dir) => rm(dir, { recursive: true, force: true })),
  );
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

async function withWorkerToken<T>(token: string | undefined, fn: () => Promise<T>): Promise<T> {
  const previousToken = process.env.SKYBRIDGE_WORKER_TOKEN;
  const previousRequired = process.env.SKYBRIDGE_REQUIRE_WORKER_AUTH;
  const previousFile = process.env.SKYBRIDGE_WORKER_TOKENS_FILE;
  const previousRemoteApiBase = process.env.SKYBRIDGE_REMOTE_API_BASE;
  try {
    if (token === undefined) delete process.env.SKYBRIDGE_WORKER_TOKEN;
    else process.env.SKYBRIDGE_WORKER_TOKEN = token;
    delete process.env.SKYBRIDGE_WORKER_TOKENS_FILE;
    delete process.env.SKYBRIDGE_REQUIRE_WORKER_AUTH;
    delete process.env.SKYBRIDGE_REMOTE_API_BASE;
    return await fn();
  } finally {
    if (previousToken === undefined) delete process.env.SKYBRIDGE_WORKER_TOKEN;
    else process.env.SKYBRIDGE_WORKER_TOKEN = previousToken;
    if (previousRequired === undefined) delete process.env.SKYBRIDGE_REQUIRE_WORKER_AUTH;
    else process.env.SKYBRIDGE_REQUIRE_WORKER_AUTH = previousRequired;
    if (previousFile === undefined) delete process.env.SKYBRIDGE_WORKER_TOKENS_FILE;
    else process.env.SKYBRIDGE_WORKER_TOKENS_FILE = previousFile;
    if (previousRemoteApiBase === undefined) delete process.env.SKYBRIDGE_REMOTE_API_BASE;
    else process.env.SKYBRIDGE_REMOTE_API_BASE = previousRemoteApiBase;
  }
}

async function withHermesConfig<T>(
  config: { apiBase?: string; apiKey?: string },
  fn: () => Promise<T>,
): Promise<T> {
  const previousBase = process.env.HERMES_API_BASE;
  const previousKey = process.env.HERMES_API_KEY;
  const previousKeyFile = process.env.HERMES_API_KEY_FILE;
  try {
    if (config.apiBase === undefined) delete process.env.HERMES_API_BASE;
    else process.env.HERMES_API_BASE = config.apiBase;
    if (config.apiKey === undefined) delete process.env.HERMES_API_KEY;
    else process.env.HERMES_API_KEY = config.apiKey;
    delete process.env.HERMES_API_KEY_FILE;
    return await fn();
  } finally {
    if (previousBase === undefined) delete process.env.HERMES_API_BASE;
    else process.env.HERMES_API_BASE = previousBase;
    if (previousKey === undefined) delete process.env.HERMES_API_KEY;
    else process.env.HERMES_API_KEY = previousKey;
    if (previousKeyFile === undefined) delete process.env.HERMES_API_KEY_FILE;
    else process.env.HERMES_API_KEY_FILE = previousKeyFile;
  }
}

describe("server api", () => {
  it("accepts and lists normalized events", async () => {
    const server = await testServer();
    const event = createEvent({
      type: "run.started",
      source: { platform: "codex", adapter: "codex-hook" },
      correlation: { session_id: "s1", run_id: "r1" },
      payload: { summary: "started" },
    });

    const post = await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: event,
    });
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
        payload: {},
      },
    });

    const body = response.json<{
      ok: boolean;
      error: string;
      issues: Array<{ path: string; message: string }>;
    }>();
    expect(response.statusCode).toBe(400);
    expect(body).toMatchObject({ ok: false, error: "invalid_event" });
    expect(body.issues.map((issue) => issue.path)).toEqual(
      expect.arrayContaining(["time", "type"]),
    );

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
        payload: { summary: "x".repeat(140_000) },
      }),
    });

    expect(response.statusCode).toBe(400);
    expect(
      response.json<{ issues: Array<{ code: string }> }>().issues[0]?.code,
    ).toBe("too_big");
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
        payload: {},
      }),
    });

    const response = await server.inject({ method: "GET", url: "/v1/runs" });
    expect(
      response.json<{ runs: Array<{ status: string }> }>().runs[0]?.status,
    ).toBe("failed");
  });

  it("filters events and returns a detailed run view", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.started",
        source: {
          platform: "skybridge",
          adapter: "yolo-runner",
          agent_id: "runner-agent",
          node_id: "node-1",
          cwd: "V:\\src\\skybridge-agent-hub",
        },
        correlation: {
          session_id: "runner-session",
          run_id: "runner-001-demo",
        },
        payload: {
          goalId: "001",
          goalFile: "001-demo.md",
          goal: "Demo goal",
          branch: "ai/001-demo",
          lifecycle: "goal.claimed",
        },
      }),
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "tool.completed",
        source: {
          platform: "skybridge",
          adapter: "yolo-runner",
          agent_id: "runner-agent",
          node_id: "node-1",
        },
        correlation: {
          session_id: "runner-session",
          run_id: "runner-001-demo",
          tool_call_id: "check-0",
        },
        payload: {
          lifecycle: "check.finished",
          command: "corepack pnpm check",
          exitCode: 0,
          message: "check passed",
        },
      }),
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.started",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { session_id: "codex-session", run_id: "codex-run" },
        payload: {},
      }),
    });

    const filtered = await server.inject({
      method: "GET",
      url: "/v1/events?run_id=runner-001-demo",
    });
    expect(
      filtered
        .json<{ events: StoredEvent[] }>()
        .events.map((event) => event.source.adapter),
    ).toEqual(["yolo-runner", "yolo-runner"]);

    const detail = await server.inject({
      method: "GET",
      url: "/v1/runs/runner-001-demo",
    });
    const body = detail.json<{
      summary: {
        title?: string;
        branch?: string;
        cwd?: string;
        goal?: string;
        tool_call_count: number;
        active_tool_count: number;
        latest_message_summary?: string;
      };
      events: StoredEvent[];
    }>();
    expect(detail.statusCode).toBe(200);
    expect(body.summary).toMatchObject({
      title: "001-demo.md",
      branch: "ai/001-demo",
      cwd: "V:\\src\\skybridge-agent-hub",
      goal: "Demo goal",
      tool_call_count: 1,
      active_tool_count: 0,
      latest_message_summary: "check passed",
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
        payload: {},
      }),
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T01:00:00.000Z",
        type: "tool.started",
        source: { platform: "codex", adapter: "codex-hook" },
        correlation: { run_id: "codex-filtered" },
        payload: {},
      }),
    });

    const response = await server.inject({
      method: "GET",
      url: "/v1/events?source_platform=codex&source_adapter=codex-hook&type=tool.started&from=2026-05-21T00:30:00.000Z&to=2026-05-21T01:30:00.000Z",
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
        payload: {},
      }),
    });

    const filtered = await server.inject({
      method: "GET",
      url: "/v1/events?platform=codex&adapter=codex-hook&session_id=session-filtered&severity=warning&limit=1&offset=0",
    });
    expect(filtered.statusCode).toBe(200);
    expect(filtered.json<{ events: StoredEvent[] }>().events).toHaveLength(1);

    const invalidLimit = await server.inject({
      method: "GET",
      url: "/v1/events?limit=not-a-number",
    });
    expect(invalidLimit.statusCode).toBe(400);
    expect(
      invalidLimit.json<{ error: string; issues: Array<{ field: string }> }>(),
    ).toMatchObject({
      error: "invalid_query",
      issues: [{ field: "limit" }],
    });

    const invalidTime = await server.inject({
      method: "GET",
      url: "/v1/events?from=2026-05-21",
    });
    expect(invalidTime.statusCode).toBe(400);
    expect(
      invalidTime.json<{ error: string; issues: Array<{ field: string }> }>()
        .issues[0]?.field,
    ).toBe("from");
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
        payload: {
          branch: "ai/console",
          goal: "Operator console",
          lifecycle: "running",
        },
      }),
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:01:00.000Z",
        type: "run.completed",
        source: { platform: "codex", adapter: "codex-exec-json" },
        correlation: { run_id: "console-run" },
        payload: { lifecycle: "completed" },
      }),
    });

    const response = await server.inject({
      method: "GET",
      url: "/v1/runs?platform=codex&adapter=codex-exec-json&status=completed&branch=ai/console&goal=console",
    });

    expect(response.statusCode).toBe(200);
    expect(
      response
        .json<{ runs: Array<{ run_id: string }> }>()
        .runs.map((run) => run.run_id),
    ).toEqual(["console-run"]);

    const invalid = await server.inject({
      method: "GET",
      url: "/v1/runs?status=stuck",
    });
    expect(invalid.statusCode).toBe(400);
  });

  it("returns v1 health, dashboard summary and filtered notifications", async () => {
    const previousTopic = process.env.NTFY_TOPIC_URL;
    const previousCommit = process.env.SKYBRIDGE_COMMIT_SHA;
    const previousImageTag = process.env.SKYBRIDGE_IMAGE_TAG;
    const previousImageRef = process.env.SKYBRIDGE_IMAGE_REF;
    const previousBuildTime = process.env.SKYBRIDGE_BUILD_TIME;
    const previousServerVersion = process.env.SKYBRIDGE_SERVER_VERSION;
    delete process.env.NTFY_TOPIC_URL;
    process.env.SKYBRIDGE_COMMIT_SHA = "abc123";
    process.env.SKYBRIDGE_IMAGE_TAG = "sha-abc123";
    process.env.SKYBRIDGE_IMAGE_REF = "ghcr.io/example/skybridge-agent-hub-server:sha-abc123";
    process.env.SKYBRIDGE_BUILD_TIME = "2026-06-17T00:00:00Z";
    process.env.SKYBRIDGE_SERVER_VERSION = "v2.6.0-test";
    try {
      const server = await testServer();
      const health = await server.inject({ method: "GET", url: "/v1/health" });
      expect(health.statusCode).toBe(200);
      expect(
        health.json<{
          service: string;
          commit_sha: string;
          image_tag: string;
          image_ref: string;
          build_time: string;
          server_version: string;
          route_set_version: string;
          token_printed: boolean;
        }>(),
      ).toMatchObject({
        service: "skybridge-server",
        commit_sha: "abc123",
        image_tag: "sha-abc123",
        image_ref: "ghcr.io/example/skybridge-agent-hub-server:sha-abc123",
        build_time: "2026-06-17T00:00:00Z",
        server_version: "v2.6.0-test",
        token_printed: false,
      });
      expect(health.json<{ route_set_version: string }>().route_set_version).toContain("goal-301");

      const version = await server.inject({ method: "GET", url: "/v1/version" });
      expect(version.statusCode).toBe(200);
      expect(
        version.json<{
          schema: string;
          service: string;
          commit_sha: string;
          image_tag: string;
          image_ref: string;
          server_version: string;
          token_printed: boolean;
        }>(),
      ).toMatchObject({
        schema: "skybridge.server_version.v1",
        service: "skybridge-server",
        commit_sha: "abc123",
        image_tag: "sha-abc123",
        image_ref: "ghcr.io/example/skybridge-agent-hub-server:sha-abc123",
        server_version: "v2.6.0-test",
        token_printed: false,
      });

      await server.inject({
        method: "POST",
        url: "/v1/events",
        payload: createEvent({
          type: "run.failed",
          severity: "error",
          source: { platform: "skybridge", adapter: "yolo-runner" },
          correlation: { run_id: "attention-run" },
          payload: {},
        }),
      });
      await waitForNotifications(server);

      const notifications = await server.inject({
        method: "GET",
        url: "/v1/notifications?status=skipped&provider=placeholder",
      });
      expect(notifications.statusCode).toBe(200);
      expect(
        notifications.json<{ notifications: StoredNotification[] }>()
          .notifications[0],
      ).toMatchObject({
        provider: "placeholder",
        status: "skipped",
        category: "run",
        severity: "error",
      });

      const summary = await server.inject({
        method: "GET",
        url: "/v1/summary",
      });
      expect(
        summary.json<{
          totals: { failed_runs: number; attention_items: number };
          sources: Array<{ adapter: string }>;
        }>(),
      ).toMatchObject({
        totals: { failed_runs: 1, attention_items: 2 },
        sources: [{ adapter: "yolo-runner" }],
      });
    } finally {
      if (previousTopic === undefined) delete process.env.NTFY_TOPIC_URL;
      else process.env.NTFY_TOPIC_URL = previousTopic;
      if (previousCommit === undefined) delete process.env.SKYBRIDGE_COMMIT_SHA;
      else process.env.SKYBRIDGE_COMMIT_SHA = previousCommit;
      if (previousImageTag === undefined) delete process.env.SKYBRIDGE_IMAGE_TAG;
      else process.env.SKYBRIDGE_IMAGE_TAG = previousImageTag;
      if (previousImageRef === undefined) delete process.env.SKYBRIDGE_IMAGE_REF;
      else process.env.SKYBRIDGE_IMAGE_REF = previousImageRef;
      if (previousBuildTime === undefined) delete process.env.SKYBRIDGE_BUILD_TIME;
      else process.env.SKYBRIDGE_BUILD_TIME = previousBuildTime;
      if (previousServerVersion === undefined) delete process.env.SKYBRIDGE_SERVER_VERSION;
      else process.env.SKYBRIDGE_SERVER_VERSION = previousServerVersion;
    }
  });

  it("exposes notification provider matrix and routing rules without secrets", async () => {
    const server = await testServer();
    const providers = await server.inject({
      method: "GET",
      url: "/v1/notifications/providers",
    });
    expect(providers.statusCode).toBe(200);
    expect(
      providers.json<{
        providers: Array<{
          provider: string;
          status: string;
          credential_values_exposed: boolean;
        }>;
      }>().providers,
    ).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          provider: "ntfy",
          status: "skipped",
          credential_values_exposed: false,
        }),
        expect.objectContaining({
          provider: "gotify",
          status: "skipped",
          credential_values_exposed: false,
        }),
      ]),
    );

    const rules = await server.inject({
      method: "GET",
      url: "/v1/notifications/rules",
    });
    expect(rules.statusCode).toBe(200);
    expect(
      rules.json<{
        rules: Array<{ event_type_patterns: string[]; dedupe: boolean }>;
      }>().rules[0],
    ).toMatchObject({
      event_type_patterns: expect.arrayContaining([
        "run.failed",
        "approval.requested",
      ]),
      dedupe: true,
    });
  });

  it("exposes manual task providers with mock default and deprecated local-direct Hermes", async () => {
    await withHermesConfig({}, async () => {
      const server = await testServer();
      const response = await server.inject({
        method: "GET",
        url: "/v1/manual-tasks/providers",
      });

      expect(response.statusCode).toBe(200);
      expect(response.body).not.toContain("server-secret");
      expect(
        response.json<{
          default_provider_id: string;
          client_secret_required: boolean;
          providers: Array<{
            provider_id: string;
            status: string;
            deprecated?: boolean;
            preview_only?: boolean;
            hermes_live_call_enabled: boolean;
            raw_request_persisted: boolean;
            raw_response_persisted: boolean;
            token_printed: boolean;
          }>;
        }>(),
      ).toMatchObject({
        default_provider_id: "mock",
        client_secret_required: false,
        providers: expect.arrayContaining([
          expect.objectContaining({
            provider_id: "mock",
            status: "enabled",
            hermes_live_call_enabled: false,
            raw_request_persisted: false,
            raw_response_persisted: false,
            token_printed: false,
          }),
          expect.objectContaining({
            provider_id: "skybridge_server_hermes",
            status: "disabled_missing_server_config",
          }),
          expect.objectContaining({
            provider_id: "hermes_deepseek",
            deprecated: true,
            preview_only: true,
          }),
        ]),
      });
    });
  });

  it("blocks server-mediated Hermes without server config and never executes output", async () => {
    await withHermesConfig({}, async () => {
      const server = await testServer();
      const response = await server.inject({
        method: "POST",
        url: "/v1/manual-tasks/run-next/skybridge-hermes",
        payload: {
          task_id: "manual-server-missing-config",
          input_preview: "command: pwsh Get-ChildItem",
        },
      });

      expect(response.statusCode).toBe(200);
      expect(response.json<{
        provider_id: string;
        status: string;
        live_call_performed: boolean;
        output_executed: boolean;
        remote_execution_enabled: boolean;
        arbitrary_command_enabled: boolean;
        queue_apply_enabled: boolean;
        token_printed: boolean;
      }>()).toMatchObject({
        provider_id: "skybridge_server_hermes",
        status: "blocked",
        live_call_performed: false,
        output_executed: false,
        remote_execution_enabled: false,
        arbitrary_command_enabled: false,
        queue_apply_enabled: false,
        token_printed: false,
      });
    });
  });

  it("calls only Hermes capabilities and responses endpoints for server-mediated manual tasks", async () => {
    await withHermesConfig(
      { apiBase: "https://hermes.example.invalid", apiKey: "server-secret-token" },
      async () => {
        const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(
          async (input, init) => {
            const url = String(input);
            if (url.endsWith("/v1/capabilities")) {
              expect(init?.method).toBe("GET");
              return new Response(JSON.stringify({ status: "ok", model: "hermes-fixture" }), {
                status: 200,
                headers: { "content-type": "application/json" },
              });
            }
            if (url.endsWith("/v1/responses")) {
              expect(init?.method).toBe("POST");
              expect(String(init?.body)).toContain("output_execution_enabled");
              return new Response(JSON.stringify({ output_text: "Safe Hermes answer. token=redacted-by-server" }), {
                status: 200,
                headers: { "content-type": "application/json" },
              });
            }
            throw new Error(`unexpected_url_${url}`);
          },
        );
        const server = await testServer();
        const response = await server.inject({
          method: "POST",
          url: "/v1/manual-tasks/run-next/skybridge-hermes",
          payload: {
            task_id: "manual-server-hermes",
            input_preview: "Summarize the next safe check.",
          },
        });

        expect(response.statusCode).toBe(200);
        expect(fetchMock).toHaveBeenCalledTimes(2);
        expect(fetchMock.mock.calls.map(([url]) => String(url))).toEqual([
          "https://hermes.example.invalid/v1/capabilities",
          "https://hermes.example.invalid/v1/responses",
        ]);
        expect(response.body).not.toContain("server-secret-token");
        expect(response.json<{
          provider_id: string;
          status: string;
          server_mediated_llm_inference_enabled: boolean;
          cloud_hermes_provider_enabled: boolean;
          live_call_performed: boolean;
          output_executed: boolean;
          token_printed: boolean;
        }>()).toMatchObject({
          provider_id: "skybridge_server_hermes",
          status: "succeeded",
          server_mediated_llm_inference_enabled: true,
          cloud_hermes_provider_enabled: true,
          live_call_performed: true,
          output_executed: false,
          token_printed: false,
        });
      },
    );
  });

  it("exposes source capability metadata", async () => {
    const server = await testServer();
    const response = await server.inject({ method: "GET", url: "/v1/sources" });
    expect(response.statusCode).toBe(200);
    expect(
      response.json<{
        sources: Array<{ platform: string; adapters: string[] }>;
      }>().sources,
    ).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          platform: "codex",
          adapters: expect.arrayContaining(["codex-hook"]),
        }),
        expect.objectContaining({
          platform: "opencode",
          adapters: expect.arrayContaining(["opencode-plugin"]),
        }),
        expect.objectContaining({
          platform: "hermes",
          adapters: expect.arrayContaining(["hermes-api"]),
        }),
      ]),
    );
  });

  it("exposes neutral adapter capability registry", async () => {
    const server = await testServer();
    const response = await server.inject({
      method: "GET",
      url: "/v1/adapters",
    });
    expect(response.statusCode).toBe(200);
    expect(
      response.json<{
        adapters: Array<{ id: string; role: string; optional: boolean }>;
      }>().adapters,
    ).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: "rule-based-planner",
          role: "planner",
          optional: true,
        }),
        expect.objectContaining({
          id: "manual-executor",
          role: "executor",
          optional: true,
        }),
        expect.objectContaining({
          id: "github-actions",
          role: "scm_ci_provider",
          optional: true,
        }),
        expect.objectContaining({
          id: "ntfy",
          role: "notification_provider",
          optional: true,
        }),
      ]),
    );

    const planners = await server.inject({
      method: "GET",
      url: "/v1/adapters?role=planner",
    });
    expect(
      planners
        .json<{ adapters: Array<{ role: string }> }>()
        .adapters.every((adapter) => adapter.role === "planner"),
    ).toBe(true);

    const invalid = await server.inject({
      method: "GET",
      url: "/v1/adapters?role=hermes",
    });
    expect(invalid.statusCode).toBe(400);
  });

  it("registers workers, records heartbeats and hides secret-like fields", async () => {
    const server = await testServer();
    const create = await server.inject({
      method: "POST",
      url: "/v1/workers/register",
      payload: {
        worker_id: "worker-local-1",
        name: "Local worker",
        provider: "manual",
        capabilities: ["manual-execution", "tests"],
        token: "must-not-return",
      },
    });
    expect(create.statusCode).toBe(201);

    const heartbeat = await server.inject({
      method: "POST",
      url: "/v1/workers/worker-local-1/heartbeat",
      payload: { status_note: "ready", load: 0.2 },
    });
    expect(heartbeat.statusCode).toBe(200);
    expect(
      heartbeat.json<{ worker: { status: string; last_seen_at?: string } }>()
        .worker,
    ).toMatchObject({ status: "online", last_seen_at: expect.any(String) });

    const list = await server.inject({ method: "GET", url: "/v1/workers" });
    const bodyText = list.body;
    expect(list.statusCode).toBe(200);
    expect(bodyText).not.toContain("must-not-return");
    expect(
      list.json<{ workers: Array<{ worker_id: string; status: string }> }>()
        .workers,
    ).toEqual([
      expect.objectContaining({
        worker_id: "worker-local-1",
        status: "online",
      }),
    ]);
  });

  it("requires bearer token on worker-sensitive routes when worker auth is configured", async () => {
    await withWorkerToken("server-worker-token", async () => {
      const server = await testServer();

      const missing = await server.inject({
        method: "POST",
        url: "/v1/workers/register",
        payload: { worker_id: "auth-worker", name: "Auth worker" },
      });
      expect(missing.statusCode).toBe(401);
      expect(missing.body).not.toContain("server-worker-token");
      expect(missing.json<{ error: string }>().error).toBe("missing_worker_token");

      const wrong = await server.inject({
        method: "POST",
        url: "/v1/workers/register",
        headers: { authorization: "Bearer wrong-token" },
        payload: { worker_id: "auth-worker", name: "Auth worker" },
      });
      expect(wrong.statusCode).toBe(403);
      expect(wrong.body).not.toContain("server-worker-token");
      expect(wrong.json<{ error: string }>().error).toBe("invalid_worker_token");

      const create = await server.inject({
        method: "POST",
        url: "/v1/workers/register",
        headers: { authorization: "Bearer server-worker-token" },
        payload: { worker_id: "auth-worker", name: "Auth worker" },
      });
      expect(create.statusCode).toBe(201);

      const heartbeat = await server.inject({
        method: "POST",
        url: "/v1/workers/auth-worker/heartbeat",
        headers: { authorization: "Bearer server-worker-token" },
        payload: { status_note: "ready" },
      });
      expect(heartbeat.statusCode).toBe(200);
    });
  });

  it("keeps local worker routes no-auth when worker auth is not configured", async () => {
    await withWorkerToken(undefined, async () => {
      const server = await testServer();
      const create = await server.inject({
        method: "POST",
        url: "/v1/workers/register",
        payload: { worker_id: "local-noauth-worker", name: "Local no-auth worker" },
      });
      expect(create.statusCode).toBe(201);
    });
  });

  it("serves Goal 218 worker registration, pairing and heartbeat preview routes without execution", async () => {
    const server = await testServer();

    const register = await server.inject({
      method: "POST",
      url: "/api/workers/register-preview",
      payload: {
        worker_id: "goal-218-worker",
        device_id_hash: "safe-fixture-device",
        display_name: "Goal 218 worker",
        repo: "skybridge-agent-hub",
        branch: "main",
        commit: "test",
        capabilities: ["heartbeat"],
        resource_policy_summary: "safe",
        resident_enabled: false,
        paired: false,
        pairing_state: "pairing_preview",
        pairing_code_hash: "hash-only",
      },
    });
    expect(register.statusCode).toBe(202);
    expect(
      register.json<{ worker: { execution_enabled: boolean; token_printed: boolean } }>().worker,
    ).toMatchObject({
      execution_enabled: false,
      token_printed: false,
    });

    const pairing = await server.inject({
      method: "POST",
      url: "/api/workers/pairing-preview",
      payload: { worker_id: "goal-218-worker", pairing_code_hash: "hash-only" },
    });
    expect(pairing.statusCode).toBe(202);
    expect(
      pairing.json<{
        pairing_preview: {
          remote_execution_enabled: boolean;
          arbitrary_command_enabled: boolean;
        };
      }>().pairing_preview,
    ).toMatchObject({
      remote_execution_enabled: false,
      arbitrary_command_enabled: false,
    });

    const heartbeat = await server.inject({
      method: "POST",
      url: "/api/workers/goal-218-worker/heartbeat-ingest",
      payload: {
        worker_id: "goal-218-worker",
        device_id_hash: "safe-fixture-device",
        repo: "skybridge-agent-hub",
        branch: "main",
        commit: "test",
        resident_enabled: false,
        resource_gate_status: "pass",
        resource_gate_blockers: [],
        active_tasks: 0,
        stale_leases: 0,
        runner_lock: "none",
        open_review_hold: false,
        queue_preview: {
          queued_workunits: 0,
          runnable_workunits: 0,
          would_create_tasks: false,
          would_claim_tasks: false,
          would_execute_tasks: false,
        },
        drain_pause_state: false,
        emergency_stop_preview_state: false,
        timestamp: "2026-06-13T00:00:00.000Z",
      },
    });
    expect(heartbeat.statusCode).toBe(202);
    expect(
      heartbeat.json<{
        heartbeat: {
          execution_enabled: boolean;
          active_tasks: number;
          stale_leases: number;
        };
      }>().heartbeat,
    ).toMatchObject({
      execution_enabled: false,
      active_tasks: 0,
      stale_leases: 0,
    });

    const status = await server.inject({
      method: "GET",
      url: "/api/workers/goal-218-worker/status",
    });
    expect(status.statusCode).toBe(200);
    expect(status.body).toContain("skybridge.worker_identity.v1");
    expect(status.body).toContain("skybridge.worker_connection_state.v1");
  });

  it("rejects unsafe Goal 218 heartbeat ingest payloads", async () => {
    const server = await testServer();
    for (const payload of [
      { raw_logs: "log text" },
      { raw_prompt: "prompt text" },
      { token_printed: true },
      { headers: { Authorization: "Bearer secret-value" } },
      { private_key: "-----BEGIN OPENSSH PRIVATE KEY----- secret" },
    ]) {
      const response = await server.inject({
        method: "POST",
        url: "/api/workers/laptop-zenbookduo/heartbeat-ingest",
        payload,
      });
      expect(response.statusCode).toBe(400);
      expect(
        response.json<{ schema: string; token_printed: boolean }>(),
      ).toMatchObject({
        schema: "skybridge.worker_ingest_rejection.v1",
        token_printed: false,
      });
    }
  });

  it("models Goal 218 approval preview as non-executing and resource-gated", async () => {
    const server = await testServer();
    const create = await server.inject({
      method: "POST",
      url: "/api/operator-approvals/request-preview",
      payload: {
        approval_request_id: "approval-route-test",
        requested_action: "future_start_one_controlled_preview",
        requested_mode: "preview",
        scope: "local",
        workunit_ids: [],
        max_workunits: 0,
        risk: "medium",
        expires_at: "2099-01-01T00:00:00.000Z",
      },
    });
    expect(create.statusCode).toBe(202);
    expect(
      create.json<{
        approval_gate: {
          allowed_to_execute: boolean;
          resource_gate_required: boolean;
        };
      }>().approval_gate,
    ).toMatchObject({
      allowed_to_execute: false,
      resource_gate_required: true,
    });

    const approve = await server.inject({
      method: "POST",
      url: "/api/operator-approvals/approval-route-test/approve-preview",
      payload: { decision_reason: "test preview" },
    });
    expect(approve.statusCode).toBe(200);
    expect(
      approve.json<{
        execution_started: boolean;
        approval_state: {
          execution_enabled: boolean;
          arbitrary_command_enabled: boolean;
        };
      }>(),
    ).toMatchObject({
      execution_started: false,
      approval_state: {
        execution_enabled: false,
        arbitrary_command_enabled: false,
      },
    });

    const shell = await server.inject({
      method: "POST",
      url: "/api/operator-approvals/request-preview",
      payload: {
        approval_request_id: "approval-shell-test",
        requested_action: "future",
        requested_mode: "preview",
        scope: "local",
        workunit_ids: [],
        max_workunits: 0,
        risk: "medium",
        expires_at: "2099-01-01T00:00:00.000Z",
        shell_command: "echo unsafe",
      },
    });
    expect(shell.statusCode).toBe(400);
  });

  it("guards queue control preview and safe action apply", async () => {
    await withWorkerToken("queue-control-token", async () => {
      const server = await testServer();
      await server.inject({
        method: "POST",
        url: "/v1/projects",
        payload: { project_id: "skybridge-agent-hub", name: "SkyBridge Agent Hub" },
      });
      const createCampaign = await server.inject({
        method: "POST",
        url: "/v1/campaigns",
        headers: { authorization: "Bearer queue-control-token" },
        payload: {
          campaign_id: "dev-queue-189-200",
          project_id: "skybridge-agent-hub",
          title: "Dev Queue 189-200",
          goals: [
            { goal_id: "super-192-dashboard-safe-actions", title: "Dashboard Safe Actions", order: 1 },
          ],
        },
      });
      expect(createCampaign.statusCode).toBe(201);

      const matrix = await server.inject({
        method: "GET",
        url: "/v1/campaigns/dev-queue-189-200/control/matrix",
      });
      expect(matrix.statusCode).toBe(200);
      expect(matrix.json<{ action_matrix: Array<{ action: string; apply_allowed: boolean }> }>().action_matrix)
        .toEqual(expect.arrayContaining([expect.objectContaining({ action: "start_one_apply", apply_allowed: false })]));

      const initialPreview = await server.inject({
        method: "POST",
        url: "/v1/campaigns/dev-queue-189-200/control/preview",
        payload: { action: "start_one_preview", source: "web" },
      });
      const initialBody = initialPreview.json<{ state_hash: string; blockers: string[] }>();
      expect(initialPreview.statusCode).toBe(409);
      expect(initialBody.blockers).toContain("target_revision_required");

      const preview = await server.inject({
        method: "POST",
        url: "/v1/campaigns/dev-queue-189-200/control/preview",
        payload: { action: "start_one_preview", source: "web", target_revision: initialBody.state_hash },
      });
      expect(preview.statusCode).toBe(200);
      expect(preview.json<{ ok: boolean; token_printed: boolean }>()).toMatchObject({ ok: true, token_printed: false });

      const forbiddenApply = await server.inject({
        method: "POST",
        url: "/v1/campaigns/dev-queue-189-200/control/apply",
        headers: { authorization: "Bearer queue-control-token" },
        payload: { action: "start_one_apply", source: "web", target_revision: initialBody.state_hash, reason: "must fail" },
      });
      expect(forbiddenApply.statusCode).toBe(403);
      expect(forbiddenApply.json<{ blockers: string[] }>().blockers).toEqual(expect.arrayContaining(["apply_forbidden_in_goal_192"]));

      const safeApply = await server.inject({
        method: "POST",
        url: "/v1/campaigns/dev-queue-189-200/control/apply",
        headers: { authorization: "Bearer queue-control-token" },
        payload: { action: "safe_pause", source: "web", target_revision: initialBody.state_hash, reason: "operator smoke reason" },
      });
      const safeBody = safeApply.json<{ ok: boolean; audit_event_id: string; token_printed: boolean }>();
      expect(safeApply.statusCode).toBe(200);
      expect(safeBody.ok).toBe(true);
      expect(safeBody.audit_event_id).toMatch(/^audit_queue_control_/);
      expect(safeBody.token_printed).toBe(false);
    });
  });

  it("isolates local no-auth worker tests from developer worker env vars", async () => {
    const previousToken = process.env.SKYBRIDGE_WORKER_TOKEN;
    const previousTokensFile = process.env.SKYBRIDGE_WORKER_TOKENS_FILE;
    const previousRemoteApiBase = process.env.SKYBRIDGE_REMOTE_API_BASE;
    process.env.SKYBRIDGE_WORKER_TOKEN = "developer-shell-token";
    process.env.SKYBRIDGE_WORKER_TOKENS_FILE = "developer-shell-token-file";
    process.env.SKYBRIDGE_REMOTE_API_BASE = "https://skybridge.example.invalid";
    try {
      await withWorkerToken(undefined, async () => {
        const server = await testServer();
        const create = await server.inject({
          method: "POST",
          url: "/v1/workers/register",
          payload: { worker_id: "isolated-noauth-worker", name: "Isolated no-auth worker" },
        });
        expect(create.statusCode).toBe(201);
        expect(create.body).not.toContain("developer-shell-token");
      });
    } finally {
      if (previousToken === undefined) delete process.env.SKYBRIDGE_WORKER_TOKEN;
      else process.env.SKYBRIDGE_WORKER_TOKEN = previousToken;
      if (previousTokensFile === undefined) delete process.env.SKYBRIDGE_WORKER_TOKENS_FILE;
      else process.env.SKYBRIDGE_WORKER_TOKENS_FILE = previousTokensFile;
      if (previousRemoteApiBase === undefined) delete process.env.SKYBRIDGE_REMOTE_API_BASE;
      else process.env.SKYBRIDGE_REMOTE_API_BASE = previousRemoteApiBase;
    }
  });

  it("creates projects and master goals with structured invalid responses", async () => {
    const server = await testServer();
    const project = await server.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "proj-core", name: "Core project" },
    });
    expect(project.statusCode).toBe(201);

    const goal = await server.inject({
      method: "POST",
      url: "/v1/projects/proj-core/goals",
      payload: { goal_id: "goal-core", title: "Build core" },
    });
    expect(goal.statusCode).toBe(201);

    const goals = await server.inject({
      method: "GET",
      url: "/v1/projects/proj-core/goals",
    });
    expect(
      goals.json<{ goals: Array<{ goal_id: string }> }>().goals,
    ).toEqual([expect.objectContaining({ goal_id: "goal-core" })]);

    const update = await server.inject({
      method: "PATCH",
      url: "/v1/goals/goal-core",
      payload: { status: "blocked", blocked_reason: "operator review" },
    });
    expect(update.statusCode).toBe(200);
    expect(update.json<{ goal: { status: string } }>().goal.status).toBe(
      "blocked",
    );

    const missing = await server.inject({
      method: "GET",
      url: "/v1/projects/missing",
    });
    expect(missing.statusCode).toBe(404);
    expect(missing.json<{ error: string }>().error).toBe("project_not_found");

    const invalid = await server.inject({
      method: "PATCH",
      url: "/v1/goals/goal-core",
      payload: { status: "unknown" },
    });
    expect(invalid.statusCode).toBe(400);
  });

  it("updates project control state for worker loops", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "proj-control", name: "Control project" },
    });

    const initial = await server.inject({
      method: "GET",
      url: "/v1/projects/proj-control/control",
    });
    expect(initial.statusCode).toBe(200);
    expect(initial.json<{ control_state: { state: string } }>().control_state.state).toBe("stopped");

    const update = await server.inject({
      method: "PATCH",
      url: "/v1/projects/proj-control/control",
      payload: {
        state: "running",
        stop_requested: false,
        max_tasks: 2,
        current_worker_id: "worker-control",
        current_task_id: "task-control",
        last_heartbeat: "2026-05-26T00:00:00.000Z",
      },
    });
    expect(update.statusCode).toBe(200);
    expect(
      update.json<{
        control_state: {
          state: string;
          max_tasks: number;
          current_worker_id: string;
          current_task_id: string;
          last_heartbeat: string;
        };
      }>().control_state,
    ).toMatchObject({
      state: "running",
      max_tasks: 2,
      current_worker_id: "worker-control",
      current_task_id: "task-control",
      last_heartbeat: "2026-05-26T00:00:00.000Z",
    });

    const invalid = await server.inject({
      method: "PATCH",
      url: "/v1/projects/proj-control/control",
      payload: { state: "launching" },
    });
    expect(invalid.statusCode).toBe(400);
  });

  it("validates goal registry lifecycle metadata", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "goal-registry", name: "Goal Registry" },
    });

    const create = await server.inject({
      method: "POST",
      url: "/v1/projects/goal-registry/goals",
      payload: {
        goal_id: "goal-registry-1",
        title: "Build registry",
        status: "ready",
        source: "smoke",
        priority: "high",
        risk: "medium",
        acceptance_criteria: ["Goal can be imported."],
        evidence_requirements: ["Smoke test output."],
        dedupe_key: "goal-registry/build",
        planner_metadata: {
          adapter: "rule-based",
          decision: "continue",
          reason: "fixture",
          allowed_paths: ["docs/"],
          blocked_paths: [],
          validation: ["just check"],
          stop_criteria_status: [],
          created_at: "2026-05-26T00:00:00.000Z",
        },
        model_backend_metadata: {
          adapter: "hermes",
          backend: "fixture",
          model: "placeholder",
          token: "must-not-return",
        },
      },
    });
    expect(create.statusCode).toBe(201);
    const created = create.json<{
      goal: {
        status: string;
        priority: string;
        risk: string;
        acceptance_criteria: string[];
        model_backend_metadata: { audit_only: boolean; secrets_included: boolean };
      };
    }>().goal;
    expect(created).toMatchObject({
      status: "ready",
      priority: "high",
      risk: "medium",
      acceptance_criteria: ["Goal can be imported."],
      model_backend_metadata: { audit_only: true, secrets_included: false },
    });
    expect(create.body).not.toContain("must-not-return");

    const blockedWithoutReason = await server.inject({
      method: "PATCH",
      url: "/v1/goals/goal-registry-1",
      payload: { status: "blocked" },
    });
    expect(blockedWithoutReason.statusCode).toBe(400);

    const completedWithoutEvidence = await server.inject({
      method: "PATCH",
      url: "/v1/goals/goal-registry-1",
      payload: { status: "completed" },
    });
    expect(completedWithoutEvidence.statusCode).toBe(400);

    const completed = await server.inject({
      method: "PATCH",
      url: "/v1/goals/goal-registry-1",
      payload: { status: "completed", completion_note: "Evidence reviewed." },
    });
    expect(completed.statusCode).toBe(200);
  });

  it("summarizes goal tasks and evidence without auto-completing goals", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "goal-evidence", name: "Goal Evidence" },
    });
    await server.inject({
      method: "POST",
      url: "/v1/projects/goal-evidence/goals",
      payload: {
        goal_id: "goal-evidence-1",
        title: "Collect evidence",
        status: "active",
        acceptance_criteria: ["Task completed."],
        evidence_requirements: ["PR and validation status."],
      },
    });
    await server.inject({
      method: "POST",
      url: "/v1/tasks",
      payload: {
        task_id: "evidence-task-1",
        project_id: "goal-evidence",
        goal_id: "goal-evidence-1",
        title: "Evidence task",
        risk: "low",
        source: "manual",
      },
    });

    const complete = await server.inject({
      method: "POST",
      url: "/v1/tasks/evidence-task-1/complete",
      payload: {
        summary: "Task done.",
        evidence_summary: {
          task_id: "evidence-task-1",
          goal_id: "goal-evidence-1",
          pr_url: "https://example.invalid/pull/1",
          commit_sha: "abc123",
          changed_files: ["docs/example.md"],
          validation_status: "passed",
          ci_status: "pending",
          risk_status: "low",
          summary: "Docs changed and validation passed.",
        },
      },
    });
    expect(complete.statusCode).toBe(200);

    const detail = await server.inject({
      method: "GET",
      url: "/v1/goals/goal-evidence-1",
    });
    const goal = detail.json<{
      goal: {
        status: string;
        task_summary: { completed: number; evidence_count: number };
        progress_summary: { completed_tasks: number; evidence_count: number };
      };
    }>().goal;
    expect(goal.status).toBe("partially_completed");
    expect(goal.task_summary).toMatchObject({ completed: 1, evidence_count: 1 });
    expect(goal.progress_summary).toMatchObject({ completed_tasks: 1, evidence_count: 1 });
  });

  it("rejects executable tasks for archived goals", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "archived-project", name: "Archived Project" },
    });
    await server.inject({
      method: "POST",
      url: "/v1/projects/archived-project/goals",
      payload: { goal_id: "archived-goal", title: "Archived", status: "archived" },
    });

    const task = await server.inject({
      method: "POST",
      url: "/v1/tasks",
      payload: {
        task_id: "archived-task",
        project_id: "archived-project",
        goal_id: "archived-goal",
        title: "Should not execute",
      },
    });
    expect(task.statusCode).toBe(409);
    expect(task.json<{ error: string }>().error).toBe("goal_not_executable");
  });

  it("runs task queue transitions and writes task events", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "proj-tasks", name: "Task project" },
    });
    await server.inject({
      method: "POST",
      url: "/v1/projects/proj-tasks/goals",
      payload: { goal_id: "goal-tasks", title: "Task goal" },
    });
    await server.inject({
      method: "POST",
      url: "/v1/workers/register",
      payload: {
        worker_id: "worker-task-1",
        name: "Task worker",
        capabilities: ["manual-execution"],
      },
    });
    await server.inject({
      method: "POST",
      url: "/v1/workers/worker-task-1/heartbeat",
      payload: {},
    });

    const create = await server.inject({
      method: "POST",
      url: "/v1/tasks",
      payload: {
        task_id: "task-1",
        project_id: "proj-tasks",
        goal_id: "goal-tasks",
        title: "Implement task core",
        risk: "medium",
        source: "manual",
      },
    });
    expect(create.statusCode).toBe(201);

    const claim = await server.inject({
      method: "POST",
      url: "/v1/tasks/task-1/claim",
      payload: { worker_id: "worker-task-1" },
    });
    expect(claim.statusCode).toBe(200);
    expect(claim.json<{ task: { status: string } }>().task.status).toBe(
      "claimed",
    );

    const complete = await server.inject({
      method: "POST",
      url: "/v1/tasks/task-1/complete",
      payload: { summary: "done" },
    });
    expect(complete.statusCode).toBe(200);
    expect(
      complete.json<{ task: { status: string; events: Array<{ type: string }> } }>()
        .task,
    ).toMatchObject({
      status: "completed",
      events: expect.arrayContaining([
        expect.objectContaining({ type: "task.created" }),
        expect.objectContaining({ type: "task.claimed" }),
        expect.objectContaining({ type: "task.completed" }),
      ]),
    });

    const claimCompleted = await server.inject({
      method: "POST",
      url: "/v1/tasks/task-1/claim",
      payload: { worker_id: "worker-task-1" },
    });
    expect(claimCompleted.statusCode).toBe(409);

    const failTask = await server.inject({
      method: "POST",
      url: "/v1/tasks",
      payload: {
        task_id: "task-2",
        project_id: "proj-tasks",
        title: "Fail then requeue",
      },
    });
    expect(failTask.statusCode).toBe(201);
    await server.inject({
      method: "POST",
      url: "/v1/tasks/task-2/claim",
      payload: { worker_id: "worker-task-1" },
    });
    expect(
      (
        await server.inject({
          method: "POST",
          url: "/v1/tasks/task-2/fail",
          payload: { error_summary: "test failure" },
        })
      ).json<{ task: { status: string } }>().task.status,
    ).toBe("failed");
    expect(
      (
        await server.inject({ method: "POST", url: "/v1/tasks/task-2/requeue" })
      ).json<{ task: { status: string } }>().task.status,
    ).toBe("queued");
  });

  it("stores Hermes planner task metadata without raw secrets", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "proj-hermes", name: "Hermes project" },
    });
    const create = await server.inject({
      method: "POST",
      url: "/v1/tasks",
      payload: {
        task_id: "task-hermes",
        project_id: "proj-hermes",
        title: "Docs from Hermes",
        body: "Update docs only.",
        prompt_summary: "Update docs only.",
        risk: "low",
        source: "hermes-planner",
        task_type: "docs",
        allowed_paths: ["docs/orchestrator/"],
        blocked_paths: [".env", "config/*.secret.ps1"],
        validation: ["corepack pnpm check"],
        planner_metadata: {
          adapter: "hermes-planner",
          decision: "continue",
          reason: "safe docs task",
          token: "must-not-return",
          raw_response: "must-not-return",
          allowed_paths: ["docs/orchestrator/"],
          blocked_paths: [".env"],
          validation: ["corepack pnpm check"],
          stop_criteria_status: ["in_progress"],
        },
      },
    });

    expect(create.statusCode).toBe(201);
    const text = create.body;
    expect(text).not.toContain("must-not-return");
    expect(create.json<{ task: { source: string; planner_metadata: { raw_response_included: boolean; secrets_included: boolean }; validation: string[] } }>().task).toMatchObject({
      source: "hermes-planner",
      validation: ["corepack pnpm check"],
      planner_metadata: {
        raw_response_included: false,
        secrets_included: false,
      },
    });
  });

  it("prevents disabled and offline workers from claiming tasks", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "proj-claim", name: "Claim project" },
    });
    await server.inject({
      method: "POST",
      url: "/v1/tasks",
      payload: { task_id: "task-disabled", project_id: "proj-claim", title: "Blocked claim" },
    });
    await server.inject({
      method: "POST",
      url: "/v1/workers/register",
      payload: { worker_id: "worker-disabled", name: "Disabled", enabled: false },
    });
    const disabled = await server.inject({
      method: "POST",
      url: "/v1/tasks/task-disabled/claim",
      payload: { worker_id: "worker-disabled" },
    });
    expect(disabled.statusCode).toBe(409);

    await server.inject({
      method: "POST",
      url: "/v1/workers/register",
      payload: { worker_id: "worker-offline", name: "Offline" },
    });
    const offline = await server.inject({
      method: "POST",
      url: "/v1/tasks/task-disabled/claim",
      payload: { worker_id: "worker-offline" },
    });
    expect(offline.statusCode).toBe(409);
  });

  it("persists worker pool and task records to SQLite", async () => {
    const dir = await tempDir();
    const dbFile = join(dir, "skybridge.sqlite");
    const first = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(first);
    await first.inject({
      method: "POST",
      url: "/v1/projects",
      payload: { project_id: "proj-durable", name: "Durable project" },
    });
    await first.inject({
      method: "POST",
      url: "/v1/workers/register",
      payload: { worker_id: "worker-durable", name: "Durable worker" },
    });
    await first.inject({
      method: "POST",
      url: "/v1/tasks",
      payload: { task_id: "task-durable", project_id: "proj-durable", title: "Durable task" },
    });
    await first.close();
    servers.pop();

    const second = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(second);
    expect(
      (
        await second.inject({ method: "GET", url: "/v1/tasks/task-durable" })
      ).json<{ task: { task_id: string } }>().task.task_id,
    ).toBe("task-durable");
    expect(
      (
        await second.inject({ method: "GET", url: "/v1/workers/worker-durable" })
      ).json<{ worker: { worker_id: string } }>().worker.worker_id,
    ).toBe("worker-durable");
  });

  it("derives SQLite worker status from persisted heartbeats", async () => {
    const dir = await tempDir();
    const dbFile = join(dir, "skybridge.sqlite");
    const server = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(server);

    await server.inject({
      method: "POST",
      url: "/v1/workers/register",
      payload: { worker_id: "sqlite-worker", name: "SQLite worker" },
    });
    const heartbeat = await server.inject({
      method: "POST",
      url: "/v1/workers/sqlite-worker/heartbeat",
      payload: {},
    });

    expect(heartbeat.json<{ worker: { status: string; last_seen_at?: string } }>().worker).toMatchObject({
      status: "online",
      last_seen_at: expect.any(String),
    });
  });

  it("summarizes remote node heartbeat events without command execution", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:00:00.000Z",
        type: "node.heartbeat",
        source: {
          platform: "skybridge",
          adapter: "sidecar",
          node_id: "node-local-1",
        },
        correlation: { session_id: "node-local-1" },
        payload: {
          node_id: "node-local-1",
          host: "devbox",
          labels: ["local", "sidecar"],
          capabilities: ["event-forwarding", "heartbeat"],
          sidecar_version: "0.1.0",
        },
      }),
    });

    const response = await server.inject({ method: "GET", url: "/v1/nodes" });
    expect(response.statusCode).toBe(200);
    expect(
      response.json<{
        nodes: Array<{
          node_id: string;
          status: string;
          capabilities: string[];
        }>;
      }>().nodes[0],
    ).toMatchObject({
      node_id: "node-local-1",
      status: "stale",
      capabilities: ["event-forwarding", "heartbeat"],
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
        payload: { approval_id: "approval-1", title: "Edit file" },
      }),
    });

    const pending = await server.inject({
      method: "GET",
      url: "/v1/approvals",
    });
    expect(
      pending.json<{
        approvals: Array<{ approval_id: string; status: string }>;
      }>().approvals[0],
    ).toMatchObject({
      approval_id: "approval-1",
      status: "pending",
    });

    const resolved = await server.inject({
      method: "POST",
      url: "/v1/approvals/approval-1/resolve",
      payload: { decision: "denied", actor: "operator", reason: "safe test" },
    });
    expect(resolved.statusCode).toBe(202);

    const detail = await server.inject({
      method: "GET",
      url: "/v1/approvals/approval-1",
    });
    expect(
      detail.json<{ approval: { status: string } }>().approval.status,
    ).toBe("denied");
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
        payload: {},
      }),
    });

    const response = await server.inject({ method: "GET", url: "/v1/metrics" });
    expect(response.statusCode).toBe(200);
    expect(
      response.json<{
        total_events: number;
        runs_by_status: Record<string, number>;
        runs_by_source: Record<string, number>;
      }>(),
    ).toMatchObject({
      total_events: 1,
      runs_by_status: { failed: 1 },
      runs_by_source: { hermes: 1 },
    });
  });

  it("creates, lists, updates and retrieves iteration records", async () => {
    const server = await testServer();
    const create = await server.inject({
      method: "POST",
      url: "/v1/iterations",
      payload: {
        iteration_id: "iter-test-1",
        project_id: "skybridge-agent-hub",
        goal_id: "015",
        repo: "owner/skybridge-agent-hub",
        branch: "ai/iter-test",
        base_branch: "main",
        state: "queued",
        attempts: 0,
        max_attempts: 3,
        checks: [],
      },
    });

    expect(create.statusCode).toBe(201);
    const update = await server.inject({
      method: "PATCH",
      url: "/v1/iterations/iter-test-1/state",
      payload: {
        state: "local_checking",
        checks: [
          { name: "corepack pnpm check", status: "passed", summary: "passed" },
        ],
      },
    });
    expect(update.statusCode).toBe(200);

    const list = await server.inject({ method: "GET", url: "/v1/iterations" });
    expect(
      list.json<{
        iterations: Array<{ iteration_id: string; state: string }>;
      }>().iterations[0],
    ).toMatchObject({
      iteration_id: "iter-test-1",
      state: "local_checking",
    });

    const detail = await server.inject({
      method: "GET",
      url: "/v1/iterations/iter-test-1",
    });
    expect(
      detail.json<{ iteration: { checks: Array<{ status: string }> } }>()
        .iteration.checks[0]?.status,
    ).toBe("passed");
  });

  it("persists iteration state and events to SQLite across server restarts", async () => {
    const dir = await tempDir();
    const dbFile = join(dir, "skybridge.sqlite");
    const first = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(first);

    await first.inject({
      method: "POST",
      url: "/v1/iterations",
      payload: {
        iteration_id: "iter-durable-1",
        project_id: "skybridge-agent-hub",
        goal_id: "017",
        repo: "owner/skybridge-agent-hub",
        branch: "ai/iter-durable",
        base_branch: "main",
        state: "queued",
        attempts: 0,
        max_attempts: 3,
        checks: [],
      },
    });
    await first.inject({
      method: "PATCH",
      url: "/v1/iterations/iter-durable-1/state",
      payload: {
        state: "ci_pending",
        pr_number: 77,
        attempts: 1,
        checks: [{ name: "server test", status: "passed", summary: "ok" }],
      },
    });
    await first.inject({
      method: "POST",
      url: "/v1/iterations/iter-durable-1/events",
      payload: {
        type: "iteration.ci_pending",
        payload: {
          state: "ci_pending",
          raw_prompt: "do not expose this prompt",
          stdout: "do not expose this output",
          token: "secret-token",
        },
      },
    });
    await first.close();
    servers.pop();

    const second = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(second);

    const list = await second.inject({
      method: "GET",
      url: "/v1/iterations?state=ci_pending&project_id=skybridge-agent-hub&branch=ai/iter-durable&pr_number=77",
    });
    expect(list.statusCode).toBe(200);
    expect(
      list.json<{
        iterations: Array<{
          iteration_id: string;
          state: string;
          pr_number: number;
        }>;
      }>().iterations,
    ).toEqual([
      expect.objectContaining({
        iteration_id: "iter-durable-1",
        state: "ci_pending",
        pr_number: 77,
      }),
    ]);

    const detail = await second.inject({
      method: "GET",
      url: "/v1/iterations/iter-durable-1",
    });
    expect(detail.statusCode).toBe(200);
    const iteration = detail.json<{
      iteration: {
        state: string;
        checks: Array<{ name: string }>;
        events: Array<{ payload: Record<string, unknown> }>;
      };
    }>().iteration;
    expect(iteration.state).toBe("ci_pending");
    expect(iteration.checks[0]?.name).toBe("server test");
    const text = JSON.stringify(iteration);
    expect(text).not.toContain("do not expose this prompt");
    expect(text).not.toContain("do not expose this output");
    expect(text).not.toContain("secret-token");
  });

  it("rejects invalid iteration state and redacts unsafe iteration payloads", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/iterations",
      payload: {
        iteration_id: "iter-test-2",
        project_id: "skybridge-agent-hub",
        repo: "owner/skybridge-agent-hub",
        branch: "ai/iter-test",
        base_branch: "main",
        state: "queued",
      },
    });

    const invalid = await server.inject({
      method: "PATCH",
      url: "/v1/iterations/iter-test-2/state",
      payload: { state: "surprised" },
    });
    expect(invalid.statusCode).toBe(400);

    const event = await server.inject({
      method: "POST",
      url: "/v1/iterations/iter-test-2/events",
      payload: {
        type: "iteration.ci_failed",
        payload: {
          token: "secret-token",
          stdout: "raw output should be omitted",
          safe: "metadata",
        },
      },
    });

    expect(event.statusCode).toBe(202);
    const body = event.json<{ event: { payload: Record<string, unknown> } }>();
    expect(JSON.stringify(body)).not.toContain("secret-token");
    expect(JSON.stringify(body)).not.toContain("raw output should be omitted");
    expect(body.event.payload.safe).toBe("metadata");
  });

  it("exposes supervisor status without raw logs", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/iterations",
      payload: {
        iteration_id: "iter-test-3",
        project_id: "skybridge-agent-hub",
        repo: "owner/skybridge-agent-hub",
        branch: "ai/iter-test",
        base_branch: "main",
        state: "ci_failed",
        pr_number: 12,
      },
    });

    const status = await server.inject({
      method: "GET",
      url: "/v1/supervisor/status",
    });
    expect(status.statusCode).toBe(200);
    expect(
      status.json<{
        raw_logs_included: boolean;
        iterations: { active: number };
        notification_path: { skybridge_notification_center_required: boolean };
      }>(),
    ).toMatchObject({
      raw_logs_included: false,
      iterations: { active: 1 },
      notification_path: { skybridge_notification_center_required: false },
    });

    const next = await server.inject({
      method: "GET",
      url: "/v1/supervisor/next-action",
    });
    expect(next.json<{ action: string; pr_number: number }>()).toMatchObject({
      action: "repair_ci",
      pr_number: 12,
    });
  });

  it("returns product summary APIs from safe local state", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/iterations",
      payload: {
        iteration_id: "iter-product-1",
        project_id: "skybridge-agent-hub",
        repo: "JerrySkywalker/skybridge-agent-hub",
        branch: "ai/product",
        base_branch: "main",
        state: "ci_green",
        pr_number: 61,
        attempts: 1,
        max_attempts: 3,
        checks: [{ name: "Project check", status: "passed", summary: "ok" }],
      },
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "run.completed",
        source: { platform: "hermes", adapter: "hermes-api" },
        correlation: { run_id: "hermes-safe-run" },
        payload: { capabilities: ["health"], health: "ok" },
      }),
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        type: "notification.sent",
        source: { platform: "skybridge", adapter: "notification-center" },
        correlation: { run_id: "notify-run" },
        payload: { provider: "ntfy", status: "sent" },
      }),
    });

    const projects = await server.inject({
      method: "GET",
      url: "/v1/projects",
    });
    expect(
      projects.json<{
        projects: Array<{ project_id: string; iteration_count: number }>;
      }>().projects,
    ).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          project_id: "skybridge-agent-hub",
          iteration_count: 1,
        }),
      ]),
    );

    expect(
      (
        await server.inject({ method: "GET", url: "/v1/iterations/summary" })
      ).json<{ total: number; latest: { iteration_id: string } }>(),
    ).toMatchObject({
      total: 1,
      latest: { iteration_id: "iter-product-1" },
    });
    expect(
      (await server.inject({ method: "GET", url: "/v1/prs/summary" })).json<{
        open: number;
        eligible: number;
        latest_ci_state: string;
      }>(),
    ).toMatchObject({
      open: 1,
      eligible: 1,
      latest_ci_state: "ci_green",
    });
    expect(
      (await server.inject({ method: "GET", url: "/v1/hermes/summary" })).json<{
        status: string;
        api: { health: string };
      }>(),
    ).toMatchObject({
      status: "available",
      api: { health: "ok" },
    });
    expect(
      (
        await server.inject({ method: "GET", url: "/v1/automerge/summary" })
      ).json<{ enabled_by_default: boolean; eligible: number }>(),
    ).toMatchObject({
      enabled_by_default: false,
      eligible: 1,
    });
    expect(
      (
        await server.inject({ method: "GET", url: "/v1/notifications/summary" })
      ).json<{
        providers: unknown[];
        bootstrap_fallback: { real_send_requires_explicit_send: boolean };
      }>(),
    ).toMatchObject({
      bootstrap_fallback: { real_send_requires_explicit_send: true },
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
        source: {
          platform: "opencode",
          adapter: "opencode-plugin",
          agent_id: "opencode-local",
        },
        correlation: { run_id: "audit-run" },
        payload: {
          approval_id: "approval-audit-1",
          title: "Edit file",
          prompt: "should stay out of audit response",
        },
      }),
    });
    await server.inject({
      method: "POST",
      url: "/v1/approvals/approval-audit-1/resolve",
      payload: {
        decision: "denied",
        actor: "operator",
        reason: "safe audit test",
      },
    });

    const response = await server.inject({ method: "GET", url: "/v1/audit" });
    expect(response.statusCode).toBe(200);
    const audit = response.json<{
      audit: Array<{
        action: string;
        actor: string;
        source_adapter: string;
        safety_decision: string;
        immutable_event_id: string;
        redaction_policy_version: string;
        raw_payload_included: boolean;
      }>;
    }>().audit;
    expect(audit).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          action: "approval.denied",
          actor: "operator",
          source_adapter: "skybridge/approval-api",
          safety_decision: "operator_denied",
          redaction_policy_version:
            "packages/event-schema/src/redaction-rules.json",
          raw_payload_included: false,
        }),
        expect.objectContaining({
          action: "approval.requested",
          source_adapter: "opencode/opencode-plugin",
          safety_decision: "approval_required_remote_execution_disabled",
          immutable_event_id: expect.any(String),
          raw_payload_included: false,
        }),
      ]),
    );
    expect(JSON.stringify(audit)).not.toContain("should stay out");
  });

  it("persists durable audit records and filters them without raw payloads", async () => {
    const dir = await tempDir();
    const dbFile = join(dir, "skybridge.sqlite");
    const first = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(first);

    await first.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:00:00.000Z",
        type: "approval.requested",
        severity: "warning",
        source: {
          platform: "codex",
          adapter: "codex-hook",
          agent_id: "codex-local",
        },
        correlation: {
          run_id: "durable-audit-run",
          session_id: "durable-audit-session",
        },
        payload: {
          approval_id: "durable-audit-approval",
          actor: "nightly-guardian",
          prompt: "raw prompt must not persist in audit",
          stdout: "raw output must not persist in audit",
        },
      }),
    });
    await first.close();
    servers.pop();

    const second = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(second);

    const response = await second.inject({
      method: "GET",
      url: "/v1/audit?run_id=durable-audit-run&actor=nightly-guardian&action=approval.requested&from=2026-05-20T00:00:00.000Z&to=2026-05-22T00:00:00.000Z",
    });

    expect(response.statusCode).toBe(200);
    const audit = response.json<{
      audit: Array<{
        action: string;
        actor: string;
        immutable_event_id: string;
        redaction_policy_version: string;
        raw_payload_included: boolean;
      }>;
    }>().audit;
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({
      action: "approval.requested",
      actor: "nightly-guardian",
      immutable_event_id: expect.any(String),
      redaction_policy_version:
        "packages/event-schema/src/redaction-rules.json",
      raw_payload_included: false,
    });
    expect(JSON.stringify(audit)).not.toContain("raw prompt");
    expect(JSON.stringify(audit)).not.toContain("raw output");
  });

  it("records durable audit fixtures for node, notification and failed-run events", async () => {
    const dir = await tempDir();
    const dbFile = join(dir, "skybridge.sqlite");
    const first = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(first);

    await first.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:00:00.000Z",
        type: "node.heartbeat",
        source: {
          platform: "skybridge",
          adapter: "sidecar",
          node_id: "audit-node-1",
        },
        correlation: { session_id: "audit-node-session" },
        payload: {
          node_id: "audit-node-1",
          host: "local-devbox",
          private_key: "-----BEGIN OPENSSH PRIVATE KEY----- secret",
          command_output: "node private output must not persist",
        },
      }),
    });
    await first.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:01:00.000Z",
        type: "notification.requested",
        severity: "warning",
        source: {
          platform: "skybridge",
          adapter: "notification-router",
          agent_id: "router-agent",
        },
        correlation: {
          run_id: "audit-router-run",
          session_id: "audit-router-session",
        },
        payload: {
          actor: "notification-router",
          provider: "ntfy",
          body: "notification body must not persist",
          token: "secret-token",
        },
      }),
    });
    await first.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:02:00.000Z",
        type: "run.failed",
        severity: "error",
        source: {
          platform: "codex",
          adapter: "codex-exec-json",
          agent_id: "codex-local",
        },
        correlation: {
          run_id: "audit-failed-run",
          session_id: "audit-failed-session",
        },
        payload: {
          actor: "codex-local",
          stderr: "failure stderr must not persist",
          prompt: "failure prompt must not persist",
        },
      }),
    });
    await first.close();
    servers.pop();

    const second = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(second);

    const response = await second.inject({
      method: "GET",
      url: "/v1/audit?limit=10",
    });
    expect(response.statusCode).toBe(200);
    const audit = response.json<{
      audit: Array<{
        action: string;
        actor: string;
        source_adapter: string;
        run_id?: string;
        safety_decision: string;
        raw_payload_included: boolean;
      }>;
    }>().audit;

    expect(audit).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          action: "node.heartbeat",
          actor: "system",
          source_adapter: "skybridge/sidecar",
          safety_decision: "node_telemetry_only",
          raw_payload_included: false,
        }),
        expect.objectContaining({
          action: "notification.requested",
          actor: "notification-router",
          run_id: "audit-router-run",
          source_adapter: "skybridge/notification-router",
          safety_decision: "notification_metadata_only",
          raw_payload_included: false,
        }),
        expect.objectContaining({
          action: "run.failed",
          actor: "codex-local",
          run_id: "audit-failed-run",
          source_adapter: "codex/codex-exec-json",
          safety_decision: "failure_observed",
          raw_payload_included: false,
        }),
      ]),
    );

    const auditText = JSON.stringify(audit);
    expect(auditText).not.toContain("OPENSSH PRIVATE KEY");
    expect(auditText).not.toContain("node private output");
    expect(auditText).not.toContain("notification body");
    expect(auditText).not.toContain("secret-token");
    expect(auditText).not.toContain("failure stderr");
    expect(auditText).not.toContain("failure prompt");
  });

  it("exports bounded audit JSONL without raw payloads", async () => {
    const server = await testServer();
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:00:00.000Z",
        type: "approval.requested",
        severity: "warning",
        source: {
          platform: "codex",
          adapter: "codex-hook",
          agent_id: "codex-local",
        },
        correlation: { run_id: "audit-export-run" },
        payload: {
          approval_id: "audit-export-approval",
          actor: "operator",
          prompt: "raw export prompt must not appear",
          token: "raw-export-token",
        },
      }),
    });
    await server.inject({
      method: "POST",
      url: "/v1/events",
      payload: createEvent({
        time: "2026-05-21T00:01:00.000Z",
        type: "run.failed",
        severity: "error",
        source: {
          platform: "codex",
          adapter: "codex-exec-json",
          agent_id: "codex-local",
        },
        correlation: { run_id: "audit-export-run" },
        payload: {
          actor: "codex-local",
          stderr: "raw export stderr must not appear",
        },
      }),
    });

    const response = await server.inject({
      method: "GET",
      url: "/v1/audit/export?run_id=audit-export-run&limit=1",
    });
    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toContain("application/x-ndjson");
    expect(response.headers["x-skybridge-raw-payload-included"]).toBe("false");

    const lines = response.body.trim().split("\n");
    expect(lines).toHaveLength(1);
    const exported = JSON.parse(lines[0]!) as {
      run_id: string;
      raw_payload_included: boolean;
    };
    expect(exported).toMatchObject({
      run_id: "audit-export-run",
      raw_payload_included: false,
    });
    expect(response.body).not.toContain("raw export prompt");
    expect(response.body).not.toContain("raw-export-token");
    expect(response.body).not.toContain("raw export stderr");
  });

  it("persists events and notifications to SQLite across server restarts", async () => {
    const previousTopic = process.env.NTFY_TOPIC_URL;
    delete process.env.NTFY_TOPIC_URL;
    const dir = await tempDir();
    const dbFile = join(dir, "skybridge.sqlite");
    const first = await createServer({
      dbFile,
      logger: false,
      jsonMigrationFile: false,
    });
    servers.push(first);

    try {
      await first.inject({
        method: "POST",
        url: "/v1/events",
        payload: createEvent({
          type: "run.completed",
          source: { platform: "codex", adapter: "codex-hook" },
          correlation: { session_id: "s1", run_id: "persisted-run" },
          payload: { summary: "done" },
        }),
      });
      await first.inject({
        method: "POST",
        url: "/v1/notifications/send",
        payload: {
          title: "Saved notification",
          body: "SQLite should retain this",
        },
      });
      await first.close();
      servers.pop();

      const second = await createServer({
        dbFile,
        logger: false,
        jsonMigrationFile: false,
      });
      servers.push(second);
      const events = (
        await second.inject({ method: "GET", url: "/v1/events" })
      ).json<{ events: StoredEvent[] }>().events;
      const notifications = (
        await second.inject({ method: "GET", url: "/v1/notifications" })
      ).json<{ notifications: StoredNotification[] }>().notifications;

      expect(events.map((event) => event.correlation?.run_id)).toContain(
        "persisted-run",
      );
      expect(
        notifications.map((notification) => notification.message.title),
      ).toContain("Saved notification");
    } finally {
      if (previousTopic === undefined) {
        delete process.env.NTFY_TOPIC_URL;
      } else {
        process.env.NTFY_TOPIC_URL = previousTopic;
      }
    }
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
        payload: { source: "json" },
      }),
      id: "legacy-event-1",
      receivedAt: "2026-05-21T00:00:00.000Z",
    };
    await writeFile(
      legacyJsonFile,
      JSON.stringify({ events: [legacyEvent], notifications: [] }),
      "utf8",
    );

    const server = await createServer({
      dbFile,
      jsonMigrationFile: legacyJsonFile,
      logger: false,
    });
    servers.push(server);

    const events = (
      await server.inject({ method: "GET", url: "/v1/events" })
    ).json<{ events: StoredEvent[] }>().events;
    expect(events).toHaveLength(1);
    expect(events[0]?.id).toBe("legacy-event-1");
  });

  it("migrates existing safe audit records from local JSON into SQLite", async () => {
    const dir = await tempDir();
    const legacyJsonFile = join(dir, "skybridge-store.json");
    const dbFile = join(dir, "skybridge.sqlite");
    const legacyAudit: StoredAuditRecord = {
      audit_id: "legacy-audit-1",
      time: "2026-05-21T00:00:00.000Z",
      action: "approval.denied",
      actor: "operator",
      source_adapter: "skybridge/approval-api",
      run_id: "legacy-audit-run",
      session_id: "legacy-audit-session",
      safety_decision: "operator_denied",
      immutable_event_id: "legacy-event-1",
      redaction_policy_version:
        "packages/event-schema/src/redaction-rules.json",
      raw_payload_included: false,
    };
    await writeFile(
      legacyJsonFile,
      JSON.stringify({ events: [], notifications: [], audit: [legacyAudit] }),
      "utf8",
    );

    const server = await createServer({
      dbFile,
      jsonMigrationFile: legacyJsonFile,
      logger: false,
    });
    servers.push(server);

    const response = await server.inject({
      method: "GET",
      url: "/v1/audit?run_id=legacy-audit-run&actor=operator&action=approval.denied",
    });
    expect(response.statusCode).toBe(200);
    const audit = response.json<{ audit: StoredAuditRecord[] }>().audit;
    expect(audit).toEqual([legacyAudit]);
    expect(JSON.stringify(audit)).not.toContain("prompt");
    expect(JSON.stringify(audit)).not.toContain("stdout");
    expect(JSON.stringify(audit)).not.toContain("token");
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
          payload: {},
        }),
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
        payload: {},
      }),
    });
    await server.listen({ port: 0, host: "127.0.0.1" });
    const address = server.server.address();
    if (!address || typeof address === "string")
      throw new Error("server did not bind to a TCP port");

    const controller = new AbortController();
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/stream`, {
      signal: controller.signal,
    });
    expect(response.ok).toBe(true);
    const text = await readUntil(response, "sse-run", controller);
    expect(text).toContain("event: connected");
    expect(text).toContain("event: skybridge.event");
    expect(text).toContain("sse-run");
  });
});

async function waitForNotifications(
  server: Awaited<ReturnType<typeof createServer>>,
) {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const response = await server.inject({
      method: "GET",
      url: "/v1/notifications",
    });
    const notifications = response.json<{
      notifications: StoredNotification[];
    }>().notifications;
    if (notifications.length > 0) return notifications;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return [];
}

async function readUntil(
  response: Response,
  needle: string,
  controller: AbortController,
) {
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
