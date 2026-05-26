import { describe, expect, it } from "vitest";
import {
  createEvent,
  createManualExecutionResult,
  createRuleBasedPlannerDecision,
  isNotificationTrigger,
  listAdapterCapabilities,
  parseEvent,
  redactForTelemetry,
  SharedRedactionRules,
} from "./index.js";

describe("event schema", () => {
  it("creates a normalized event", () => {
    const event = createEvent({
      type: "run.started",
      source: { platform: "codex", adapter: "codex-hook" },
      severity: "info",
      payload: {},
    });

    expect(event.schema).toBe("skybridge.agent_event.v1");
    expect(event.type).toBe("run.started");
  });

  it("validates source families used by first-party adapters", () => {
    for (const platform of ["codex", "opencode", "hermes"] as const) {
      const event = parseEvent({
        schema: "skybridge.agent_event.v1",
        time: new Date().toISOString(),
        type: "run.started",
        severity: "info",
        source: { platform, adapter: `${platform}-adapter` },
        correlation: { session_id: "s1", run_id: "r1" },
        payload: { message: "started" },
      });

      expect(event.source.platform).toBe(platform);
    }
  });

  it("identifies critical notification trigger events", () => {
    expect(isNotificationTrigger({ type: "run.failed" })).toBe(true);
    expect(isNotificationTrigger({ type: "approval.requested" })).toBe(true);
    expect(isNotificationTrigger({ type: "tool.completed" })).toBe(false);
  });

  it("allows rich run summary metadata without changing event validation", () => {
    const summary = {
      run_id: "runner-001-demo",
      session_id: "runner-123",
      source_platform: "skybridge",
      source_adapter: "yolo-runner",
      source_agent_id: "skybridge-yolo-runner",
      status: "running",
      event_count: 3,
      tool_call_count: 1,
      failed_tool_count: 0,
      notification_count: 1,
      first_seen_at: new Date().toISOString(),
      last_seen_at: new Date().toISOString(),
      last_event_type: "notification.requested",
      title: "001-demo.md",
      lifecycle: "notification.requested",
      branch: "ai/001-demo",
      goal_id: "001",
    };

    expect(summary.run_id).toBe("runner-001-demo");
    expect(summary.tool_call_count).toBe(1);
  });

  it("redacts secret-like keys and summarizes raw output fields", () => {
    const redacted = redactForTelemetry({
      token: "abc123",
      headers: { Authorization: "Bearer abc.def.ghi" },
      stdout: "full command output",
      nested: { api_key: "sk-testsecret123456" },
    }) as Record<string, unknown>;

    expect(redacted.token).toBe(SharedRedactionRules.replacement);
    expect(JSON.stringify(redacted)).not.toContain("abc.def.ghi");
    expect(JSON.stringify(redacted)).not.toContain("sk-testsecret123456");
    expect(redacted.stdout).toMatchObject({
      omitted: true,
      reason: "unsafe_raw_payload",
    });
  });

  it("validates iteration lifecycle events and safe metadata payloads", () => {
    const event = createEvent({
      type: "iteration.state_changed",
      source: { platform: "skybridge", adapter: "iteration-controller" },
      correlation: { run_id: "iter_001" },
      payload: {
        iteration_id: "iter_001",
        project_id: "skybridge-agent-hub",
        goal_id: "015",
        repo: "owner/skybridge-agent-hub",
        branch: "ai/super-015-016",
        base_branch: "main",
        state: "local_checking",
        attempts: 1,
        max_attempts: 3,
        checks: [{ name: "corepack pnpm check", status: "pending" }],
      },
    });

    expect(event.type).toBe("iteration.state_changed");
    expect(event.payload).toMatchObject({
      iteration_id: "iter_001",
      state: "local_checking",
    });
  });

  it("redacts unsafe fields from iteration payloads before telemetry", () => {
    const redacted = redactForTelemetry({
      iteration_id: "iter_safe",
      state: "ci_failed",
      prompt: "raw prompt must not be sent",
      stderr: "raw check output must not be sent",
      token: "secret-token",
    });

    const text = JSON.stringify(redacted);
    expect(text).not.toContain("raw prompt must not be sent");
    expect(text).not.toContain("raw check output must not be sent");
    expect(text).not.toContain("secret-token");
  });

  it("exposes neutral adapter capabilities by role", () => {
    const planners = listAdapterCapabilities("planner");
    const executors = listAdapterCapabilities("executor");
    const notifications = listAdapterCapabilities("notification_provider");

    expect(planners.map((item) => item.id)).toContain("rule-based-planner");
    expect(planners.map((item) => item.id)).toContain("hermes-api");
    expect(executors.map((item) => item.id)).toContain("manual-executor");
    expect(executors.map((item) => item.id)).toContain("codex-exec-json");
    expect(notifications.map((item) => item.id)).toContain("ntfy");
    expect(listAdapterCapabilities().every((item) => item.optional)).toBe(true);
  });

  it("creates a docs-only work order without Hermes", () => {
    const decision = createRuleBasedPlannerDecision({
      goal: "Update the README positioning for agent-agnostic core boundaries.",
      now: "2026-05-25T00:00:00.000Z",
    });

    expect(decision.planner_adapter).toBe("rule-based-planner");
    expect(decision.decision).toBe("continue");
    expect(decision.task?.validation).toContain("corepack pnpm check");
    expect(decision.work_orders).toHaveLength(1);
    expect(decision.work_orders[0]?.kind).toBe("docs");
    expect(decision.work_orders[0]?.task_type).toBe("docs");
    expect(decision.work_orders[0]?.constraints).toContain("no deployment");
  });

  it("records a manual executor result without Codex", () => {
    const [workOrder] = createRuleBasedPlannerDecision({
      goal: "Write docs",
      now: "2026-05-25T00:00:00.000Z",
    }).work_orders;
    const result = createManualExecutionResult({
      workOrder: workOrder!,
      summary: "Documentation update completed manually.",
      prNumber: 27,
      now: "2026-05-25T00:01:00.000Z",
    });

    expect(result.executor_adapter).toBe("manual-executor");
    expect(result.pr_number).toBe(27);
    expect(result.events[0]?.source.adapter).toBe("manual-executor");
    expect(result.events[0]?.payload.manual_result).toBe(true);
  });
});
