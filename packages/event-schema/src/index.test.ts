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
