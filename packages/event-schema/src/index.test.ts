import { describe, expect, it } from "vitest";
import {
  createEvent,
  createManualExecutionResult,
  createRuleBasedPlannerDecision,
  fixtureOperatorApprovalGate,
  fixtureOperatorApprovalRequest,
  fixtureOperatorApprovalState,
  fixtureAuditReport,
  fixtureBoincV1ControlledApplyBoundary,
  fixtureBoincV1ControlledTrialStatus,
  fixtureBoincV1ReleaseApproval,
  fixtureBoincV1ReleaseOperatorPolicy,
  fixtureBoincV1ReleaseStatus,
  fixtureBoincV1ReleaseTagPlan,
  fixtureEvidenceRetentionReport,
  fixtureFailureBudgetReport,
  fixtureSafeExportGate,
  fixtureServerApprovedWorkunitStatus,
  fixtureTrustedDocsAutoMergeGate,
  fixtureWorkerHeartbeat,
  fixtureWorkerPairingPreview,
  fixtureWorkerRegistration,
  isNotificationTrigger,
  listAdapterCapabilities,
  ManualTaskAuditSchema,
  ManualTaskProviderListSchema,
  ManualTaskProviderReportSchema,
  ManualTaskQueueSchema,
  ManualTaskResultSchema,
  parseOperatorApprovalRequest,
  parseAuditReport,
  parseBoincV1ControlledTrialStatus,
  parseBoincV1ReleaseStatus,
  parseEvidenceRetentionReport,
  parseEvent,
  parseFailureBudget,
  parseServerApprovedWorkunitStatus,
  parseTrustedDocsAutoMergeGate,
  parseWorkerHeartbeat,
  parseWorkerRegistration,
  redactForTelemetry,
  SharedRedactionRules,
  TASK_TEMPLATE_REGISTRY,
  DraftSubmitPreviewSchema,
  DraftSubmitResultSchema,
  MatlabParameterSweepRunnerSchema,
  MatlabSweepEvidenceSchema,
  MatlabSweepManifestSchema,
  MatlabSweepSummarySchema,
  BoundedGoalLoopSchema,
  GeneratedGoalMetadataSchema,
  GoalAppendReviewSchema,
  LocalGoalGeneratorSchema,
  ManagedDevE2EHandoffSchema,
  ManagedDevPilotSchema,
  MultiGoalLoopSchema,
  TemplateRunnerEvidenceSchema,
  TaskDraftPreviewSchema,
  TaskTemplateRegistrySchema,
  SingleGoalLoopSchema,
  ToolProviderInventorySchema,
  WorkerTemplateRunnerPreviewSchema,
  WorkerTemplateRunnerResultSchema,
  getTaskTemplate,
  listTaskTemplates,
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

  it("models manual task chat and mock queue without execution", () => {
    const now = "2026-06-17T00:00:00.000Z";
    const provider = {
      schema: "skybridge.manual_task_provider.v1",
      provider_id: "mock",
      deterministic: true,
      network_enabled: false,
      hermes_live_call_enabled: false,
      raw_request_persisted: false,
      raw_response_persisted: false,
      token_printed: false,
    } as const;
    const task = {
      schema: "skybridge.manual_task.v1",
      task_id: "manual_fixture",
      status: "succeeded",
      input_preview: "What should be checked next?",
      input_hash: "abc123abc123",
      result_preview: "Mock reply abc123abc123: recorded sanitized local question.",
      result_hash: "def456def456",
      provider_id: "mock",
      provider_status: "mock_default",
      duration_ms: 1,
      error_summary: "",
      live_call_performed: false,
      remote_llm_inference_enabled: false,
      command_text_detected: false,
      prompt_body_persisted: false,
      output_executed: false,
      command_executed: false,
      created_at: now,
      updated_at: now,
      token_printed: false,
    } as const;
    expect(
      ManualTaskQueueSchema.parse({
        schema: "skybridge.manual_task_queue.v1",
        queue_id: "local-manual-task-queue",
        provider,
        tasks: [task],
        state_machine: ["queued", "running", "succeeded", "failed", "blocked", "cancelled"],
        execution_enabled: false,
        worker_execution_started: false,
        workunit_created: false,
        task_created: false,
        task_claim_created: false,
        task_pr_created: false,
        queue_apply_enabled: false,
        remote_execution_enabled: false,
        remote_llm_inference_enabled: false,
        arbitrary_command_enabled: false,
        host_mutation_performed: false,
        prompt_body_persisted: false,
        transcript_body_persisted: false,
        raw_logs_persisted: false,
        updated_at: now,
        token_printed: false,
      }),
    ).toMatchObject({
      provider: { provider_id: "mock", hermes_live_call_enabled: false },
      execution_enabled: false,
      queue_apply_enabled: false,
      token_printed: false,
    });
    expect(
      ManualTaskResultSchema.parse({
        schema: "skybridge.manual_task_result.v1",
        task_id: "manual_fixture",
        provider,
        status: "succeeded",
        result_preview: "Mock reply abc123abc123: recorded sanitized local question.",
        result_hash: "def456def456",
        duration_ms: 1,
        error_summary: "",
        live_call_performed: false,
        remote_llm_inference_enabled: false,
        output_executed: false,
        command_executed: false,
        workunit_created: false,
        task_created: false,
        task_claim_created: false,
        task_pr_created: false,
        queue_apply_enabled: false,
        token_printed: false,
      }),
    ).toMatchObject({ output_executed: false });
    expect(
      ManualTaskAuditSchema.parse({
        schema: "skybridge.manual_task_audit.v1",
        action: "add-question",
        accepted: true,
        task,
        prompt_body_persisted: false,
        token_printed: false,
      }),
    ).toMatchObject({ accepted: true });
  });

  it("models chat-to-task MATLAB draft preview without execution", () => {
    const session = {
      schema: "skybridge.chat_to_task_session.v1",
      session_id: "chat_draft_abc123abc123",
      project_id: "skybridge-agent-hub",
      planner_id: "deterministic-local-chat-to-task.v1",
      input_preview: "MATLAB parameter sweep eta=2..10 h=500/700km P=6/8/10 with summary report.",
      input_hash: "abc123abc123abc123",
      raw_prompt_persisted: false,
      raw_response_persisted: false,
      task_created: false,
      campaign_created: false,
      claim_created: false,
      execution_started: false,
      codex_run_called: false,
      matlab_run_called: false,
      arbitrary_shell_enabled: false,
      token_printed: false,
    } as const;
    const draft = {
      schema: "skybridge.campaign_draft.v1",
      draft_id: "draft_matlab_abc123abc123",
      draft_type: "campaign",
      template_id: "matlab-parameter-sweep.v1",
      project_id: "skybridge-agent-hub",
      title: "Chapter 4 MATLAB parameter sweep",
      summary: "Preview a bounded MATLAB parameter sweep and report request.",
      risk: "local_experiment",
      required_capabilities: ["windows", "powershell", "matlab", "codex"],
      allowed_paths: ["results/skybridge/**", "docs/experiments/**"],
      blocked_paths: [".env", "secrets/**", "deploy/**", ".git/**"],
      validation: ["confirm MATLAB availability", "write outputs only under allowed paths"],
      runner_id: "matlab-parameter-sweep-runner.v1",
      evidence_schema: ["run_manifest", "parameter_matrix", "result_summary", "report_path", "audit_summary"],
      planner_id: "deterministic-local-chat-to-task.v1",
      input_preview: session.input_preview,
      input_hash: session.input_hash,
      inputs: {
        eta_range: [2, 10],
        h_km: [500, 700],
        p_values: [6, 8, 10],
        outputs: ["summary", "report"],
      },
      raw_prompt_persisted: false,
      raw_response_persisted: false,
      task_created: false,
      campaign_created: false,
      claim_created: false,
      execution_started: false,
      codex_run_called: false,
      matlab_run_called: false,
      arbitrary_shell_enabled: false,
      token_printed: false,
    } as const;
    expect(
      TaskDraftPreviewSchema.parse({
        schema: "skybridge.task_draft_preview.v1",
        ok: true,
        status: "preview",
        draft_id: draft.draft_id,
        draft_type: draft.draft_type,
        template_id: draft.template_id,
        project_id: draft.project_id,
        planner_id: draft.planner_id,
        session,
        draft,
        command_text_detected: false,
        unsafe_request_detected: false,
        blockers: [],
        warnings: [],
        next_safe_action: "review_preview_only",
        input_preview: session.input_preview,
        input_hash: session.input_hash,
        raw_prompt_persisted: false,
        raw_response_persisted: false,
        task_created: false,
        campaign_created: false,
        claim_created: false,
        execution_started: false,
        codex_run_called: false,
        matlab_run_called: false,
        arbitrary_shell_enabled: false,
        token_printed: false,
      }),
    ).toMatchObject({
      draft_type: "campaign",
      template_id: "matlab-parameter-sweep.v1",
      execution_started: false,
      matlab_run_called: false,
      codex_run_called: false,
      token_printed: false,
    });
  });

  it("validates the Bootstrap Alpha task template registry without execution support", () => {
    const registry = TaskTemplateRegistrySchema.parse(TASK_TEMPLATE_REGISTRY);
    const templateIds = registry.templates.map((template) => template.template_id);

    expect(templateIds).toEqual(
      expect.arrayContaining([
        "software-docs-task.v1",
        "codex-analysis-report.v1",
        "safe-local-smoke.v1",
        "matlab-parameter-sweep.v1",
        "matlab-result-analysis.v1",
      ]),
    );
    expect(registry.execution_supported).toBe(false);
    expect(registry.task_creation_supported).toBe(false);
    expect(registry.campaign_creation_supported).toBe(false);
    expect(registry.claim_supported).toBe(false);
    expect(registry.codex_run_supported).toBe(false);
    expect(registry.matlab_run_supported).toBe(false);
    expect(registry.arbitrary_shell_enabled).toBe(false);
    expect(registry.token_printed).toBe(false);

    for (const template of listTaskTemplates()) {
      expect(template.template_id).toBeTruthy();
      expect(template.required_capabilities.length).toBeGreaterThan(0);
      expect(template.allowed_paths.length).toBeGreaterThan(0);
      expect(template.blocked_paths.length).toBeGreaterThan(0);
      expect(template.runner_id).toMatch(/\.v1$/);
      expect(template.evidence_schema[0]).toMatch(/^skybridge\..+_evidence\.v1$/);
      expect(template.execution_supported).toBe(false);
      expect(template.task_creation_supported).toBe(false);
      expect(template.campaign_creation_supported).toBe(false);
      expect(template.claim_supported).toBe(false);
      expect(template.codex_run_supported).toBe(false);
      expect(template.matlab_run_supported).toBe(false);
      expect(template.arbitrary_shell_enabled).toBe(false);
      expect(template.token_printed).toBe(false);
    }

    const matlabTemplate = getTaskTemplate("matlab-parameter-sweep.v1");
    expect(matlabTemplate).toMatchObject({
      draft_type: "campaign",
      risk_class: "medium",
      runner_id: "matlab-parameter-sweep-runner.v1",
    });
    expect(matlabTemplate?.allowed_paths).toEqual(
      expect.arrayContaining(["experiments/matlab/**", "results/skybridge/**", "docs/experiments/**"]),
    );
    expect(matlabTemplate?.blocked_paths).toEqual(
      expect.arrayContaining([".env", "secrets/**", "deploy/**", ".git/**", "Cloudflare", "OpenResty", "Authelia"]),
    );
    expect(matlabTemplate?.evidence_schema).toContain("skybridge.matlab_sweep_evidence.v1");
  });

  it("models draft submit preview and result without execution", () => {
    const preview = DraftSubmitPreviewSchema.parse({
      schema: "skybridge.draft_submit_preview.v1",
      ok: true,
      draft_id: "draft_docs_abc123abc123",
      draft_type: "task",
      template_id: "software-docs-task.v1",
      project_id: "skybridge-agent-hub",
      title: "Software Docs Task",
      risk: "low",
      required_capabilities: ["git", "codex"],
      allowed_paths: ["docs/**", "README.md"],
      blocked_paths: [".env", "secrets/**", "deploy/**", ".git/**"],
      runner_id: "software-docs-task-runner.v1",
      evidence_schema: ["skybridge.docs_task_evidence.v1"],
      review_status: "ready_for_confirmation",
      review_reason: "draft_validated_create_queued_records_only_no_execution",
      submitted_by: "local-operator",
      task_created: false,
      campaign_created: false,
      claim_created: false,
      execution_started: false,
      codex_run_called: false,
      matlab_run_called: false,
      worker_loop_started: false,
      arbitrary_shell_enabled: false,
      project_control_unpause: false,
      raw_prompt_persisted: false,
      raw_response_persisted: false,
      token_printed: false,
    });
    expect(preview.task_created).toBe(false);
    expect(preview.execution_started).toBe(false);

    const result = DraftSubmitResultSchema.parse({
      ...preview,
      schema: "skybridge.draft_submit_result.v1",
      review_status: "submitted",
      review_reason: "queued_task_created_no_execution",
      created_task_id: "draft_task_abc123abc123",
      task_created: true,
      campaign_created: false,
      next_safe_action: "hold_for_mg329_worker_runner",
    });
    expect(result.task_created).toBe(true);
    expect(result.claim_created).toBe(false);
    expect(result.worker_loop_started).toBe(false);
    expect(result.token_printed).toBe(false);
  });

  it("models worker template runner preview, result, and evidence safely", () => {
    const preview = WorkerTemplateRunnerPreviewSchema.parse({
      schema: "skybridge.worker_template_runner_preview.v1",
      ok: true,
      mode: "preview",
      worker_id: "worker-mg329",
      project_id: "skybridge-agent-hub",
      task_id: "mg329-safe-local-smoke",
      template_id: "safe-local-smoke.v1",
      runner_id: "safe-local-smoke-runner.v1",
      selected: true,
      eligible: true,
      rejected_reason: "",
      claim_created: false,
      execution_started: false,
      execution_completed: false,
      execution_failed: false,
      evidence_present: false,
      allowed_paths_checked: true,
      blocked_paths_checked: true,
      changed_files: [],
      validation_status: "preview_only",
      result_summary: "Eligible safe local smoke fixture task.",
      pr_created: false,
      codex_run_called: false,
      matlab_run_called: false,
      arbitrary_shell_enabled: false,
      worker_loop_started: false,
      unbounded_run_enabled: false,
      project_control_unpaused: false,
      token_printed: false,
    });
    expect(preview.claim_created).toBe(false);
    expect(preview.execution_started).toBe(false);

    const result = WorkerTemplateRunnerResultSchema.parse({
      ...preview,
      schema: "skybridge.worker_template_runner_result.v1",
      mode: "apply",
      claim_created: true,
      execution_started: true,
      execution_completed: true,
      evidence_present: true,
      validation_status: "passed",
      result_summary: "Fixture runner completed one safe-local-smoke task.",
    });
    expect(result.claim_created).toBe(true);
    expect(result.execution_completed).toBe(true);
    expect(result.codex_run_called).toBe(false);
    expect(result.matlab_run_called).toBe(false);

    const evidence = TemplateRunnerEvidenceSchema.parse({
      schema: "skybridge.template_runner_evidence.v1",
      ok: true,
      worker_id: "worker-mg329",
      project_id: "skybridge-agent-hub",
      task_id: "mg329-safe-local-smoke",
      template_id: "safe-local-smoke.v1",
      runner_id: "safe-local-smoke-runner.v1",
      evidence_schema_id: "skybridge.local_smoke_evidence.v1",
      evidence_path: ".agent/tmp/worker-template-runner/mg329-safe-local-smoke/evidence.json",
      changed_files: [],
      validation_status: "passed",
      result_summary: "Safe fixture evidence only.",
      pr_created: false,
      codex_run_called: false,
      matlab_run_called: false,
      arbitrary_shell_enabled: false,
      worker_loop_started: false,
      unbounded_run_enabled: false,
      project_control_unpaused: false,
      raw_logs_included: false,
      token_printed: false,
    });
    expect(evidence.raw_logs_included).toBe(false);
    expect(evidence.token_printed).toBe(false);
  });

  it("models MG333 MATLAB golden trial runner contracts safely", () => {
    const common = {
      task_id: "live-matlab-golden-task-333-001",
      worker_id: "jerry-win-local-01",
      template_id: "matlab-parameter-sweep.v1" as const,
      runner_id: "matlab-parameter-sweep-runner.v1" as const,
      parameter_grid_summary: "eta=[2,3]; h_km=[500]; P=[6]; combinations=2",
      combination_count: 2,
      output_dir: ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-333-001",
      manifest_path: ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-333-001/manifest.json",
      summary_path: ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-333-001/summary.json",
      metrics_path: ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-333-001/metrics.csv",
      raw_stdout_included: false as const,
      raw_stderr_included: false as const,
      raw_mat_files_uploaded: false as const,
      codex_run_called: false as const,
      arbitrary_shell_enabled: false as const,
      worker_loop_started: false as const,
      token_printed: false as const,
    };

    const runner = MatlabParameterSweepRunnerSchema.parse({
      schema: "skybridge.matlab_parameter_sweep_runner.v1",
      ok: true,
      mode: "preview",
      ...common,
      completed_count: 0,
      failed_count: 0,
      validation_status: "preview_only",
      matlab_available: true,
      would_invoke_matlab: true,
      matlab_invoked: false,
      matlab_exit_code: null,
      blockers: [],
      warnings: [],
    });
    expect(runner.combination_count).toBe(2);
    expect(runner.matlab_invoked).toBe(false);

    const manifest = MatlabSweepManifestSchema.parse({
      schema: "skybridge.matlab_sweep_manifest.v1",
      ...common,
      generated_at: "2026-06-24T00:00:00.000Z",
    });
    expect(manifest.raw_stdout_included).toBe(false);

    const summary = MatlabSweepSummarySchema.parse({
      schema: "skybridge.matlab_sweep_summary.v1",
      task_id: common.task_id,
      worker_id: common.worker_id,
      combination_count: 2,
      completed_count: 2,
      failed_count: 0,
      min_score: 0.024,
      max_score: 0.036,
      mean_score: 0.03,
      validation_status: "passed",
      raw_stdout_included: false,
      raw_stderr_included: false,
      raw_mat_files_uploaded: false,
      codex_run_called: false,
      arbitrary_shell_enabled: false,
      worker_loop_started: false,
      token_printed: false,
    });
    expect(summary.failed_count).toBe(0);

    const evidence = MatlabSweepEvidenceSchema.parse({
      schema: "skybridge.matlab_sweep_evidence.v1",
      ok: true,
      ...common,
      expected_combination_count: 2,
      completed_count: 2,
      failed_count: 0,
      manifest_exists: true,
      summary_exists: true,
      metrics_exists: true,
      validation_status: "passed",
      matlab_invoked: true,
      matlab_exit_code: 0,
      allowed_paths_checked: true,
      blocked_paths_checked: true,
      changed_files: [common.manifest_path, common.summary_path, common.metrics_path],
      result_summary: "Synthetic MATLAB golden trial completed with sanitized evidence.",
      pr_created: false,
      project_control_unpaused: false,
    });
    expect(evidence.matlab_invoked).toBe(true);
    expect(evidence.raw_stderr_included).toBe(false);
    expect(evidence.token_printed).toBe(false);
  });

  it("models Hermes DeepSeek provider preview disabled by default", () => {
    const hermesProvider = {
      schema: "skybridge.manual_task_provider.v1",
      provider_id: "hermes_deepseek",
      status: "preview_no_network",
      configured: false,
      deterministic: false,
      network_enabled: false,
      hermes_live_call_enabled: false,
      remote_llm_inference_enabled: false,
      disabled_by_default: true,
      ci_disabled: true,
      config_values_redacted: true,
      raw_request_persisted: false,
      raw_response_persisted: false,
      token_printed: false,
    } as const;
    const providerList = ManualTaskProviderListSchema.parse({
      schema: "skybridge.manual_task_provider_list.v1",
      default_provider_id: "mock",
      providers: [
        {
          schema: "skybridge.manual_task_provider.v1",
          provider_id: "mock",
          status: "enabled",
          configured: true,
          deterministic: true,
          network_enabled: false,
          hermes_live_call_enabled: false,
          remote_llm_inference_enabled: false,
          disabled_by_default: false,
          config_values_redacted: true,
          raw_request_persisted: false,
          raw_response_persisted: false,
          token_printed: false,
        },
        hermesProvider,
      ],
      live_call_disabled_by_default: true,
      token_printed: false,
    });
    expect(providerList.providers[1]).toMatchObject({
      provider_id: "hermes_deepseek",
      hermes_live_call_enabled: false,
    });
    expect(
      ManualTaskResultSchema.parse({
        schema: "skybridge.manual_task_result.v1",
        task_id: "manual_fixture",
        provider_id: "hermes_deepseek",
        provider_status: "preview_no_network",
        status: "succeeded",
        result_preview: "Hermes DeepSeek preview abc123abc123: live call disabled.",
        result_hash: "abc123abc123",
        duration_ms: 1,
        error_summary: "",
        live_call_performed: false,
        remote_llm_inference_enabled: false,
        output_executed: false,
        command_executed: false,
        workunit_created: false,
        task_created: false,
        task_claim_created: false,
        task_pr_created: false,
        queue_apply_enabled: false,
        token_printed: false,
      }),
    ).toMatchObject({
      provider_id: "hermes_deepseek",
      live_call_performed: false,
      output_executed: false,
    });
    expect(
      ManualTaskProviderReportSchema.parse({
        schema: "skybridge.manual_task_provider_report.v1",
        status: "ready",
        default_provider_id: "mock",
        provider_list: providerList,
        hermes_disabled_by_default: true,
        no_hermes_live_call_in_ci: true,
        raw_request_persisted: false,
        raw_response_persisted: false,
        output_executed: false,
        worker_execution_started: false,
        workunit_created: false,
        task_created: false,
        task_claim_created: false,
        task_pr_created: false,
        queue_apply_enabled: false,
        remote_execution_enabled: false,
        arbitrary_command_enabled: false,
        token_printed: false,
      }),
    ).toMatchObject({ hermes_disabled_by_default: true });
  });

  it("models server-mediated Hermes manual task provider without local secrets or execution", () => {
    const serverProvider = {
      schema: "skybridge.manual_task_provider.v1",
      provider_id: "skybridge_server_hermes",
      status: "disabled_missing_server_config",
      configured: false,
      deterministic: false,
      network_enabled: false,
      hermes_live_call_enabled: false,
      server_mediated_llm_inference_enabled: false,
      cloud_hermes_provider_enabled: false,
      remote_llm_inference_enabled: false,
      disabled_by_default: true,
      config_values_redacted: true,
      raw_request_persisted: false,
      raw_response_persisted: false,
      token_printed: false,
    } as const;
    const providerList = ManualTaskProviderListSchema.parse({
      schema: "skybridge.manual_task_provider_list.v1",
      default_provider_id: "mock",
      providers: [
        {
          schema: "skybridge.manual_task_provider.v1",
          provider_id: "mock",
          status: "enabled",
          configured: true,
          deterministic: true,
          network_enabled: false,
          hermes_live_call_enabled: false,
          remote_llm_inference_enabled: false,
          disabled_by_default: false,
          config_values_redacted: true,
          raw_request_persisted: false,
          raw_response_persisted: false,
          token_printed: false,
        },
        serverProvider,
        {
          schema: "skybridge.manual_task_provider.v1",
          provider_id: "hermes_deepseek",
          status: "deprecated_preview_no_network",
          configured: false,
          deterministic: false,
          network_enabled: false,
          hermes_live_call_enabled: false,
          remote_llm_inference_enabled: false,
          disabled_by_default: true,
          deprecated: true,
          preview_only: true,
          config_values_redacted: true,
          raw_request_persisted: false,
          raw_response_persisted: false,
          token_printed: false,
        },
      ],
      live_call_disabled_by_default: true,
      token_printed: false,
    });
    expect(providerList.providers.map((provider) => provider.provider_id)).toEqual([
      "mock",
      "skybridge_server_hermes",
      "hermes_deepseek",
    ]);
    expect(
      ManualTaskResultSchema.parse({
        schema: "skybridge.manual_task_result.v1",
        task_id: "manual_fixture",
        provider_id: "skybridge_server_hermes",
        provider_status: "disabled_missing_server_config",
        status: "blocked",
        result_preview: "SkyBridge server Hermes blocked: missing server config.",
        result_hash: "abc123abc123",
        duration_ms: 1,
        error_summary: "missing_server_config",
        server_mediated_llm_inference_enabled: false,
        cloud_hermes_provider_enabled: false,
        live_call_performed: false,
        remote_llm_inference_enabled: false,
        output_executed: false,
        command_executed: false,
        workunit_created: false,
        task_created: false,
        task_claim_created: false,
        task_pr_created: false,
        remote_execution_enabled: false,
        arbitrary_command_enabled: false,
        queue_apply_enabled: false,
        token_printed: false,
      }),
    ).toMatchObject({
      provider_id: "skybridge_server_hermes",
      output_executed: false,
      token_printed: false,
    });
  });

  it("models local tool provider inventory without execution", () => {
    const inventory = ToolProviderInventorySchema.parse({
      schema: "skybridge.tool_provider.v1",
      generated_at: "2026-06-28T00:00:00.000Z",
      host_os: "Windows",
      host_name_safe: "host-fixture",
      project_id: "skybridge-agent-hub",
      provider_inventory: "fixture",
      providers: [
        {
          provider_id: "direct-local",
          provider_type: "direct",
          display_name: "Direct Local Provider",
          status: "available",
          tools: ["powershell", "git", "pnpm", "codex", "matlab"],
          default_for_tools: ["codex", "matlab"],
          execution_enabled: false,
          notes: ["Default provider for fixed local runner paths."],
          warnings: [],
          blockers: [],
        },
        {
          provider_id: "hermes-optional",
          provider_type: "hermes",
          display_name: "Hermes Optional Provider",
          status: "unavailable",
          tools: ["hermes"],
          default_for_tools: [],
          execution_enabled: false,
          notes: ["Planner/gate/provider only when configured."],
          warnings: ["fixture_not_configured"],
          blockers: [],
        },
        {
          provider_id: "mcp-disabled",
          provider_type: "mcp",
          display_name: "MCP Provider",
          status: "future",
          tools: ["mcp"],
          default_for_tools: [],
          execution_enabled: false,
          notes: ["Future/disabled until explicitly enabled."],
          warnings: [],
          blockers: [],
        },
      ],
      tools: [
        {
          tool_id: "codex",
          display_name: "Codex CLI",
          provider_id: "direct-local",
          detection_method: "fixture",
          executable_path_safe: "%PATH%/codex.cmd",
          version_summary_safe: "fixture-detected",
          status: "detected",
          can_preview: true,
          can_execute_now: false,
          requires_exact_confirmation: true,
          requires_template: true,
          requires_allowlist: true,
          warnings: [],
          blockers: [],
        },
        {
          tool_id: "matlab",
          display_name: "MATLAB",
          provider_id: "direct-local",
          detection_method: "fixture",
          executable_path_safe: "",
          version_summary_safe: "fixture-missing",
          status: "missing",
          can_preview: true,
          can_execute_now: false,
          requires_exact_confirmation: true,
          requires_template: true,
          requires_allowlist: true,
          warnings: [],
          blockers: ["tool_missing"],
        },
      ],
      defaults: {
        codex: "direct-local",
        matlab: "direct-local",
        hermes: "hermes-optional",
        mcp: "mcp-disabled",
      },
      disabled_capabilities: [
        "general_shell_provider",
        "arbitrary_prompt_provider",
        "arbitrary_matlab_provider",
        "mcp_execution",
      ],
      warnings: ["fixture_inventory"],
      blockers: [],
      execution_allowed: false,
      task_created: false,
      task_claimed: false,
      execution_started: false,
      codex_run_called: false,
      matlab_run_called: false,
      hermes_run_called: false,
      mcp_run_called: false,
      worker_loop_started: false,
      project_control_unpaused: false,
      token_printed: false,
    });

    expect(inventory.schema).toBe("skybridge.tool_provider.v1");
    expect(inventory.defaults.codex).toBe("direct-local");
    expect(inventory.execution_allowed).toBe(false);
    expect(inventory.codex_run_called).toBe(false);
    expect(inventory.matlab_run_called).toBe(false);
    expect(inventory.hermes_run_called).toBe(false);
    expect(inventory.mcp_run_called).toBe(false);
    expect(inventory.token_printed).toBe(false);
  });

  it("models single-goal loop completion with sanitized evidence", () => {
    const safety = {
      codex_run_called: false,
      matlab_run_called: false,
      hermes_run_called: false,
      mcp_run_called: false,
      arbitrary_shell_enabled: false,
      worker_loop_started: false,
      project_control_unpaused: false,
      token_printed: false,
    };
    const evidence = {
      schema: "skybridge.single_goal_loop_evidence.v1",
      campaign_id: "local-cloud-single-goal-fixture",
      step_id: "safe-local-smoke-step",
      task_id: "single-goal-safe-local-smoke-fixture-task",
      worker_id: "mg352-fixture-worker",
      template_id: "safe-local-smoke.v1",
      runner_id: "safe-local-smoke-runner.v1",
      provider_inventory_checked: true,
      direct_provider_available: true,
      task_claimed_count: 1,
      execution_started: true,
      execution_completed: true,
      execution_failed: false,
      changed_files: [],
      ...safety,
    };
    const loop = SingleGoalLoopSchema.parse({
      schema: "skybridge.single_goal_loop.v1",
      generated_at: "2026-06-28T00:00:00.000Z",
      mode: "fixture",
      project_id: "skybridge-agent-hub",
      campaign_id: "local-cloud-single-goal-fixture",
      step_id: "safe-local-smoke-step",
      task_id: "single-goal-safe-local-smoke-fixture-task",
      worker_id: "mg352-fixture-worker",
      provider_inventory_checked: true,
      direct_provider_available: true,
      template_id: "safe-local-smoke.v1",
      runner_id: "safe-local-smoke-runner.v1",
      preview_only: false,
      apply_confirmed: true,
      task_created: true,
      task_claimed: true,
      execution_started: true,
      execution_completed: true,
      execution_failed: false,
      evidence_attached: true,
      step_completed: true,
      campaign_completed: true,
      blockers: [],
      warnings: ["fixture_mode"],
      safety_flags: safety,
      task_created_count: 1,
      task_claimed_count: 1,
      execution_completed_count: 1,
      evidence,
      ...safety,
    });

    expect(loop.schema).toBe("skybridge.single_goal_loop.v1");
    expect(loop.evidence?.schema).toBe("skybridge.single_goal_loop_evidence.v1");
    expect(loop.task_claimed_count).toBe(1);
    expect(loop.codex_run_called).toBe(false);
    expect(loop.matlab_run_called).toBe(false);
    expect(loop.hermes_run_called).toBe(false);
    expect(loop.mcp_run_called).toBe(false);
    expect(loop.token_printed).toBe(false);
  });

  it("models multi-goal loop one-step completion with sanitized evidence", () => {
    const safety = {
      codex_run_called: false,
      matlab_run_called: false,
      hermes_run_called: false,
      mcp_run_called: false,
      arbitrary_shell_enabled: false,
      worker_loop_started: false,
      project_control_unpaused: false,
      token_printed: false,
    };
    const evidence = {
      schema: "skybridge.multi_goal_loop_evidence.v1",
      campaign_id: "local-cloud-static-multi-goal-fixture",
      step_id: "safe-local-smoke-step-353-001",
      task_id: "static-multi-goal-safe-task-fixture-353-001",
      worker_id: "mg353-fixture-worker",
      template_id: "safe-local-smoke.v1",
      runner_id: "safe-local-smoke-runner.v1",
      provider_inventory_checked: true,
      direct_provider_available: true,
      task_claimed_count: 1,
      execution_started: true,
      execution_completed: true,
      execution_failed: false,
      changed_files: [],
      produced_artifacts_safe: [],
      validation_summary_safe: "fixture safe-local-smoke completed",
      ...safety,
    };
    const loop = MultiGoalLoopSchema.parse({
      schema: "skybridge.multi_goal_loop.v1",
      generated_at: "2026-06-28T00:00:00.000Z",
      mode: "fixture",
      project_id: "skybridge-agent-hub",
      campaign_id: "local-cloud-static-multi-goal-fixture",
      worker_id: "mg353-fixture-worker",
      current_step_id: "safe-local-smoke-step-353-001",
      next_step_id: "matlab-golden-step-353-002",
      steps: [
        {
          step_id: "safe-local-smoke-step-353-001",
          order: 1,
          state: "completed",
          template_id: "safe-local-smoke.v1",
          runner_id: "safe-local-smoke-runner.v1",
          task_id: "static-multi-goal-safe-task-fixture-353-001",
          dependencies: [],
          dependency_status: "complete",
          provider_required: "direct",
          provider_available: true,
          can_preview: true,
          can_apply_next: false,
          evidence_attached: true,
          completed: true,
          failed: false,
          held: false,
          blockers: [],
          warnings: [],
        },
        {
          step_id: "matlab-golden-step-353-002",
          order: 2,
          state: "ready",
          template_id: "matlab-parameter-sweep.v1",
          runner_id: "matlab-parameter-sweep-runner.v1",
          task_id: "static-multi-goal-matlab-task-fixture-353-002",
          dependencies: ["safe-local-smoke-step-353-001"],
          dependency_status: "ready",
          provider_required: "matlab",
          provider_available: true,
          can_preview: true,
          can_apply_next: true,
          evidence_attached: false,
          completed: false,
          failed: false,
          held: false,
          blockers: [],
          warnings: ["fixture_mode_no_matlab_invocation"],
        },
        {
          step_id: "codex-report-step-353-003",
          order: 3,
          state: "pending",
          template_id: "codex-analysis-report.v1",
          runner_id: "codex-analysis-report-runner.v1",
          task_id: "static-multi-goal-codex-task-fixture-353-003",
          dependencies: ["matlab-golden-step-353-002"],
          dependency_status: "blocked",
          provider_required: "codex",
          provider_available: true,
          can_preview: true,
          can_apply_next: false,
          evidence_attached: false,
          completed: false,
          failed: false,
          held: false,
          blockers: ["dependency_not_complete:matlab-golden-step-353-002"],
          warnings: ["fixture_mode_no_codex_invocation"],
        },
      ],
      provider_inventory_checked: true,
      direct_provider_available: true,
      preview_only: false,
      apply_confirmed: true,
      max_steps: 1,
      selected_step_count: 1,
      selected_task_count: 1,
      task_created_count: 1,
      task_claimed_count: 1,
      execution_started_count: 1,
      execution_completed_count: 1,
      execution_failed_count: 0,
      evidence_attached_count: 1,
      step_completed_count: 1,
      campaign_completed: false,
      campaign_held: false,
      blockers: [],
      warnings: ["fixture_mode"],
      safety_flags: safety,
      evidence,
      ...safety,
    });

    expect(loop.schema).toBe("skybridge.multi_goal_loop.v1");
    expect(loop.steps.map((step) => step.template_id)).toEqual([
      "safe-local-smoke.v1",
      "matlab-parameter-sweep.v1",
      "codex-analysis-report.v1",
    ]);
    expect(loop.evidence?.schema).toBe("skybridge.multi_goal_loop_evidence.v1");
    expect(loop.selected_step_count).toBe(1);
    expect(loop.hermes_run_called).toBe(false);
    expect(loop.mcp_run_called).toBe(false);
    expect(loop.worker_loop_started).toBe(false);
    expect(loop.token_printed).toBe(false);
  });

  it("models local goal generator metadata and sanitized evidence", () => {
    const safety = {
      import_performed: false,
      approval_performed: false,
      append_performed: false,
      task_created: false,
      task_claimed: false,
      execution_started: false,
      worker_loop_started: false,
      project_control_unpaused: false,
      matlab_run_called: false,
      hermes_run_called: false,
      mcp_run_called: false,
      raw_prompt_persisted: false,
      raw_response_persisted: false,
      raw_stdout_persisted: false,
      raw_stderr_persisted: false,
      token_printed: false,
    };
    const metadata = GeneratedGoalMetadataSchema.parse({
      schema: "skybridge.generated_goal_metadata.v1",
      goal_id: "generated-docs-validation-goal-354-fixture",
      title: "Generated Docs Validation Goal 354 Fixture",
      order: 1,
      risk: "low",
      task_type: "docs-validation",
      allowed_task_types: ["docs-validation", "local-smoke"],
      blocked_task_types: ["task-execution", "worker-loop"],
      requires: ["human review"],
      expected_outputs: ["one markdown goal proposal"],
      advance_gate: {
        human_review_required: true,
        import_allowed: false,
        execution_allowed: false,
      },
      generated_by: "skybridge-local-goal-generator",
      generation_provider: "fixture",
      source_campaign_id: "local-goal-generator-fixture-354",
      source_project_id: "skybridge-agent-hub",
      goal_budget_remaining: 1,
      human_review_required: true,
      import_allowed: false,
      execution_allowed: false,
      token_printed: false,
    });
    const generator = LocalGoalGeneratorSchema.parse({
      schema: "skybridge.local_goal_generator.v1",
      generated_at: "2026-06-28T00:00:00.000Z",
      mode: "fixture",
      project_id: "skybridge-agent-hub",
      campaign_id: "local-goal-generator-fixture-354",
      goal_budget_remaining: 1,
      provider_inventory_checked: true,
      direct_provider_available: true,
      codex_detected: false,
      codex_generation_requested: false,
      codex_generation_called: false,
      codex_generation_succeeded: false,
      generated_goal_id: metadata.goal_id,
      generated_goal_title: metadata.title,
      generated_goal_path_safe: ".agent/tmp/generated-goals/fixture/generated-goal-354-fixture.md",
      generated_goal_hash: "0".repeat(64),
      generated_goal_schema_valid: true,
      generated_goal_safety_valid: true,
      proposed_goal_written: true,
      blockers: [],
      warnings: ["fixture_mode_no_codex_invocation"],
      safety_flags: safety,
      evidence: {
        schema: "skybridge.local_goal_generator_evidence.v1",
        generated_at: "2026-06-28T00:00:00.000Z",
        provider_inventory_checked: true,
        direct_provider_available: true,
        codex_detected: false,
        codex_generation_called: false,
        generated_goal_path_safe: ".agent/tmp/generated-goals/fixture/generated-goal-354-fixture.md",
        generated_goal_hash: "0".repeat(64),
        generated_goal_valid: true,
        ...safety,
      },
      ...safety,
    });

    expect(metadata.human_review_required).toBe(true);
    expect(metadata.import_allowed).toBe(false);
    expect(metadata.execution_allowed).toBe(false);
    expect(generator.schema).toBe("skybridge.local_goal_generator.v1");
    expect(generator.evidence.raw_prompt_persisted).toBe(false);
    expect(generator.task_created).toBe(false);
    expect(generator.worker_loop_started).toBe(false);
    expect(generator.token_printed).toBe(false);
  });

  it("models goal append review metadata without execution", () => {
    const safety = {
      task_created: false,
      task_claimed: false,
      execution_started: false,
      codex_run_called: false,
      matlab_run_called: false,
      hermes_run_called: false,
      mcp_run_called: false,
      worker_loop_started: false,
      project_control_unpaused: false,
      raw_prompt_persisted: false,
      raw_response_persisted: false,
      raw_stdout_persisted: false,
      raw_stderr_persisted: false,
      token_printed: false,
    };
    const review = GoalAppendReviewSchema.parse({
      schema: "skybridge.goal_append_review.v1",
      generated_at: "2026-06-28T00:00:00.000Z",
      mode: "fixture",
      project_id: "skybridge-agent-hub",
      campaign_id: "goal-append-fixture-campaign-355",
      candidate_path_safe: ".agent/tmp/goal-append/fixture/generated-goal-355-fixture.md",
      candidate_hash: "1".repeat(64),
      expected_hash: "1".repeat(64),
      hash_matches: true,
      generated_goal_id: "generated-goal-355-fixture",
      generated_goal_title: "Generated Goal 355 Fixture",
      metadata_valid: true,
      safety_valid: true,
      human_review_required: true,
      import_allowed: false,
      execution_allowed: false,
      review_state: "appended",
      approved: true,
      rejected: false,
      approval_reason_safe: "fixture approval",
      reject_reason_safe: "",
      append_preview_valid: true,
      append_applied: true,
      appended_step_id: "appended-generated-goal-355-fixture-step",
      appended_step_order: 1,
      appended_step_state: "pending",
      goal_budget_remaining_before: 1,
      goal_budget_remaining_after: 0,
      import_performed: true,
      approval_performed: false,
      append_performed: true,
      blockers: [],
      warnings: [],
      evidence: {
        schema: "skybridge.goal_append_evidence.v1",
        generated_at: "2026-06-28T00:00:00.000Z",
        campaign_id: "goal-append-fixture-campaign-355",
        generated_goal_id: "generated-goal-355-fixture",
        candidate_hash: "1".repeat(64),
        reviewed_hash: "1".repeat(64),
        appended_step_id: "appended-generated-goal-355-fixture-step",
        appended_step_order: 1,
        goal_budget_remaining_before: 1,
        goal_budget_remaining_after: 0,
        validation_summary_safe: "candidate approved and appended as non-executed metadata",
        import_performed: true,
        approval_performed: false,
        append_performed: true,
        ...safety,
      },
      ...safety,
    });

    expect(review.schema).toBe("skybridge.goal_append_review.v1");
    expect(review.append_performed).toBe(true);
    expect(review.task_created).toBe(false);
    expect(review.task_claimed).toBe(false);
    expect(review.execution_started).toBe(false);
    expect(review.worker_loop_started).toBe(false);
    expect(review.token_printed).toBe(false);
  });

  it("models bounded goal loop one-action policy", () => {
    const safety = {
      codex_generation_called: false,
      codex_run_called: false,
      matlab_run_called: false,
      hermes_run_called: false,
      mcp_run_called: false,
      arbitrary_shell_enabled: false,
      worker_loop_started: false,
      project_control_unpaused: false,
      appended_step_executed: false,
      raw_prompt_persisted: false,
      raw_response_persisted: false,
      raw_stdout_persisted: false,
      raw_stderr_persisted: false,
      token_printed: false,
    };
    const loop = BoundedGoalLoopSchema.parse({
      schema: "skybridge.bounded_goal_loop.v1",
      generated_at: "2026-06-28T00:00:00.000Z",
      mode: "fixture",
      project_id: "skybridge-agent-hub",
      campaign_id: "bounded-loop-fixture-ready-step-356",
      worker_id: "fixture-worker-356",
      goal_budget_limit: 1,
      goal_budget_remaining_before: 1,
      goal_budget_remaining_after: 1,
      max_actions_per_run: 1,
      max_steps_per_run: 1,
      max_generated_goals_per_run: 1,
      selected_action: "execute_ready_step",
      selected_action_reason: "ready_step_has_priority",
      preview_only: false,
      apply_confirmed: true,
      provider_inventory_checked: true,
      direct_provider_available: true,
      ready_step_detected: true,
      reviewed_candidate_detected: false,
      generated_candidate_detected: false,
      selected_step_id: "bounded-loop-safe-step-356-001",
      selected_task_id: "bounded-loop-safe-task-356-001",
      selected_candidate_path_safe: "",
      selected_candidate_hash: "",
      generated_goal_id: "",
      generated_goal_path_safe: "",
      appended_step_id: "",
      appended_step_state: "",
      action_performed: true,
      action_count: 1,
      task_created: true,
      task_claimed: true,
      execution_started: true,
      execution_completed: true,
      evidence_attached: true,
      step_completed: true,
      goal_generated: false,
      goal_reviewed: false,
      goal_appended: false,
      campaign_completed: false,
      campaign_held: false,
      task_created_count: 1,
      task_claimed_count: 1,
      execution_started_count: 1,
      execution_completed_count: 1,
      goal_generated_count: 0,
      goal_appended_count: 0,
      blockers: [],
      warnings: [],
      safety_flags: safety,
      evidence: {
        schema: "skybridge.bounded_goal_loop_evidence.v1",
        generated_at: "2026-06-28T00:00:00.000Z",
        campaign_id: "bounded-loop-fixture-ready-step-356",
        selected_action: "execute_ready_step",
        selected_action_reason: "ready_step_has_priority",
        goal_budget_remaining_before: 1,
        goal_budget_remaining_after: 1,
        selected_step_id: "bounded-loop-safe-step-356-001",
        selected_task_id: "bounded-loop-safe-task-356-001",
        generated_goal_id: "",
        generated_goal_hash: "",
        appended_step_id: "",
        task_created: true,
        task_claimed: true,
        execution_started: true,
        execution_completed: true,
        goal_generated: false,
        goal_appended: false,
        ...safety,
      },
      ...safety,
    });

    expect(loop.schema).toBe("skybridge.bounded_goal_loop.v1");
    expect(loop.selected_action).toBe("execute_ready_step");
    expect(loop.action_count).toBe(1);
    expect(loop.goal_generated).toBe(false);
    expect(loop.goal_appended).toBe(false);
    expect(loop.worker_loop_started).toBe(false);
    expect(loop.token_printed).toBe(false);
  });

  it("models managed development pilot human-review hold without merge", () => {
    const safety = {
      auto_merge_enabled: false,
      merge_performed: false,
      release_created: false,
      tag_created: false,
      asset_uploaded: false,
      deploy_mutation_requested: false,
      task_created: false,
      task_claimed: false,
      worker_loop_started: false,
      codex_generation_called: false,
      codex_run_called: false,
      matlab_run_called: false,
      hermes_run_called: false,
      mcp_run_called: false,
      arbitrary_shell_enabled: false,
      project_control_unpaused: false,
      token_printed: false,
    };
    const pilot = ManagedDevPilotSchema.parse({
      ...safety,
      schema: "skybridge.managed_dev_pilot.v1",
      generated_at: "2026-06-28T00:00:00.000Z",
      mode: "fixture",
      project_id: "skybridge-agent-hub",
      campaign_id: "managed-dev-fixture-campaign-357",
      goal_id: "managed-dev-docs-smoke-goal-357-fixture",
      branch_name: "codex/mega-357-managed-dev-pr-pilot-fixture",
      base_branch: "main",
      selected_change_kind: "docs-note-and-smoke-fixture",
      allowed_paths: [
        "docs/orchestrator/",
        "docs/dev/",
        "scripts/powershell/smoke-managed-dev-",
      ],
      max_changed_files: 5,
      preview_only: false,
      apply_confirmed: true,
      branch_created: true,
      files_changed: 2,
      changed_files: [
        "docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT.md",
        "scripts/powershell/smoke-managed-dev-pilot-fixture.ps1",
      ],
      local_validations_run: true,
      local_validations_passed: true,
      draft_pr_requested: false,
      draft_pr_created: false,
      pr_number: 0,
      pr_url_safe: "",
      pr_ci_observed: false,
      pr_ci_status: "simulated_skipped",
      held_for_human_review: true,
      git_available: true,
      gh_available: true,
      git_detection_method: "fixture",
      gh_detection_method: "fixture",
      git_path_safe: "git",
      gh_path_safe: "gh",
      git_blocker: "",
      gh_blocker: "",
      provider_inventory_checked: false,
      controller_native_git_used: true,
      controller_native_gh_used: false,
      manual_fallback_used: false,
      pilot_branch_pushed: false,
      draft_pr_created_by_controller: false,
      draft_pr_number: 0,
      draft_pr_url_safe: "",
      ci_observed_by_controller: false,
      blockers: [],
      warnings: ["fixture_mode_no_real_branch_or_pr"],
      safety_flags: safety,
      evidence: {
        schema: "skybridge.managed_dev_pilot_evidence.v1",
        generated_at: "2026-06-28T00:00:00.000Z",
        branch_name: "codex/mega-357-managed-dev-pr-pilot-fixture",
        base_branch: "main",
        changed_files: [
          "docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT.md",
          "scripts/powershell/smoke-managed-dev-pilot-fixture.ps1",
        ],
        validation_summary_safe: "fixture validations simulated",
        draft_pr_created: false,
        pr_number: 0,
        pr_url_safe: "",
        ci_status: "simulated_skipped",
        held_for_human_review: true,
        git_available: true,
        gh_available: true,
        git_detection_method: "fixture",
        gh_detection_method: "fixture",
        git_blocker: "",
        gh_blocker: "",
        provider_inventory_checked: false,
        controller_native_git_used: true,
        controller_native_gh_used: false,
        manual_fallback_used: false,
        pilot_branch_pushed: false,
        draft_pr_created_by_controller: false,
        ci_observed_by_controller: false,
        auto_merge_enabled: false,
        merge_performed: false,
        release_created: false,
        tag_created: false,
        asset_uploaded: false,
        raw_logs_persisted: false,
        raw_stdout_persisted: false,
        raw_stderr_persisted: false,
        secrets_persisted: false,
        token_printed: false,
      },
    });

    expect(pilot.schema).toBe("skybridge.managed_dev_pilot.v1");
    expect(pilot.draft_pr_created).toBe(false);
    expect(pilot.held_for_human_review).toBe(true);
    expect(pilot.auto_merge_enabled).toBe(false);
    expect(pilot.merge_performed).toBe(false);
    expect(pilot.release_created).toBe(false);
    expect(pilot.git_available).toBe(true);
    expect(pilot.gh_available).toBe(true);
    expect(pilot.manual_fallback_used).toBe(false);
    expect(pilot.token_printed).toBe(false);
  });

  it("models managed dev E2E handoff freeze reports", () => {
    const safety = {
      release_created: false,
      tag_created: false,
      asset_uploaded: false,
      auto_merge_enabled: false,
      worker_loop_started: false,
      queue_runner_started: false,
      task_created: false,
      task_claimed: false,
      codex_run_called: false,
      matlab_run_called: false,
      hermes_run_called: false,
      mcp_run_called: false,
      project_control_unpaused: false,
      token_printed: false,
    };
    const handoff = ManagedDevE2EHandoffSchema.parse({
      ...safety,
      schema: "skybridge.managed_dev_e2e_handoff.v1",
      generated_at: "2026-06-29T00:00:00.000Z",
      expected_commit: "961b492fabdcc7a737043e83d906d6c8d3f4bf38",
      expected_cloud_image:
        "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-961b492fabdcc7a737043e83d906d6c8d3f4bf38",
      current_branch: "main",
      git_clean: true,
      git_aligned: true,
      cloud_health: "ok",
      cloud_version: "961b492fabdcc7a737043e83d906d6c8d3f4bf38",
      cloud_parity: "ok",
      capability_matrix: [
        {
          milestone: "M8",
          name: "Campaign-Driven Managed Dev E2E",
          status: "complete",
          manual_script: "scripts/powershell/manual-managed-dev-campaign-test.ps1",
          evidence_summary: "PR #279 merged after the human review gate.",
        },
      ],
      required_docs_present: true,
      required_scripts_present: true,
      required_smokes_present: true,
      open_pr_summary: [],
      safety_flags: safety,
      blockers: [],
      warnings: [],
    });

    expect(handoff.schema).toBe("skybridge.managed_dev_e2e_handoff.v1");
    expect(handoff.git_clean).toBe(true);
    expect(handoff.capability_matrix).toHaveLength(1);
    expect(handoff.auto_merge_enabled).toBe(false);
    expect(handoff.token_printed).toBe(false);
  });

  it("models Goal 218 worker control-plane contracts without execution", () => {
    expect(parseWorkerRegistration(fixtureWorkerRegistration)).toMatchObject({
      schema: "skybridge.worker_registration.v1",
      execution_enabled: false,
      queue_apply_enabled: false,
      remote_execution_enabled: false,
      arbitrary_command_enabled: false,
      pairing_code_raw_persisted: false,
      token_printed: false,
    });
    expect(fixtureWorkerPairingPreview).toMatchObject({
      schema: "skybridge.worker_pairing_preview.v1",
      pairing_preview_only: true,
      execution_enabled: false,
      remote_execution_enabled: false,
      arbitrary_command_enabled: false,
      token_printed: false,
    });
    expect(parseWorkerHeartbeat(fixtureWorkerHeartbeat)).toMatchObject({
      schema: "skybridge.worker_heartbeat.v1",
      active_tasks: 0,
      stale_leases: 0,
      runner_lock: "none",
      token_printed: false,
    });
  });

  it("models Goal 218 operator approval as non-executing and gated", () => {
    expect(parseOperatorApprovalRequest(fixtureOperatorApprovalRequest)).toMatchObject({
      schema: "skybridge.operator_approval_request.v1",
      max_parallel_repo_mutations: 1,
      resource_gate_required: true,
      human_review_required: true,
      finalizer_required: true,
      token_printed: false,
    });
    expect(fixtureOperatorApprovalState).toMatchObject({
      schema: "skybridge.operator_approval_state.v1",
      approval_state: "pending",
      execution_enabled: false,
      remote_execution_enabled: false,
      arbitrary_command_enabled: false,
    });
    expect(fixtureOperatorApprovalGate).toMatchObject({
      allowed_to_execute: false,
      approval_does_not_execute: true,
      generic_bounded_queue_apply_enabled: false,
      remote_arbitrary_command_dispatch_enabled: false,
      token_printed: false,
    });
  });

  it("models Goal 219 failure budget without silent retry", () => {
    expect(parseFailureBudget(fixtureFailureBudgetReport.policy)).toMatchObject({
      schema: "skybridge.failure_budget.v1",
      retry_requires_explicit_authorization: true,
      replacement_requires_no_mutation_classification: true,
      no_silent_rerun: true,
      no_retry_after_pr_created: true,
      no_retry_after_raw_artifact: true,
      no_retry_after_secret_detected: true,
      token_printed: false,
    });
    expect(fixtureFailureBudgetReport.retry_gate).toMatchObject({
      retry_allowed: false,
      automatic_retry_allowed: false,
      explicit_operator_authorization_required: true,
    });
    expect(fixtureFailureBudgetReport.replacement_gate).toMatchObject({
      automatic_replacement_allowed: false,
      requires_no_mutation_classification: true,
    });
  });

  it("models Goal 219 safe evidence retention and hash chain", () => {
    const report = parseEvidenceRetentionReport(fixtureEvidenceRetentionReport);
    expect(report.schema).toBe("skybridge.evidence_retention_report.v1");
    expect(report.hash_chain.schema).toBe("skybridge.evidence_hash_chain.v1");
    expect(report.entries.every((entry) => entry.raw_artifact === false)).toBe(true);
    expect(report.entries.every((entry) => entry.secret_detected === false)).toBe(true);
    expect(report.export_summary.raw_artifact_count).toBe(0);
    expect(report.token_printed).toBe(false);
  });

  it("models Goal 219 audit, redaction, and safe export gates", () => {
    const report = parseAuditReport(fixtureAuditReport);
    expect(report.audit_trail.raw_payload_included).toBe(false);
    expect(report.redaction_scan.passed).toBe(true);
    expect(report.safe_export_gate).toMatchObject({
      safe_to_export: true,
      raw_prompt_persisted: false,
      raw_transcript_persisted: false,
      raw_stdout_persisted: false,
      raw_stderr_persisted: false,
      raw_logs_persisted: false,
      authorization_persisted: false,
      token_printed: false,
    });
    expect(fixtureSafeExportGate.token_printed).toBe(false);
  });

  it("models Goal 220 BOINC-like v1 release gate without default execution", () => {
    const status = parseBoincV1ReleaseStatus(fixtureBoincV1ReleaseStatus);
    expect(status.schema).toBe("skybridge.boinc_v1_release_status.v1");
    expect(status.gate.gate_result).toBe("pass");
    expect(status.gate.can_execute_now).toBe(false);
    expect(status.gate.can_create_workunit_now).toBe(false);
    expect(status.gate.can_claim_task_now).toBe(false);
    expect(status.gate.readiness).toMatchObject({
      active_tasks: 0,
      stale_leases: 0,
      runner_lock: "none",
      remote_execution_enabled: false,
      arbitrary_command_enabled: false,
      execution_enabled: false,
      queue_apply_enabled: false,
      generic_bounded_queue_apply_enabled: false,
      no_next_execution_authorized: true,
      token_printed: false,
    });
  });

  it("models Goal 220 release approval and apply boundary as preview-only", () => {
    expect(fixtureBoincV1ReleaseApproval).toMatchObject({
      schema: "skybridge.boinc_v1_release_approval.v1",
      max_parallel_repo_mutations: 1,
      require_resource_gate: true,
      require_human_review: true,
      require_finalizer: true,
      require_failure_budget: true,
      require_evidence_retention: true,
      require_audit: true,
      approval_state: "preview_only",
      can_execute_now: false,
      token_printed: false,
    });
    expect(fixtureBoincV1ControlledApplyBoundary).toMatchObject({
      generic_bounded_queue_apply_enabled: false,
      remote_arbitrary_command_dispatch_enabled: false,
      workunit_creation_enabled: false,
      task_claim_enabled: false,
      task_pr_creation_enabled: false,
      can_execute_now: false,
    });
    expect(fixtureBoincV1ReleaseOperatorPolicy.shell_command_text_allowed).toBe(false);
  });

  it("models Goal 220 tag plan without force-moving tags", () => {
    expect(fixtureBoincV1ReleaseTagPlan).toMatchObject({
      schema: "skybridge.boinc_v1_release_tag_plan.v1",
      tag: "v0.99.0-boinc-like-v1-controlled-release",
      force_tag: false,
      token_printed: false,
    });
  });

  it("models Goal 221 controlled trial as one local human-reviewed workunit", () => {
    const status = parseBoincV1ControlledTrialStatus(fixtureBoincV1ControlledTrialStatus);
    expect(status.schema).toBe("skybridge.boinc_v1_controlled_trial_status.v1");
    expect(status.workunit).toMatchObject({
      workunit_id: "boinc-v1-controlled-trial-221-workunit-001",
      task_id: "boinc-v1-controlled-trial-221-task-001",
      task_type: "docs/local-smoke",
      risk: "low",
      target_path: "docs/boinc-v1-controlled-trial-221.md",
      max_workunits: 1,
      max_tasks: 1,
      max_claims: 1,
      max_task_prs: 1,
      token_printed: false,
    });
    expect(status.policy).toMatchObject({
      max_codex_executions: 1,
      allow_remote_execution: false,
      allow_arbitrary_command: false,
      allow_generic_queue_apply: false,
      approval_can_execute_work: false,
      shell_command_text_allowed: false,
    });
    expect(status.gate).toMatchObject({
      gate_result: "pass",
      active_tasks: 0,
      stale_leases: 0,
      runner_lock: "none",
      open_task_pr_count: 0,
      no_next_execution_authorized: true,
    });
    expect(status.finalizer_preview).toMatchObject({
      status: "boinc_v1_controlled_trial_221_completed",
      can_apply: false,
      human_review_confirmed: true,
      no_auto_merge: true,
      token_printed: false,
    });
  });

  it("models Goal 225 server-approved one-workunit execution with human-review hold", () => {
    const status = parseServerApprovedWorkunitStatus(fixtureServerApprovedWorkunitStatus);
    expect(status.schema).toBe("skybridge.server_approved_workunit_status.v1");
    expect(status.workunit).toMatchObject({
      workunit_id: "server-approved-run-225-workunit-001",
      task_id: "server-approved-run-225-task-001",
      task_type: "docs/local-smoke",
      risk: "low",
      target_path: "docs/server-approved-workunit-225.md",
      max_workunits: 1,
      max_tasks: 1,
      max_claims: 1,
      max_task_prs: 1,
      token_printed: false,
    });
    expect(status.policy).toMatchObject({
      mode: "server_approved_one_workunit",
      max_codex_executions: 1,
      remote_execution_enabled: false,
      arbitrary_command_enabled: false,
      generic_queue_apply_enabled: false,
      trusted_docs_auto_merge_enabled: false,
      stop_on_pr_created: true,
    });
    expect(status.gate).toMatchObject({
      gate_result: "pass",
      approval_consumption_status: "consumed",
      active_tasks: 0,
      stale_leases: 0,
      runner_lock: "none",
      open_task_pr_count: 1,
      no_next_execution_authorized: true,
      token_printed: false,
    });
    expect(status.finalizer_preview).toMatchObject({
      status: "held_waiting_human_review_server_approved_run_225",
      can_apply: false,
      human_review_required: true,
      no_auto_merge: true,
      token_printed: false,
    });
  });

  it("models Goal 222 trusted docs auto-merge as disabled preview-only", () => {
    const gate = parseTrustedDocsAutoMergeGate(fixtureTrustedDocsAutoMergeGate);
    expect(gate.schema).toBe("skybridge.trusted_docs_auto_merge_gate.v1");
    expect(gate.policy).toMatchObject({
      trusted_docs_auto_merge_enabled: false,
      auto_merge_apply_enabled: false,
      max_files: 1,
      max_additions: 20,
      max_deletions: 0,
      require_human_override: true,
      token_printed: false,
    });
    expect(gate.decision).toMatchObject({
      decision: "eligible_docs_only_but_disabled",
      theoretically_eligible: true,
      auto_merge_allowed: false,
      human_review_required: true,
    });
    expect(gate).toMatchObject({
      auto_merge_allowed: false,
      platform_auto_merge_enabled: false,
      branch_protection_mutated: false,
      token_printed: false,
    });
  });
});
