# Managed Dev Campaign E2E

MG362 adds the first campaign-driven managed development end-to-end wrapper. It
connects the reviewed-goal append gate, bounded one-action selection and the
controller-native managed-dev PR path.

## Purpose

The milestone proves this reviewed path:

1. a reviewed managed-dev goal is available;
2. the goal is appended as one campaign metadata step;
3. the bounded loop selects exactly one managed-dev draft PR action;
4. the managed-dev controller creates one branch and one docs-only change;
5. the controller creates one draft PR and observes CI;
6. the flow holds for human review.

This is not an autonomous development loop. It does not auto-merge, run a queue
runner, start a worker loop, call Hermes or MCP, or create releases, tags or
assets.

## Relation To Prior Milestones

- MG351 defines provider inventory and local execution ownership.
- MG352 and MG353 prove one-step and ordered static execution boundaries.
- MG354 generates proposed goal markdown only.
- MG355 reviews and appends one generated goal as non-executed metadata.
- MG356 chooses one bounded next action per invocation.
- MG357 through MG361 prove managed-dev draft PR creation, Git/GH repair and the
  human PR review/merge gate.

MG362 composes those contracts without widening them.

## Controller

Main script:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-dev-campaign.ps1 -Command preview -Fixture -Json
```

Supported commands:

- `status`
- `preview`
- `create-fixture`
- `append-reviewed-dev-goal`
- `bounded-apply-one`
- `create-draft-pr`
- `observe-ci`
- `run-fixture-e2e`
- `report`
- `safe-summary`

Default behavior is fixture preview. Mutation requires exact confirmation.

## Exact Confirmations

One campaign-driven managed-dev action requires:

```text
I_UNDERSTAND_RUN_ONE_CAMPAIGN_DRIVEN_MANAGED_DEV_ACTION_ONLY
```

Creating the controller-native draft PR requires:

```text
I_UNDERSTAND_CREATE_ONE_DRAFT_PR_FOR_HUMAN_REVIEW_ONLY_NO_AUTO_MERGE
```

## Fixture Flow

Fixture mode is CI-safe and creates no real branches or PRs.

- campaign: `managed-dev-campaign-fixture-362`
- goal: `managed-dev-campaign-goal-362-fixture`
- appended step: `managed-dev-campaign-step-362-fixture`
- selected action: `managed_dev_draft_pr`
- changed file list: `docs/orchestrator/CAMPAIGN_DRIVEN_MANAGED_DEV_MG362.md`
- CI: simulated success
- hold: `held_for_human_review=true`

## Local Flow

Local mode may create one real branch and one draft PR only after the exact
confirmations. The target branch is:

```text
codex/mg362-campaign-driven-managed-dev-pilot-pr
```

The target PR title is:

```text
MG362 Campaign-Driven Managed Dev Pilot PR
```

The controller delegates branch, commit, push, draft PR creation and CI
observation to the repaired managed-dev pilot controller. The report keeps
`manual_fallback_used=false`.

## Allowed Paths

- `docs/orchestrator/`
- `docs/dev/`
- `docs/dev/PROGRESS.md`
- `scripts/powershell/`
- `package.json` when adding fixture-only smoke entries
- `packages/event-schema/` for narrowly scoped schema/report fields

## Forbidden Paths

- `.github/workflows/`
- deployment infrastructure and Docker deployment files
- OpenResty, Authelia, DNS, TLS or firewall config
- secrets, env, proxy, token and credential files
- installer, binary or generated release assets
- production runtime config

## Manual M8 Test

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-managed-dev-campaign-test.ps1 -Fixture -Preview -Json -WriteReport
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-managed-dev-campaign-test.ps1 -Fixture -RunFixture -Confirm I_UNDERSTAND_RUN_ONE_CAMPAIGN_DRIVEN_MANAGED_DEV_ACTION_ONLY -Json -WriteReport
```

Optional local mode should be run only after implementation merge and cloud
parity are green. It creates at most one draft PR and then stops for human
review.

## Failure And Hold Cases

The controller holds when confirmations are missing, branch names are unsafe,
forbidden paths are selected, the managed-dev controller reports a Git/GH
blocker, CI cannot be observed, or the draft PR is unavailable.

## Next Milestones

Useful follow-ups are a Hermes planner provider pilot, managed-dev v2 with
generated goal input, and the MCP tool provider stub. None are enabled by MG362.

`token_printed=false`
