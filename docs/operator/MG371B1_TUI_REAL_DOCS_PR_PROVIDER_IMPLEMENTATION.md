# MG371B1 TUI Real Docs PR Provider Implementation

MG371B1 implements a safely gated real docs-only PR provider boundary for the
Ratatui Operator Console. It prepares a future MG371B retry, but it is not
MG371B and it must not create a real TUI branch or PR.

## Baseline

- baseline commit:
  `873e1b61e20ac1ff651f3ea5f13fc0cdce5e47f6`
- cloud image:
  `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-873e1b61e20ac1ff651f3ea5f13fc0cdce5e47f6`
- `/v1/health`: ok
- `/v1/version`: matches
  `873e1b61e20ac1ff651f3ea5f13fc0cdce5e47f6`
- cloud parity: ok
- previous implementation milestone:
  MG371B0 TUI-created Docs-only PR Capability Staging
- previous blocked attempt:
  MG371B First TUI-created Docs-only PR under Explicit Authorization

## Relation to MG371B0 and Blocked MG371B

MG371B0 added the TUI docs-only PR state machine, policy validators, fake
provider, blocked real-provider request path and artifacts. It intentionally
kept real mutation disabled and did not implement a callable real provider.

The first MG371B attempt was correctly blocked with:

- `safely_gated_tui_real_provider_path_not_implemented`
- `mg371b0_real_provider_request_blocks_before_provider_call`
- `real_mutation_disabled_by_default`
- `mg371b0_does_not_authorize_real_provider`

MG371B1 resolves the missing support boundary:

- blocker resolved:
  `safely_gated_tui_real_provider_path_not_implemented`

MG371B1 does not resolve MG371B itself. It does not run the armed provider
path, create a TUI branch, create a TUI PR, mark a PR ready, merge, deploy,
release, tag or upload assets.

## Provider Model

The fake provider remains available and unchanged for fixture-safe staging.

The real provider boundary now exists with guarded operations for:

- create local branch
- commit allowlisted docs changes
- push one branch
- create one draft PR

MG371B1 support and smoke paths do not call those operations. Provider call
count remains `0` in MG371B1.

## Required Gates

The future real provider path is disabled by default and requires all of these
gates before any real mutation:

- explicit real-provider flag, such as `--allow-real-docs-pr-provider`
- exact MG371B authorization phrase:
  `I_UNDERSTAND_AUTHORIZE_MG371B_FIRST_TUI_CREATED_DOCS_ONLY_BRANCH_AND_DRAFT_PR`
- MG371B execution mode, not MG371B0 or MG371B1 support mode
- docs-only allowlist pass
- branch policy pass
- clean repo
- current branch is `main`
- `main` synced with `origin/main`
- one branch maximum
- one draft PR maximum
- dry preflight artifact written before mutation

The MG371B authorization phrase is used in MG371B1 only as inert
fixture/policy/test data. MG371B1 records
`authorization_phrase_used_for_real_mutation=false`.

## Branch Policy

Future TUI-created branch names must match:

```text
tui/mg371b-docs-only-pr-<utc-date>-<short-id>
```

Rules:

- prefix must be `tui/`
- milestone must be `mg371b`
- no spaces
- no shell metacharacters
- length under 80 characters
- branch name recorded in artifacts before provider action
- one branch maximum

## Changed-files Allowlist

The future MG371B docs-only allowlist remains:

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

## PR Policy

Future PR metadata policy remains:

- one draft PR maximum
- PR title starts with `MG371B First TUI-created Docs-only PR`
- `draft=true`
- `auto_merge=false`
- `release/tag/assets=false`
- `merge_by_tui=false`
- `mark_ready_by_tui=false`

## Support Probe Behavior

MG371B1 adds a support probe command path:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --operator-guide `
  --stage-tui-docs-pr-real-provider `
  --probe-real-docs-pr-provider-support `
  --authorization-phrase I_UNDERSTAND_AUTHORIZE_MG371B_FIRST_TUI_CREATED_DOCS_ONLY_BRANCH_AND_DRAFT_PR `
  --lang zh-CN `
  --runtime-timeout-ms 120000 `
  --output-dir .agent/tmp/operator-tui/mg371b1-real-provider-implementation
