# Goal 201 Local README Refresh

## Metadata

```json
{
  "proposed_goal_id": "proposed-goal-201-local-readme-refresh",
  "title": "Goal 201 Local README Refresh",
  "source": "fixture",
  "proposed_markdown_path": "goals/proposed/proposed-goal-201-local-readme-refresh.md",
  "content_hash": "a80296ad3f06fd009c1c82a8caa68e337821bc538040fb01141eff47ae6785fb",
  "safety_classification": "low",
  "review_status": "proposed",
  "suggested_order": 201,
  "suggested_dependencies": [
    "super-200-controlled-goal-draft-review-import"
  ],
  "allowed_task_types": [
    "docs",
    "local-smoke"
  ],
  "blocked_task_types": [
    "production_deploy",
    "secret_rotation",
    "server_root_config",
    "github_settings",
    "branch_protection",
    "auto_execution"
  ],
  "expected_outputs": [
    "reviewed_docs",
    "fixture_smoke"
  ],
  "review_notes": [
    "Fixture-generated proposed goal for human review only."
  ],
  "generated_at": "2026-06-08T00:00:00.000Z",
  "review_required": true,
  "token_printed": false
}
```

## Context

SkyBridge may use fixture or Hermes-adapter output to draft future Super Goals, but this artifact is only a proposed goal.

## Mission

Refresh local project documentation for the proposed-goal workflow after Goal 200 imports reviewed drafts.

## Hard Safety Boundaries

- Do not import this generated goal into an active campaign.
- Do not execute this generated goal.
- Do not create campaign-step-derived execution tasks.
- Do not allow generated goals to approve themselves.
- Do not print or persist tokens, Authorization headers, raw prompts, raw LLM outputs, raw stdout/stderr, private keys, cookies, or secret-bearing local paths.
- token_printed=false

## Allowed Scope

- Human review under goals/proposed only.
- Fixture-generated Markdown may be written only with explicit fixture apply mode.
- Real Hermes invocation remains disabled unless a later reviewed goal explicitly enables a fixture-safe adapter boundary.

## Validation

- Validate required sections before writing.
- Validate safety filter classification before writing.
- Validate output path remains under goals/proposed.
- Validate no import, no execution, no task claim, and no worker loop.
- Validate token_printed=false.

## Evidence Requirements

- Proposed draft path.
- Stable content hash.
- Safety classification and blocked reasons.
- Review status.
- No-import and no-execution confirmation.

## Final Campaign State

- Goal 199 may create proposed drafts only.
- Goal 200 is required for controlled review/import.
- Active campaign manifests are not updated by this draft.
- token_printed=false

## No-Execution Statement

This generated goal is proposed/review-required only. It must not be imported, approved for import, or executed by Goal 199.

