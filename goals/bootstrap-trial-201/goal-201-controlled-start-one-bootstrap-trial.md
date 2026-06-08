```json
{"schema":"skybridge.super_goal.v1","goal_id":"goal-201-controlled-start-one-bootstrap-trial","title":"Controlled Start-One Bootstrap Trial","order":1,"risk":"low","task_type":"docs/local-smoke","allowed_task_types":["docs","local-smoke"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection","auto_execution","start_all","unbounded_worker_loop"],"requires":["super-200-controlled-goal-draft-review-import"],"source_proposed_goal_id":"proposed-goal-201-local-readme-refresh","source_proposed_markdown_path":"goals/proposed/proposed-goal-201-local-readme-refresh.md","payload":"Local README Refresh","expected_outputs":["one_small_readme_or_docs_pr","local_smoke_evidence","post_run_hold"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Goal 201: Controlled Start-One Bootstrap Trial

## Context

Goal 199 produced `goals/proposed/proposed-goal-201-local-readme-refresh.md` as a proposed, non-executing docs/local-smoke draft. Goal 200 added the controlled review/import workflow, but imported drafts still require a separate execution review before any task creation or worker claim.

This reviewed trial pack reframes that draft as a one-step bootstrap trial. It does not import anything into `dev-queue-189-200`.

## Mission

Prove the control contract for starting exactly one low-risk docs/local-smoke campaign step, creating exactly one execution task, routing it to exactly one eligible local worker, producing exactly one review PR, and immediately holding for human review.

The payload is the Local README Refresh. The expected result is one small README/docs PR, no auto-merge, and no continuation.

## Hard Safety Boundaries

- Do not run `start-all`.
- Do not run an unbounded worker loop.
- Do not run `resume -Apply`.
- Do not execute more than one campaign step.
- Do not create more than one execution task.
- Do not allow more than one task claim.
- Do not create more than one task PR.
- Do not automatically merge the task PR.
- Do not continue to another goal after the trial.
- Do not execute any task type except docs/local-smoke.
- Do not mutate production, server-root, DNS, OpenResty, Authelia, 1Panel, Docker daemon, Hermes, GitHub settings, branch protection, or secrets.
- Do not mutate repositories outside `V:/src/skybridge-agent-hub`.
- Do not expose arbitrary shell execution.
- Do not print or persist tokens, Authorization headers, raw prompts, raw stdout/stderr, raw worker logs, private keys, cookies, secret-bearing local paths, or raw Codex transcripts.
- token_printed=false

## Trial Budget

- `max_steps=1`
- `max_tasks=1`
- `max_prs=1`
- `max_runtime_minutes=30`
- `max_parallel_per_repo=1`
- `auto_merge=false`
- `post_run_state=held_waiting_human_pr_review`

## Reviewed Import Trace

- Original proposed artifact: `goals/proposed/proposed-goal-201-local-readme-refresh.md`
- Proposed goal id: `proposed-goal-201-local-readme-refresh`
- Reviewed trial campaign id: `bootstrap-trial-201`
- Reviewed trial goal id: `goal-201-controlled-start-one-bootstrap-trial`
- Review status: `execution-review-required`

## Current Execution Decision

The campaign pack is approved only as a reviewed trial artifact. Actual execution must remain held unless the start-one bootstrap gate can prove all preflight gates and a bounded one-shot worker claim/executor path.

Current known blocker: existing worker service and routing contracts still report `can_claim_tasks=false` and `can_execute_tasks=false`. Until a later change adds a real one-shot claim/executor boundary, this Goal 201 pack must not create a task or claim work.

## Evidence Requirements

- Reviewed/imported Goal 201 path.
- Trial campaign id.
- Original proposed goal trace.
- Gate result with active tasks, stale leases, runner lock, repo lock, route preview and budget.
- Worker route reason.
- If executed later, task id, PR URL, lease outcome, and post-run hold state.
- Confirmation that no start-all, no second task, no auto-merge, no raw transcript, and token_printed=false.

## Final State

The safe final state for this infrastructure pass is `held_no_execution_worker_claim_disabled`.

