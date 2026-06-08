import { afterEach, describe, expect, it, vi } from "vitest";
import {
  createAttentionModel,
  createWorkerServiceReadiness,
  createWorkerRoutePreview,
  deriveAttentionEvents,
  SkyBridgeClient,
  fixtureCampaignRunReport,
  fixtureCampaignLock,
  fixtureCampaignPriorityQueue,
  fixtureGoalQueueReviewSummary,
  fixtureProjectProfileReviewSummary,
  fixtureProjectSelectionPreview,
  fixtureQueueControlState,
  fixtureRepoExclusiveLock,
  fixtureStaleCampaignLock,
  fixtureWorkerReadiness,
  fixtureWorkerRoutingReadiness,
  fixtureWorkerServiceState,
  notificationRoutingMatrix,
  queueControlActionMatrix,
  routeAttentionEvent,
  workerRoutingPolicy,
} from "./index.js";

const fetchMock = vi.fn();

afterEach(() => {
  fetchMock.mockReset();
  vi.unstubAllGlobals();
});

function jsonResponse(body: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body
  } as Response;
}

describe("SkyBridgeClient", () => {
  it("classifies queue-control actions and lock previews for Goal 198", () => {
    const byAction = new Map(queueControlActionMatrix.map((entry) => [entry.action, entry]));

    expect(byAction.get("refresh_status")).toMatchObject({
      class: "read_only",
      allowed_modes: ["read"],
      token_printed: false,
    });
    expect(byAction.get("safe_pause")).toMatchObject({
      class: "safe_stop_pause",
      apply_allowed: true,
      reason_required: true,
      token_printed: false,
    });
    expect(byAction.get("start_one_preview")).toMatchObject({
      class: "preview",
      allowed_modes: ["preview"],
      apply_allowed: false,
    });
    expect(byAction.get("start_one_apply")).toMatchObject({
      class: "armed_execution",
      apply_allowed: false,
      requires_arm_lease: true,
      blockers: ["execution_apply_deferred_until_goal_199"],
    });
    expect(byAction.get("campaign_lock_preview")).toMatchObject({
      class: "preview",
      apply_allowed: false,
      token_printed: false,
    });
    expect(byAction.get("unlock_stale_campaign_lock")).toMatchObject({
      class: "safe_stop_pause",
      apply_allowed: true,
      reason_required: true,
    });
    expect(byAction.get("start_all")).toMatchObject({
      class: "forbidden",
      apply_allowed: false,
      blockers: ["forbidden_action"],
    });
    expect(fixtureQueueControlState).toMatchObject({
      current_goal_id: "super-198-multi-project-support",
      active_tasks: 0,
      stale_leases: 0,
      worker_status: "offline",
      can_start_one: false,
      can_start_queue: false,
      can_resume: false,
      token_printed: false,
    });
  });

  it("models campaign and repo locks with deterministic priority queue selection", () => {
    expect(fixtureCampaignLock).toMatchObject({
      schema: "skybridge.campaign_lock.v1",
      campaign_id: "dev-queue-189-200",
      project_id: "skybridge-agent-hub",
      lock_status: "held",
      token_printed: false,
    });
    expect(fixtureRepoExclusiveLock).toMatchObject({
      schema: "skybridge.repo_exclusive_lock.v1",
      repo_id: "skybridge-agent-hub",
      lock_status: "active",
      blocks_execution_preview: true,
      force_release_allowed: false,
      token_printed: false,
    });
    expect(fixtureStaleCampaignLock).toMatchObject({
      lock_status: "stale",
      stale: true,
      token_printed: false,
    });
    expect(fixtureCampaignPriorityQueue.selection).toMatchObject({
      selected_campaign_id: "dev-queue-189-200",
      decision: "blocked",
      execution_side_effects: false,
      token_printed: false,
    });
    expect(fixtureCampaignPriorityQueue.items.map((item) => item.priority)).toEqual([10, 20]);
  });

  it("models Goal 195 manual queue review without execution controls", () => {
    expect(fixtureGoalQueueReviewSummary).toMatchObject({
      schema: "skybridge.goal_queue_review_summary.v1",
      goal_pack_id: "dev-queue-189-200",
      validation_result: "pass",
      hash_drift_count: 0,
      dependency_order_status: "valid",
      no_execution_controls: true,
      task_created: false,
      worker_loop_started: false,
      queue_execution_enabled: false,
      token_printed: false,
    });
  });

  it("models Goal 194 worker service readiness without task claim or execution", () => {
    expect(fixtureWorkerServiceState).toMatchObject({
      schema: "skybridge.worker_service_state.v1",
      mode: "offline",
      current_task_id: null,
      can_claim_tasks: false,
      can_execute_tasks: false,
      token_printed: false,
    });
    expect(fixtureWorkerServiceState.capability_matrix).toMatchObject({
      heartbeat: true,
      task_claim: false,
      task_execute: false,
      codex_execute: false,
      pr_create: false,
      arbitrary_shell: false,
    });
    const readiness = createWorkerServiceReadiness(fixtureWorkerServiceState, {
      cleanWorktree: true,
      activeTasks: 0,
      staleLeases: 0,
      runnerLockStatus: "none",
    });
    expect(readiness).toMatchObject({
      schema: "skybridge.worker_service_readiness.v1",
      ready_for_start_one_gate: false,
      can_claim_tasks: false,
      can_execute_tasks: false,
      token_printed: false,
    });
    expect(readiness.blockers).toEqual(expect.arrayContaining(["worker_service_offline", "execution_disabled_until_goal_199"]));
    expect(fixtureCampaignRunReport.worker_service_state).toMatchObject({ mode: "offline", token_printed: false });
    expect(fixtureCampaignRunReport.queue_control_readiness).toMatchObject({
      can_start_one: false,
      can_start_queue: false,
      can_resume: false,
      execution_disabled_until_goal: "super-199-hermes-goal-draft-generator",
    });
  });

  it("models Goal 197 multi-worker route preview without claim or execution", () => {
    const preview = createWorkerRoutePreview(undefined, fixtureWorkerReadiness);

    expect(workerRoutingPolicy).toMatchObject({
      max_parallel_per_repo: 1,
      can_claim_tasks: false,
      can_execute_tasks: false,
      token_printed: false,
    });
    expect(preview).toMatchObject({
      schema: "skybridge.worker_route_preview.v1",
      mode: "preview",
      task_created: false,
      task_claimed: false,
      task_executed: false,
      worker_loop_started: false,
      queue_execution_enabled: false,
      token_printed: false,
    });
    expect(preview.selected_worker?.worker_id).toBe("laptop-zenbookduo");
    expect(preview.rejected_workers.map((worker) => worker.rejection_reasons).flat()).toEqual(
      expect.arrayContaining(["worker_stale", "worker_disabled", "project_access_mismatch", "repo_access_mismatch"]),
    );
    expect(fixtureWorkerRoutingReadiness).toMatchObject({
      execution_enabled: false,
      can_start_one: false,
      can_start_queue: false,
      selected_worker_ready_for_preview_only: true,
      token_printed: false,
    });
  });

  it("models Goal 198 project profiles and selection as preview-only", () => {
    expect(fixtureProjectProfileReviewSummary).toMatchObject({
      schema: "skybridge.project_profile_review_summary.v1",
      project_id: "skybridge-agent-hub",
      validation_status: "valid",
      default_branch: "main",
      no_execution_controls: true,
      token_printed: false,
    });
    expect(fixtureProjectProfileReviewSummary.validation_commands.every((command) => command.executes === false)).toBe(true);
    expect(fixtureProjectSelectionPreview).toMatchObject({
      schema: "skybridge.project_selection_preview.v1",
      mode: "preview",
      selected_project_id: "skybridge-agent-hub",
      project_selection_preview_only: true,
      task_claimed: false,
      task_executed: false,
      worker_loop_started: false,
      queue_execution_enabled: false,
      validation_commands_executed: false,
      token_printed: false,
    });
    expect(fixtureCampaignRunReport.queue_control_readiness.project_profile?.profile_hash).toBe(fixtureProjectSelectionPreview.profile_hash);
  });

  it("derives attention events and fixture-only routes for Goal 193", () => {
    const events = deriveAttentionEvents(fixtureCampaignRunReport);
    expect(events).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          schema: "skybridge.attention_event.v1",
          event_type: "worker_offline",
          attention_level: "action_required",
          token_printed: false,
        }),
        expect.objectContaining({
          event_type: "queue_blocked",
          attention_level: "blocker",
        }),
        expect.objectContaining({
          event_type: "human_approval_required",
        }),
        expect.objectContaining({
          event_type: "active_repo_lock_blocks_queue",
        }),
        expect.objectContaining({
          event_type: "campaign_held",
        }),
        expect.objectContaining({
          event_type: "multi_campaign_conflict",
        }),
        expect.objectContaining({
          event_type: "project_selection_preview_only",
        }),
      ]),
    );

    const model = createAttentionModel(fixtureCampaignRunReport);
    expect(model).toMatchObject({
      schema: "skybridge.attention_model.v1",
      goal_id: "super-198-multi-project-support",
      token_printed: false,
    });
    expect(notificationRoutingMatrix).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ route: "local_fixture_notification", real_external_send: false }),
        expect.objectContaining({ route: "ntfy_placeholder", status: "not_configured", real_external_send: false }),
      ]),
    );
    expect(routeAttentionEvent(events[0])).toMatchObject({
      external_notification_sent: false,
      token_printed: false,
    });
  });

  it("builds filtered event URLs", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValueOnce(jsonResponse({ events: [] }));
    const client = new SkyBridgeClient("http://127.0.0.1:8787/");

    await client.listEvents({
      platform: "codex",
      adapter: "codex-hook",
      severity: "warning",
      type: "approval.requested",
      limit: 25,
      offset: 10
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "http://127.0.0.1:8787/v1/events?platform=codex&adapter=codex-hook&severity=warning&type=approval.requested&limit=25&offset=10"
    );
  });

  it("builds run, detail and notification URLs", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ runs: [] }))
      .mockResolvedValueOnce(jsonResponse({ summary: { run_id: "run/1" }, events: [] }))
      .mockResolvedValueOnce(jsonResponse({ notifications: [] }));
    const client = new SkyBridgeClient("http://localhost:8787");

    await client.listRuns({ status: "failed", goal: "console", limit: 10 });
    await client.getRun("run/1", { limit: 50 });
    await client.listNotifications({ status: "skipped", provider: "placeholder" });

    expect(fetchMock).toHaveBeenNthCalledWith(1, "http://localhost:8787/v1/runs?status=failed&goal=console&limit=10");
    expect(fetchMock).toHaveBeenNthCalledWith(2, "http://localhost:8787/v1/runs/run%2F1?limit=50");
    expect(fetchMock).toHaveBeenNthCalledWith(3, "http://localhost:8787/v1/notifications?status=skipped&provider=placeholder");
  });

  it("returns health and summary responses", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ ok: true, service: "skybridge-server", persistence: "memory", time: "2026-05-21T00:00:00.000Z" }))
      .mockResolvedValueOnce(jsonResponse({ health: {}, totals: { events: 0 }, sources: [] }));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.getHealth()).resolves.toMatchObject({ service: "skybridge-server" });
    await expect(client.getSummary()).resolves.toMatchObject({ sources: [] });
  });

  it("returns derived audit entries", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValueOnce(jsonResponse({
      audit: [{
        audit_id: "audit-1",
        action: "approval.denied",
        actor: "operator",
        source_adapter: "skybridge/approval-api",
        safety_decision: "operator_denied",
        immutable_event_id: "event-1",
        redaction_policy_version: "packages/event-schema/src/redaction-rules.json",
        raw_payload_included: false
      }]
    }));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.listAuditEntries({ run_id: "run-1", action: "approval.denied", limit: 10 })).resolves.toEqual([
      expect.objectContaining({ audit_id: "audit-1", raw_payload_included: false })
    ]);
    expect(fetchMock).toHaveBeenCalledWith("http://localhost:8787/v1/audit?run_id=run-1&action=approval.denied&limit=10");
  });

  it("returns iteration and supervisor status helpers", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ iterations: [{ iteration_id: "iter-1", state: "ci_pending" }] }))
      .mockResolvedValueOnce(jsonResponse({ iteration: { iteration_id: "iter-1", state: "ci_pending", events: [] } }))
      .mockResolvedValueOnce(jsonResponse({ ok: true, raw_prompts_included: false, raw_logs_included: false, iterations: { total: 1, active: 1, blocked: 0 }, recent_iteration_events: [] }))
      .mockResolvedValueOnce(jsonResponse({ action: "repair_ci", iteration_id: "iter-1", pr_number: 12 }));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.listIterations()).resolves.toEqual([expect.objectContaining({ iteration_id: "iter-1" })]);
    await expect(client.getIteration("iter-1")).resolves.toMatchObject({ iteration_id: "iter-1", events: [] });
    await expect(client.getSupervisorStatus()).resolves.toMatchObject({ raw_logs_included: false });
    await expect(client.getSupervisorNextAction()).resolves.toMatchObject({ action: "repair_ci", pr_number: 12 });
  });

  it("returns product dashboard summaries with stable URLs", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ projects: [{ project_id: "skybridge-agent-hub" }] }))
      .mockResolvedValueOnce(jsonResponse({ total: 1, active: 1, blocked: 0, failed: 0, repair_attempts: 0, recent: [] }))
      .mockResolvedValueOnce(jsonResponse({ total: 1, open: 1, merged: 0, blocked: 0, eligible: 1, ci_failed: 0, latest_ci_state: "ci_green", prs: [] }))
      .mockResolvedValueOnce(jsonResponse({ total: 1, sent: 1, skipped: 0, failed: 0, pending: 0, by_severity: {}, providers: [], bootstrap_fallback: { status: "available-manual", script: "notify-bootstrap.ps1", real_send_requires_explicit_send: true }, recent: [] }))
      .mockResolvedValueOnce(jsonResponse({ status: "placeholder", tunnel: { status: "unknown", public_exposure: false }, api: { health: "placeholder", base_publicly_exposed: false }, capabilities: [], related_iterations: [] }))
      .mockResolvedValueOnce(jsonResponse({ enabled_by_default: false, dry_run_default: true, total_prs: 1, eligible: 1, blocked: 0, pending: 0, merged_history: [], decisions: [] }));
    const client = new SkyBridgeClient("http://localhost:8787/");

    await expect(client.listProjects()).resolves.toEqual([expect.objectContaining({ project_id: "skybridge-agent-hub" })]);
    await expect(client.getIterationsSummary()).resolves.toMatchObject({ total: 1 });
    await expect(client.getPrsSummary()).resolves.toMatchObject({ latest_ci_state: "ci_green" });
    await expect(client.getNotificationsSummary()).resolves.toMatchObject({ sent: 1 });
    await expect(client.getHermesSummary()).resolves.toMatchObject({ status: "placeholder" });
    await expect(client.getAutoMergeSummary()).resolves.toMatchObject({ dry_run_default: true });

    expect(fetchMock).toHaveBeenNthCalledWith(1, "http://localhost:8787/v1/projects");
    expect(fetchMock).toHaveBeenNthCalledWith(2, "http://localhost:8787/v1/iterations/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(3, "http://localhost:8787/v1/prs/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(4, "http://localhost:8787/v1/notifications/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(5, "http://localhost:8787/v1/hermes/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(6, "http://localhost:8787/v1/automerge/summary");
  });

  it("builds worker, project, goal and task helper URLs", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ worker: { worker_id: "worker/1" } }))
      .mockResolvedValueOnce(jsonResponse({ worker: { worker_id: "worker/1" } }))
      .mockResolvedValueOnce(jsonResponse({ workers: [] }))
      .mockResolvedValueOnce(jsonResponse({ worker: { worker_id: "worker/1" } }))
      .mockResolvedValueOnce(jsonResponse({ total: 1, online: 1, stale: 0, offline: 0, disabled: 0, workers: [] }))
      .mockResolvedValueOnce(jsonResponse({ project: { project_id: "proj/1" } }))
      .mockResolvedValueOnce(jsonResponse({ project: { project_id: "proj/1" } }))
      .mockResolvedValueOnce(jsonResponse({ goal: { goal_id: "goal/1" } }))
      .mockResolvedValueOnce(jsonResponse({ goals: [] }))
      .mockResolvedValueOnce(jsonResponse({ goal: { goal_id: "goal/1" } }))
      .mockResolvedValueOnce(jsonResponse({ goal: { goal_id: "goal/1" } }))
      .mockResolvedValueOnce(jsonResponse({ task: { task_id: "task/1" } }))
      .mockResolvedValueOnce(jsonResponse({ tasks: [] }))
      .mockResolvedValueOnce(jsonResponse({ tasks: [] }))
      .mockResolvedValueOnce(jsonResponse({ task: { task_id: "task/1" } }))
      .mockResolvedValueOnce(jsonResponse({ task: { task_id: "task/1" } }))
      .mockResolvedValueOnce(jsonResponse({ task: { task_id: "task/1" } }))
      .mockResolvedValueOnce(jsonResponse({ task: { task_id: "task/1" } }))
      .mockResolvedValueOnce(jsonResponse({ task: { task_id: "task/1" } }))
      .mockResolvedValueOnce(jsonResponse({ total: 1, queued: 0, claimed: 0, running: 0, completed: 1, failed: 0, blocked: 0, cancelled: 0, stale: 0 }));
    const client = new SkyBridgeClient("http://localhost:8787/");

    await client.registerWorker({ worker_id: "worker/1", name: "Worker" });
    await client.sendWorkerHeartbeat("worker/1");
    await client.listWorkers();
    await client.getWorker("worker/1");
    await client.getWorkersSummary();
    await client.createProject({ project_id: "proj/1", name: "Project" });
    await client.getProject("proj/1");
    await client.createGoal("proj/1", { goal_id: "goal/1", title: "Goal" });
    await client.listGoals("proj/1");
    await client.getGoal("goal/1");
    await client.updateGoal("goal/1", { status: "completed" });
    await client.createTask({ task_id: "task/1", project_id: "proj/1", title: "Task" });
    await client.listTasks({ project_id: "proj/1", status: "queued" });
    await client.listProjectTasks("proj/1");
    await client.getTask("task/1");
    await client.claimTask("task/1", "worker/1");
    await client.completeTask("task/1", { summary: "done" });
    await client.requeueTask("task/1");
    await client.getTasksSummary();

    expect(fetchMock).toHaveBeenNthCalledWith(1, "http://localhost:8787/v1/workers/register", expect.objectContaining({ method: "POST" }));
    expect(fetchMock).toHaveBeenNthCalledWith(2, "http://localhost:8787/v1/workers/worker%2F1/heartbeat", expect.objectContaining({ method: "POST" }));
    expect(fetchMock).toHaveBeenNthCalledWith(3, "http://localhost:8787/v1/workers");
    expect(fetchMock).toHaveBeenNthCalledWith(4, "http://localhost:8787/v1/workers/worker%2F1");
    expect(fetchMock).toHaveBeenNthCalledWith(5, "http://localhost:8787/v1/workers/summary");
    expect(fetchMock).toHaveBeenNthCalledWith(6, "http://localhost:8787/v1/projects", expect.objectContaining({ method: "POST" }));
    expect(fetchMock).toHaveBeenNthCalledWith(7, "http://localhost:8787/v1/projects/proj%2F1");
    expect(fetchMock).toHaveBeenNthCalledWith(8, "http://localhost:8787/v1/projects/proj%2F1/goals", expect.objectContaining({ method: "POST" }));
    expect(fetchMock).toHaveBeenNthCalledWith(9, "http://localhost:8787/v1/projects/proj%2F1/goals");
    expect(fetchMock).toHaveBeenNthCalledWith(10, "http://localhost:8787/v1/goals/goal%2F1");
    expect(fetchMock).toHaveBeenNthCalledWith(11, "http://localhost:8787/v1/goals/goal%2F1", expect.objectContaining({ method: "PATCH" }));
    expect(fetchMock).toHaveBeenNthCalledWith(12, "http://localhost:8787/v1/tasks", expect.objectContaining({ method: "POST" }));
    expect(fetchMock).toHaveBeenNthCalledWith(13, "http://localhost:8787/v1/tasks?project_id=proj%2F1&status=queued");
    expect(fetchMock).toHaveBeenNthCalledWith(14, "http://localhost:8787/v1/projects/proj%2F1/tasks");
    expect(fetchMock).toHaveBeenNthCalledWith(15, "http://localhost:8787/v1/tasks/task%2F1");
    expect(fetchMock).toHaveBeenNthCalledWith(16, "http://localhost:8787/v1/tasks/task%2F1/claim", expect.objectContaining({ method: "POST" }));
    expect(fetchMock).toHaveBeenNthCalledWith(17, "http://localhost:8787/v1/tasks/task%2F1/complete", expect.objectContaining({ method: "POST" }));
    expect(fetchMock).toHaveBeenNthCalledWith(18, "http://localhost:8787/v1/tasks/task%2F1/requeue", expect.objectContaining({ method: "POST" }));
    expect(fetchMock).toHaveBeenNthCalledWith(19, "http://localhost:8787/v1/tasks/summary");
  });

  it("throws useful errors for non-2xx responses", async () => {
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValueOnce(jsonResponse({ error: "invalid_query" }, 400));
    const client = new SkyBridgeClient("http://localhost:8787");

    await expect(client.listEvents({ limit: 1 })).rejects.toThrow("HTTP 400");
  });
});
