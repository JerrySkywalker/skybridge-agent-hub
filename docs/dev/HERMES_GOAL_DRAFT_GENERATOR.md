# Hermes Goal Draft Generator

Goal 199 adds a fixture-first proposed-goal draft generator for SkyBridge.

The generator writes candidate Super Goal Markdown only under `goals/proposed/` and only when explicitly asked to apply fixture output. Generated goals are proposed/review-required artifacts. They are not imported into campaign manifests, converted into tasks or executed.

## Workflow

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft.ps1 -Command goal-draft-generate-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft.ps1 -Command goal-draft-generate-fixture -Apply -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft.ps1 -Command goal-draft-list -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft.ps1 -Command goal-draft-safe-summary -Json
```

Default generation is dry-run. Write mode is restricted to deterministic fixture Markdown under `goals/proposed/`.

## Proposed Goal Schema

Each proposed draft records `proposed_goal_id`, `title`, `source`, `proposed_markdown_path`, `content_hash`, `safety_classification`, `review_status`, `suggested_order`, `suggested_dependencies`, `allowed_task_types`, `blocked_task_types`, `expected_outputs`, `review_notes`, `generated_at` and `token_printed=false`.

## Safety Filter

Drafts are blocked when they propose production deploys, secret rotation, server-root config mutation, GitHub settings, branch protection, credential extraction, destructive filesystem actions, unbounded worker loops, auto-import, auto-execution or self-approval.

Medium and high risk drafts remain human-review items. Blocked drafts must not be imported.

## Hermes Boundary

Goal 199 does not require a real Hermes service. The supported path is fixture-first generation. A future Hermes adapter can feed the same schema only after a reviewed goal enables a fixture-safe boundary that avoids raw prompt/output logging.

## Goal 200 Boundary

Goal 199 intentionally does not import or execute generated goals. Goal 200 is required for controlled review/import so proposed drafts cannot approve themselves or bypass campaign review.