```

The support probe reports:

- `real_provider_path_implemented=true`
- `real_provider_disabled_by_default=true`
- `real_provider_requires_explicit_flag=true`
- `real_provider_requires_exact_authorization=true`
- `real_provider_requires_allowlist=true`
- `real_provider_requires_branch_policy=true`
- `real_provider_requires_clean_synced_main=true`
- `real_provider_called=false`
- `provider_call_count=0`
- `git_push_called=false`
- `gh_pr_create_called=false`
- `github_api_called=false`
- `token_printed=false`

## Artifact Schema

MG371B1 writes ignored artifacts under:

`.agent/tmp/operator-tui/mg371b1-real-provider-implementation/`

Required artifacts:

- `mg371b1-state.json`
- `mg371b1-report.json`
- `mg371b1-report.md`
- `mg371b1-provider-support-probe.json`
- `mg371b1-default-block-report.json`
- `mg371b1-authorization-block-report.json`
- `mg371b1-allowlist-block-report.json`
- `mg371b1-branch-policy-block-report.json`
- `mg371b1-preflight-report.json`
- `mg371b1-safety-report.json`
- `mg371b1-action-history.json`
- `mg371b1-artifact-index.json`

The report schema is:

`skybridge.operator_tui_mg371b1_real_docs_pr_provider_implementation.v1`

## Smoke List

MG371B1 adds these smokes:

- `corepack pnpm smoke:operator-tui-mg371b1-provider-support-probe`
- `corepack pnpm smoke:operator-tui-mg371b1-default-real-provider-blocked`
- `corepack pnpm smoke:operator-tui-mg371b1-authorization-required`
- `corepack pnpm smoke:operator-tui-mg371b1-allowlist-enforced`
- `corepack pnpm smoke:operator-tui-mg371b1-branch-policy-enforced`
- `corepack pnpm smoke:operator-tui-mg371b1-no-real-pr`
- `corepack pnpm smoke:operator-tui-mg371b1-no-real-execution`

These smokes prove:

- support probe reports `real_provider_path_implemented=true`
- default real-provider request blocks before provider call
- authorization missing or mismatch blocks before provider call
- allowlist failure blocks before provider call
- branch policy failure blocks before provider call
- no real branch is created
- no real PR is created
- no `git push` is called
- no `gh pr create` is called
- no GitHub API is called by the TUI
- no worker loop, queue runner, run forever, live Hermes or MCP is called
- `auto_merge=false`
- `release/tag/assets=false`
- `raw_input_persisted=false`
- `token_printed=false`

## Safety Boundary

MG371B1 records:

- `implementation_added=true`
- `runtime_behavior_changed=true`
- `real_provider_path_implemented=true`
- `real_provider_disabled_by_default=true`
- `real_provider_requires_explicit_flag=true`
- `real_provider_requires_exact_authorization=true`
- `support_probe_passed=true`
- `fake_provider_still_available=true`
- `real_provider_called=false`
- `real_provider_mutation_executed=false`
- `real_mutation_enabled=false`
- `authorization_phrase_used_for_real_mutation=false`
- `TUI_created_branch=false`
- `TUI_created_PR=false`
- `git_push_called=false`
- `gh_pr_create_called=false`
- `github_api_called=false`
- `real_task_execution_enabled=false`
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

MG371B1 did not create a real TUI branch or PR.

MG371B1 does not itself authorize MG371B execution.

## Next Recommendation

If MG371B1 passes, retry:

`MG371B First TUI-created Docs-only PR under Explicit Authorization`

The MG371B retry must still require the exact MG371B authorization phrase and
must remain one TUI-created branch, one TUI-created draft PR, docs-only,
no auto-merge, no release/tag/assets, no worker loop, no queue runner, no run
forever, no live Hermes, no MCP, no arbitrary shell and no secrets.

`token_printed=false`
