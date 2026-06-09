# Proposed Goal Workunit Pipeline

Goal 207A bridges reviewed proposed goals into workunit candidates. It does not execute candidates, claim workers, create tasks, or enable bounded queue apply.

## Lifecycle

Proposed goals remain review artifacts under `goals/proposed` until a human review/import flow marks them eligible. The candidate pipeline reads proposed or reviewed goal metadata and produces `skybridge.proposed_goal_workunit_candidate.v1` records for preview.

Candidate conversion is a planning step:

- low-risk `docs` and `local-smoke` goals may become `candidate_ready`;
- medium and high risk goals stay review-required or blocked;
- blocked surfaces include production deploys, secret rotation, server-root config, DNS, OpenResty, Hermes config, GitHub settings, branch protection, arbitrary shell, auto-execution, and auto-merge;
- generated goals never approve themselves;
- candidate conversion never executes.

## Candidate Pack

The pipeline groups candidates in `skybridge.workunit_candidate_pack.v1`. Packs include risk gate decisions, candidate counts, blocked counts, review-required counts, and a next safe action. Packs are eligible only for bounded queue preview input.

`skybridge.workunit_candidate_manifest.v1` is manifest-only. Fixture writes are confined to `.agent/tmp/workunit-candidates`, require an explicit reason, and still set `execution_review_required=true`.

## Bounded Queue Preview

The bounded queue plan may include a candidate pack as preview input. This means the operator can see what would be considered later, but the queue still reports:

- `can_start_bounded_queue=false`;
- `start_bounded_queue_apply_available=false`;
- no task creation;
- no worker claim;
- no execution.

## Surfaces

Desktop shows a Workunit Candidate Review card with candidate counts, risk status, blocked count, next safe action, and disabled execution controls.

Web shows a Proposed Goal to Workunit Candidate panel with the candidate list, risk gate status, candidate pack summary, bounded queue preview state, and execution-disabled confirmation.

## Validation

Run focused smokes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-goal-to-workunit-schema-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-goal-to-workunit-candidate-pack-preview.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-bounded-queue-preview-includes-candidates.ps1
```

Then run the shared checks from AGENTS.md, including `scripts/powershell/validate-powershell.ps1`, `corepack pnpm check`, `corepack pnpm -C apps/desktop build`, Tauri `cargo check`, and `just check`.
