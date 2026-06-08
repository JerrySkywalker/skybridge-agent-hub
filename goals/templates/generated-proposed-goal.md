```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "proposed-000-short-slug",
  "title": "Generated Proposed Goal Title",
  "order": 1,
  "risk": "medium",
  "task_type": "generated-proposed-goal",
  "allowed_task_types": ["docs", "local-smoke"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": [],
  "expected_outputs": ["review_preview", "operator_decision"],
  "advance_gate": {
    "requires_clean_worktree": true,
    "requires_no_active_tasks": true,
    "requires_no_stale_leases": true,
    "requires_parent_pr_merged": false,
    "requires_human_approval": true
  },
  "proposal": {
    "generated": true,
    "review_required": true,
    "convert_to_ready_requires_apply": true
  }
}
```

# Proposed 000: Generated Proposed Goal Title

## Context

Summarize the source prompt or planning context without including raw private prompts.

## Mission

Create a reviewable proposed goal that an operator can accept, revise or reject.

## Hard Safety Boundaries

- Do not include raw prompts, raw stdout/stderr, secrets, tokens, cookies, Authorization headers or private key material.
- Do not auto-import, auto-convert, execute campaign steps, claim tasks or start workers.
- Do not mutate live campaign state without an explicit reviewed apply flow.

## Allowed Scope

- Draft markdown.
- Dry-run validation and re-import preview.
- Operator review metadata.

## Validation

- Validate schema, dependencies, safety sections and safe-to-paste output.
- Confirm token_printed=false.

## Evidence Requirements

- Generated draft id.
- Validation result.
- Review decision path.
- No-execution confirmation.

## Final Campaign State

- Proposed goals remain proposed until a separate review-gated conversion occurs.
- live campaign state is not mutated by default.
- token_printed=false.

## No Execution Statement

This generated/proposed goal is authoring-only. It must not execute queue steps, create execution tasks, claim tasks or run workers. token_printed=false.
