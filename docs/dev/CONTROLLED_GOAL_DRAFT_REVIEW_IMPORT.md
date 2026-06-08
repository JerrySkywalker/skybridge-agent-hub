# Controlled Goal Draft Review And Import

Goal 200 adds a controlled review/import workflow for proposed goals generated under `goals/proposed/`.

Proposed goals remain non-executing artifacts. Review/import can stage a reviewed goal pack, but it must not create campaign-step-derived tasks, claim work, start a worker loop, start the queue, or execute generated/imported goals.

## Commands

Use `scripts/powershell/skybridge-goal-draft-review.ps1`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft-review.ps1 -Command review-queue -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft-review.ps1 -Command validate-draft -DraftPath goals/proposed/proposed-goal-201-local-readme-refresh.md -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft-review.ps1 -Command approve-preview -DraftPath goals/proposed/proposed-goal-201-local-readme-refresh.md -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft-review.ps1 -Command approve-apply -DraftPath goals/proposed/proposed-goal-201-local-readme-refresh.md -Reason "low-risk docs fixture approved" -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-draft-review.ps1 -Command import-preview -DraftPath goals/proposed/proposed-goal-201-local-readme-refresh.md -Json
```

Apply commands require explicit reason where they make a review decision. `import-apply` requires an already approved draft, a reason, no validation blockers and explicit operator intent.

## Review Queue Model

Each review record contains:

- `draft_id` / `proposed_goal_id`;
- `proposed_markdown_path`;
- `review_status`: `proposed`, `needs_review`, `approved`, `rejected`, `edited`, `imported`, `superseded`;
- `reviewer`, `decision`, `decision_reason`;
- `risk_level`, `safety_classification`;
- `original_hash`, `edited_hash`;
- `import_status`, `import_target`, `import_preview`;
- `generated_at`, `reviewed_at`;
- `token_printed=false`.

Review state defaults to ignored `.agent/tmp/goal-draft-review/review-state.json`. Smokes use temporary roots so dry-runs and fixture apply tests leave the repository clean.

## Lifecycle

1. `review-queue` lists proposed drafts and any local review decisions.
2. `validate-draft` checks schema, sections, metadata, safety text and hash state.
3. `approve-preview` and `reject-preview` show the decision without mutation.
4. `approve-apply` and `reject-apply` require `-Reason` and write auditable local review state.
5. `edit-preview` / `edit-apply` stage edits and recompute hash evidence.
6. `supersede-preview` / `supersede-apply` records replacement intent.
7. `import-preview` shows exact target path, metadata diff, dependency/order changes, manifest changes, hash changes and blockers.
8. `import-apply` stages an approved draft into `goals/reviewed/` or a configured import root and writes a reviewed import manifest.

## Risk Gating

Blocked or unsafe drafts cannot be approved for import. Medium/high risk drafts require an explicit human reason. Drafts that mention production deploys, secret rotation, server-root config, GitHub settings, branch protection, destructive cleanup, auto-import, auto-execution or self-approval remain blocked.

The low-risk fixture docs draft can be approved/imported only through an explicit reason and dry-run-first preview. Blocked fixture drafts are rejected or rewritten.

## Controlled Import

The default target is `goals/reviewed/`, not the active `goals/dev-queue-189-200/campaign.skybridge.json` manifest. This is deliberate: importing directly into the active dev queue would blur review/import with execution planning. Reviewed imports are staged and marked `execution_review_required=true`.

Import does not execute goals, create tasks, start workers, start queues, claim tasks or advance campaigns. Imported goals remain pending a separate future execution review, such as a later Controlled Start-One Bootstrap Trial.

## Validation

Import preview validates duplicate goal id, duplicate order, missing dependencies, dependency/order changes, invalid task types, required safety sections, no-execution statement, metadata/hash drift and target path constraints. Validation blockers must be resolved before `import-apply`.

## Desktop And Web

Desktop and Web show the proposed goals list, review status, risk, hash, blocked reasons, reason-gated approve/reject preview state, edit/hash state, import preview summary, manifest diff, import target and `execution review required`.

They expose no execute button, no start queue button and no imported-goal execution control.

## Attention

Goal 200 derives review/import attention events:

- `proposed_goal_needs_review`;
- `proposed_goal_approved`;
- `proposed_goal_rejected`;
- `proposed_goal_import_preview_ready`;
- `proposed_goal_imported`;
- `imported_goal_requires_execution_review`;
- `unsafe_import_blocked`.

These events are review/import indicators only. They do not imply execution is enabled.
