# Campaign Step Executor Pilot

This note records the manual child-step execution pattern for `bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening`.

## Scope

Task id:

```text
campaign-step-super-187-bootstrap-campaign-mvp-hardening-20260531100053
```

Campaign step:

```text
bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening
```

Source markdown:

```text
goals/bootstrap-mvp/super-187-bootstrap-campaign-mvp-hardening.md
```

Expected files:

- `docs/dev/CAMPAIGN_STEP_EXECUTOR_PILOT.md`
- `docs/dev/BOOTSTRAP_CAMPAIGN_MVP.md`
- `docs/dev/PROGRESS.md`
- `docs/orchestrator/SELF_BOOTSTRAP_SUPERVISOR.md`
- `docs/orchestrator/WORKER_PROFILE_RUNBOOK.md`

## Safety Boundary

The child task execution was documentation-only. It did not:

- advance campaign metadata;
- execute Super 184B;
- start an unbounded worker loop;
- convert proposals or create tasks;
- change production deployment, server root config, secrets, GitHub settings or branch protection;
- commit, push or create the PR from this Codex session when the edge worker owns that step.

Campaign metadata advancement was performed later by the parent Super 187 operator flow after the task evidence was attached and deterministic plus Hermes gate evaluation returned `advance`.

## Execution Checklist

Preflight:

- Read the Super 187 goal markdown completely.
- Read `README.md`, `ARCHITECTURE.md`, `DEVELOPMENT.md` and `SECURITY.md`.
- Inspect current campaign docs and progress notes.
- Confirm target file scope before editing.

Implementation:

- Add the restartable campaign MVP contract.
- Add this campaign step executor pilot record.
- Update supervisor and worker runbooks with campaign resume, lock and evidence expectations.
- Update progress with the campaign step result.

Validation:

- Prefer `just check` when available.
- Otherwise run `corepack pnpm check`.
- Record unavailable commands or failures directly in the final step result.

## PR, CI And Evidence

Child PR:

```text
https://github.com/JerrySkywalker/skybridge-agent-hub/pull/92
```

Execution evidence:

- lease id: `lease_chdDfMPI1SEIgonHR-hzv`
- changed files: docs-only, limited to the expected list above
- validation: `corepack pnpm check` passed in the child task
- CI: GitHub checks passed after the child PR was marked ready
- merge: PR #92 merged by squash
- task evidence: recovered after the initial worker CI guardian stopped on draft/pending checks
- lock cleanup: local repo lock was released in the worker `finally`

## Campaign Step Result

Result status for the real cloud pilot is completed with recovered task evidence and campaign evidence attached.

Required result fields:

- `campaign_id`: `bootstrap-mvp`
- `step_id`: `bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening`
- `goal_id`: `super-187-bootstrap-campaign-mvp-hardening`
- `changed_files`: expected docs list only
- `validation_summary`: `corepack pnpm check` passed
- `child_pr_url`: `https://github.com/JerrySkywalker/skybridge-agent-hub/pull/92`
- `ci_status`: passed
- `merge_status`: merged
- `task_evidence_status`: recovered
- `gate_final_decision`: `advance`
- `campaign_advanced`: `true`, metadata-only to `bootstrap-mvp:super-184b-operator-console-dashboard`

## Operator Follow-Up

Completed operator follow-up:

1. The edge worker committed the docs-only changes.
2. The task branch was pushed and child PR #92 was opened.
3. Checks passed and PR #92 was merged.
4. Task evidence was repaired to recovered after merge.
5. Campaign step evidence was attached.
6. `advance-with-gate -Apply` advanced the campaign to Super 184B without executing Super 184B.
