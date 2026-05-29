# Batch Worker Loop Pilot

Status: Super 180 capability-aligned batch pilot proven on 2026-05-29 with recovered evidence for one pending-CI stop.

The Super 180 batch worker loop pilot extends the one-task always-on worker proof into a small bounded batch. Its purpose is to verify that SkyBridge can prepare several low-risk tasks, normalize their execution capabilities to match real worker profiles, let one local worker process them one at a time, and return concise evidence without turning the worker into an unbounded background executor.

This is a control-plane and evidence pilot, not a production execution expansion. The loop remains local-first, task-capped, stop-on-failure capable and safe to inspect through status commands and child PR evidence.

## Pilot Purpose

The pilot should prove:

- a batch contains only reviewed low-risk tasks with explicit allowed paths;
- task capability requirements are executable by the selected worker before the loop starts;
- the worker claims at most one task at a time and stops at the configured task cap, idle timeout, project pause or first failure when requested;
- child PRs and CI results form the evidence chain for each completed task;
- recovered evidence is appended without rewriting raw failed task history;
- project control is restored to `paused` when the batch finishes or stops.

The pilot should not prove remote unattended production control, public worker exposure, secret handling, server root mutation or broad auto-merge behavior.

## Capability Normalization Rules

Capability alignment is the main Super 180 constraint. A batch must be prepared against the worker profile that will actually execute it.

- Preserve planner output as `original_required_capabilities` when proposal normalization is available.
- Add `normalized_required_capabilities` for policy and conversion decisions.
- Executable proposals must include `codex` in the normalized capability list because the current local worker executes tasks through Codex.
- Docs proposals may keep descriptive capabilities such as `docs` or `git`, but those must not make the task incompatible with a worker that does not advertise `docs`.
- Safe local-smoke proposals may keep `powershell`, `windows`, `node` or similar capabilities when they match the worker profile, but they still need `codex` when Codex performs the repository edit.
- Unsafe proposal types, high-risk paths and production surfaces remain blocked by policy; normalization must not weaken risk gates.
- Converted tasks should use the normalized capability list, not the raw planner list, so queue selection and worker filtering agree.

For `laptop-zenbookduo`, the known lesson from the previous pilot is that a docs-only task requiring only `docs` can be skipped as incompatible even though the worker can execute documentation work through Codex. Batch preparation should therefore prefer `required_capabilities=["codex"]` or `["codex","git"]` for docs tasks unless the worker profile explicitly advertises `docs`.

## Status Query Filters

Operators should inspect the batch before, during and after execution with scoped status queries rather than broad queue dumps.

Use the project filter for normal batch status:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ProjectId skybridge-agent-hub
```

Use `-ShowAll` before and after the pilot to include completed and recovered tasks:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ProjectId skybridge-agent-hub `
  -ShowAll
```

Use `-TaskId` for final evidence inspection of each task:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ProjectId skybridge-agent-hub `
  -TaskId <task-id>
