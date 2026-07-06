# MG371B0 TUI-created Docs-only PR Capability Staging

MG371B0 implements the first TUI docs-only PR capability path in a staged,
disabled-by-default form. It prepares the machinery needed for a future MG371B
attempt, but it is not MG371B and does not authorize a real TUI-created branch
or PR.

## Baseline

Baseline commit:
`c2f5c6ebd58a19694901c42ffe941b81d6530303`

Baseline cloud image:
`ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-c2f5c6ebd58a19694901c42ffe941b81d6530303`

Baseline cloud health:
`/v1/health` ok

Baseline cloud version:
`/v1/version` matches `c2f5c6ebd58a19694901c42ffe941b81d6530303`

Baseline cloud parity:
ok

Relation to MG371A:
MG371A defined the future authorization design gate. MG371B0 implements a
disabled-by-default capability staging path and fake-provider smokes against
that design. MG371B0 does not use the future MG371B authorization phrase as
active real-mutation authorization.

## Why MG371B0 Exists Before MG371B

MG371A proved the policy was written down, but MG371B needs code-level policy
enforcement before a real TUI-created branch or draft PR is attempted.
MG371B0 inserts that implementation staging step so branch naming, changed-file
allowlists, PR metadata rules, one-branch/one-draft-PR limits, provider
boundaries, abort behavior and audit artifacts can be exercised safely without
real mutation.

MG371B0 therefore proves the TUI path can run the state machine with a fake
provider while all real branch/PR creation stays disabled.

## Implementation Summary

MG371B0 adds a clearly named TUI command path:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --operator-guide `
  --self-drive-dry-run `
  --yolo-fixture-only `
  --stage-tui-docs-pr-capability `
  --fake-docs-pr-provider `
  --lang zh-CN `
  --runtime-timeout-ms 120000 `
  --output-dir .agent/tmp/operator-tui/mg371b0-capability-staging
```

The staged state machine records:

1. `disabled`
2. `preflight_pending`
3. `authorization_required`
4. `authorization_verified`
5. `branch_plan_prepared`
6. `allowlist_checked`
7. `draft_pr_metadata_prepared`
8. `fake_provider_executed`
9. `real_provider_blocked`
10. `completed_staging`

The normal MG371B0 path reaches `fake_provider_executed` and
`completed_staging`. The unauthorized real-provider scenario reaches
`real_provider_blocked` before any provider call.

## Provider Model

MG371B0 defines an internal provider boundary.

Fake provider:

- default for MG371B0
- records simulated branch metadata
- records simulated draft PR metadata
- never calls `git push`
- never calls `gh pr create`
- never calls the GitHub API
- writes artifacts only

Real provider:

- guarded placeholder only
- disabled by default
- not reachable in MG371B0
- blocked before provider invocation when requested in smokes
- must require a future explicit real-mutation flag and the exact future
  MG371B authorization phrase before any future activation

MG371B0 smokes do not call the real provider.

## Future Authorization Phrase Policy

The MG371A future authorization phrase is known as inert fixture/policy data:

```text
I_UNDERSTAND_AUTHORIZE_MG371B_FIRST_TUI_CREATED_DOCS_ONLY_BRANCH_AND_DRAFT_PR
```

MG371B0 records:

- `phrase_known=true`
- `authorization_phrase_matched_for_future_flow=true` only in fake-provider or
  blocked-policy fixture scenarios
- `phrase_used_for_real_mutation=false`
- `future_authorization_phrase_used_for_real_mutation=false`
- `real_mutation_authorized=false`

The phrase alone does not enable real mutation in MG371B0.

## Branch Policy

MG371B0 validates the future branch pattern:

```text
tui/mg371b-docs-only-pr-<utc-date>-<short-id>
```

Validation enforces:

- prefix must be `tui/`
- milestone must be `mg371b`
- no spaces
- no shell metacharacters
- length under 80 characters
- branch name recorded in artifacts before provider action
- one branch maximum

Invalid branch names stop before fake provider execution and before any real
mutation path.

## Allowlist Policy

MG371B0 enforces the MG371A future changed-files allowlist:

- `docs/operator/MG371B_FIRST_TUI_CREATED_DOCS_ONLY_PR.md`
- `docs/operator/RATATUI_OPERATOR_CONSOLE.md`
- `docs/dev/PROGRESS.md`
- `docs/release/MANAGED_DEV_E2E_HANDOFF.md`
- `docs/release/STAGE_S1_1_CLOSE.md`

Blocked classes:

- app code
- server code
- workflow files
- package files
- Docker/runtime/production infra files
- generated binary artifacts
- secrets

Non-allowlisted files stop before provider execution.

## PR Metadata Policy

MG371B0 prepares draft PR metadata only:

- one draft PR maximum
- title starts with `MG371B First TUI-created Docs-only PR`
- body includes safety flags
- `draft=true`
- `auto_merge=false`
- `release/tag/assets=false`
- `merge_by_tui=false`

MG371B0 does not open a real PR from the TUI.

## Abort Policy

MG371B0 records the future abort policy in action history:

Before branch creation:

- abort clears pending state
- artifacts record `aborted_before_branch_creation=true`
- no branch or PR exists

After fake branch creation but before fake PR creation:

- fake provider only
- artifacts record `branch_created=true` and `pr_created=false`
- no real branch exists

After fake PR creation:

- fake provider only
- artifacts record `branch_created=true` and `pr_created=true`
- no real PR exists

No automatic real branch deletion or PR closing is added.

## Artifact Schema

MG371B0 writes ignored artifacts under:

`.agent/tmp/operator-tui/mg371b0-capability-staging/`

Required artifacts:

- `mg371b0-state.json`
- `mg371b0-report.json`
- `mg371b0-report.md`
- `mg371b0-preflight.json`
- `mg371b0-authorization-check.json`
- `mg371b0-allowlist-check.json`
- `mg371b0-branch-plan.json`
- `mg371b0-pr-metadata.json`
- `mg371b0-provider-report.json`
- `mg371b0-safety-report.json`
- `mg371b0-action-history.json`
- `mg371b0-artifact-index.json`

Report schema:
`skybridge.operator_tui_mg371b0_tui_docs_pr_capability_staging.v1`

Key report fields include:

- `implementation_added=true`
- `runtime_behavior_changed=true`
- `real_mutation_enabled=false`
- `fake_provider_used=true`
- `real_provider_called=false`
- `future_authorization_phrase_known=true`
- `future_authorization_phrase_used_for_real_mutation=false`
- `real_mutation_authorized=false`
- `branch_policy_enforced=true`
- `allowlist_enforced=true`
- `pr_policy_enforced=true`
- `abort_policy_enforced_or_documented=true`
- `artifacts_written=true`
- `TUI_created_branch=false`
- `TUI_created_PR=false`
- `git_push_called=false`
- `gh_pr_create_called=false`
- `github_api_called=false`
- `token_printed=false`

## Smoke List

MG371B0 adds these smokes:

- `corepack pnpm smoke:operator-tui-mg371b0-capability-staging`
- `corepack pnpm smoke:operator-tui-mg371b0-unauthorized-real-mutation-blocked`
- `corepack pnpm smoke:operator-tui-mg371b0-allowlist-enforced`
- `corepack pnpm smoke:operator-tui-mg371b0-branch-policy-enforced`
- `corepack pnpm smoke:operator-tui-mg371b0-no-real-pr`
- `corepack pnpm smoke:operator-tui-mg371b0-no-real-execution`

These smokes prove:

- fake provider completes the staged flow
- real provider is not called
- unauthorized real mutation is blocked
- future authorization phrase alone does not enable real mutation in MG371B0
- invalid branch names are blocked
- non-docs/non-allowlisted files are blocked
- changed-files allowlist passes for the future MG371B docs set
- PR metadata is draft-only
- auto-merge remains false
- release/tag/assets remain false
- no real branch is created
- no real PR is created
- no `git push` is called
- no `gh pr create` is called
- no GitHub API is called by the TUI
- no worker loop, queue runner, run forever, live Hermes or MCP is called
- `token_printed=false`

## Safety Boundary

MG371B0 records:

- `TUI_created_branch=false`
- `TUI_created_PR=false`
- `git_push_called=false`
- `gh_pr_create_called=false`
- `github_api_called=false`
- `real_task_execution_enabled=false`
- `real_branch_creation_enabled_by_TUI=false`
- `real_PR_creation_enabled_by_TUI=false`
- `task_created=false`
- `task_claimed=false`
- `execution_started=false`
- `worker_loop_started=false`
- `queue_runner_started=false`
- `run_forever_started=false`
- `hermes_live_called=false`
- `mcp_run_called=false`
- `auto_merge_enabled=false`
- `release_created=false`
- `tag_created=false`
- `asset_uploaded=false`
- `raw_input_persisted=false`
- `token_printed=false`

MG371B0 did not create a real TUI branch or PR.

MG371B0 does not authorize MG371B.

## Next Recommendation

If MG371B0 passes, recommend:

`MG371B First TUI-created Docs-only PR under Explicit Authorization`

MG371B must still require Jerry to provide the exact MG371B authorization
phrase before any TUI-created branch or PR:

```text
I_UNDERSTAND_AUTHORIZE_MG371B_FIRST_TUI_CREATED_DOCS_ONLY_BRANCH_AND_DRAFT_PR
```

`token_printed=false`
