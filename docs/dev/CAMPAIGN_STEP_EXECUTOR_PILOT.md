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

This execution is documentation-only. It must not:

- advance campaign metadata;
- execute Super 184B;
- start a worker loop;
- convert proposals or create tasks;
- change production deployment, server root config, secrets, GitHub settings or branch protection;
- commit, push or create the PR from this Codex session when the edge worker owns that step.

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

## Draft PR Evidence

The task request requires a draft/manual child PR URL as evidence, but the same task body also says not to run `git add`, `git commit`, `git push` or `gh pr create`; the edge worker owns commit, push and draft PR creation after validation passes.

Expected PR state for this Codex session:

- child PR URL: pending edge-worker commit/push/PR creation;
- PR mode: draft/manual child PR;
- changed files: docs-only, limited to the expected list above.

## Campaign Step Result

Result status for this local execution is documentation prepared, validation passed, PR creation delegated to the edge worker, and campaign advancement not performed.

Required result fields:

- `campaign_id`: `bootstrap-mvp`
- `step_id`: `bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening`
- `goal_id`: `super-187-bootstrap-campaign-mvp-hardening`
- `changed_files`: expected docs list only
- `validation_summary`: `corepack pnpm check` passed
- `draft_pr_url`: pending unless the edge worker creates it later
- `ci_status`: unavailable until PR exists
- `merge_status`: unavailable until PR exists
- `campaign_advanced`: `false`

## Operator Follow-Up

After validation, the edge worker or operator should:

1. Commit these docs-only changes.
2. Push the task branch.
3. Open a draft/manual child PR.
4. Attach the PR URL, validation result and this campaign step summary as evidence.
5. Leave campaign advance to the SkyBridge gate; do not advance metadata from the child PR workflow.