```

For machine-readable review, add `-Json` and write snapshots to local operator files. Do not upload raw command output, local worker logs or Codex JSONL logs to SkyBridge.

Important fields in status output:

- `raw_status`: the stored task state, including historical `failed` values.
- `display_status`: operator-facing recovered state when evidence proves recovery.
- `recovered`: whether evidence repair marked the task recovered.
- `ci_status`: CI state such as `passed`, `pending`, `failed`, `passed_after_pending` or `passed_after_rerun`.
- `pr_url`: child PR that carries the reviewable diff and CI evidence.
- `evidence`: compact indication that evidence exists or has been repaired.

## Safety Boundaries

The batch loop must stay inside the same safety boundary as the earlier edge worker pilots:

- no secrets, `.env` files, private keys, cookies or deployment credentials;
- no production config, server root configuration, OpenResty, Authelia, 1Panel or Docker daemon changes;
- no GitHub settings, branch protection or force-push changes;
- no raw prompts, raw command output, patches, stdout, stderr, Codex JSONL logs or local worker artifacts uploaded to SkyBridge;
- no production deployment or public remote worker exposure;
- no task execution outside the selected task's allowed paths;
- no removal of tests just to make validation pass;
- no unbounded loop; use `MaxTasks`, idle timeout, project control and stop-on-failure.

For docs-only batch tasks, expected changed files should remain under the documented allowed path list. If a task needs code, scripts, config or deployment files, it belongs in a separate reviewed pilot with a higher risk classification.

## Expected Evidence Fields

Each completed or repaired task should provide a concise `evidence_summary` rather than raw logs. Expected fields are:

- `task_id`
- `goal_id`
- `pr_url`
- `commit_sha` when available
- `changed_files`
- `validation_status`
- `ci_status`
- `risk_status`
- `summary`
- `created_at`
- `recovered` when evidence repair is used

Recommended batch-level evidence:

- worker ID and advertised capabilities used for selection;
- batch task IDs and normalized capability lists;
- project control start and final paused state;
- loop bounds such as `MaxTasks`, poll interval, idle timeout and stop-on-failure;
- local-only log path names, without log contents;
- final child PR URLs and CI conclusions;
- skipped, blocked or incompatible tasks with bounded reasons such as `missing_capability:<capability>`.

The pilot is successful when every claimed task has completed evidence, recovered evidence or an explicit bounded failure, the project is paused, no extra tasks are running, and no unsafe data has been uploaded.

## 2026-05-29 Super 180 Result

The real batch used only `laptop-zenbookduo` and cloud project `skybridge-agent-hub` with:

- `MaxTasks=2`
- `IdleTimeoutSeconds=120`
- `PollIntervalSeconds=5`
- `StopOnFailure=true`
- allowed task types: docs only

Prepared tasks:

- `batch-worker-loop-pilot-docs-180b`: docs task for `docs/orchestrator/WORKER_PROFILE_RUNBOOK.md`, legacy `required_capabilities=["docs","git"]`.
- `batch-worker-loop-pilot-docs-180a`: docs task for `docs/dev/BATCH_WORKER_LOOP_PILOT.md`, legacy `required_capabilities=["docs"]`.

The interrupted first task was recovered manually from the worker child branch without widening scope. Child PR [#81](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/81) changed only `docs/orchestrator/WORKER_PROFILE_RUNBOOK.md`, passed AI branch validation, Project check, Docker build server and Docker build web, and merged at `64fec501a08431d31442912d3820618f4882f0a5`. Cloud task `batch-worker-loop-pilot-docs-180b` is `completed` with `ci_status=passed`.

The bounded loop then claimed the remaining queued task. Codex completed with `retry_count=0`, changed only `docs/dev/BATCH_WORKER_LOOP_PILOT.md`, and opened child PR [#82](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/82). CI Guardian stopped the loop while checks were pending, so the cloud task recorded `failed` and the loop stopped with `stop_reason=failure`. PR #82 then passed AI branch validation, Project check, Docker build server and Docker build web, was marked ready, and merged at `d7c2cd7ee7fe9eb703df0b9222472bf7c62348a1`. Evidence repair recorded `recovered=true`, `ci_status=passed_after_pending`, and `risk_status=low_docs_only` for `batch-worker-loop-pilot-docs-180a`.

Final cloud state was restored to `paused` with `stop_requested=false`, `stop_reason=batch_pilot_completed_with_recovered_evidence`, and no queued, claimed or running tasks. Historical `task_proposal-59a0236fb69800cd` remained blocked and was not executed. No local-smoke, production, deployment, server config, GitHub settings, branch protection or secret work was run.

Conclusion: the capability-aligned batch worker loop is proven for two low-risk docs tasks on `laptop-zenbookduo`, with one normal completion and one recovered pending-CI stop. The next reliability improvement is to make CI Guardian treat pending checks as waitable instead of task failure when the PR is otherwise safe and bounded.
