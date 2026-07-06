# MG371A TUI-created Docs-only PR Authorization Design Gate

MG371A is a documentation, policy and safety-design milestone for a future
first TUI-created docs-only branch and draft PR. It prepares the MG371B
authorization contract, but does not perform MG371B.

## Baseline

Baseline commit:
`225b54a07c2be29290e4ba5eb86e6e655af1d2fa`

Cloud version before design gate:
`225b54a07c2be29290e4ba5eb86e6e655af1d2fa`

Cloud image before design gate:
`ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-225b54a07c2be29290e4ba5eb86e6e655af1d2fa`

Cloud health before design gate:
`/v1/health` ok

Cloud parity before design gate:
ok

Previous gate:
`MG370D Review Gate for Codex-controller Docs-only PR Repeatability`

Previous gate result:
`codex_controller_docs_pr_repeatability_result=pass`

Reviewed Codex-controller docs-only PR count:
`2`

## Scope

MG371A is design-only.

- no TUI-created branch in MG371A
- no TUI-created PR in MG371A
- no real task execution in MG371A
- no runtime behavior change in MG371A

MG371A does not implement TUI-created branch or PR behavior. It does not enable
TUI-created branch or PR behavior. It only defines the authorization, allowlist,
branch, PR, abort and audit contract required before a future MG371B attempt.

## Human Authorization Contract for Future MG371B

The exact future authorization phrase required for MG371B is:

`I_UNDERSTAND_AUTHORIZE_MG371B_FIRST_TUI_CREATED_DOCS_ONLY_BRANCH_AND_DRAFT_PR`

This phrase must only authorize:

- one TUI-created branch
- one TUI-created draft PR
- docs-only changed files
- no auto-merge
- no release/tag/assets
- no worker loop
- no queue runner
- no run forever
- no live Hermes
- no MCP
- no arbitrary shell
- no secrets

Without this exact authorization phrase, the TUI must not create a real branch
or PR.

The phrase must be compared exactly. A missing, partial, translated,
case-changed or whitespace-mutated phrase must be treated as not authorized.
Authorization verification must be recorded in the future MG371B audit
artifacts before any branch or PR creation.

## Branch Naming Policy

Allowed future TUI-created branch naming pattern:

`tui/mg371b-docs-only-pr-<utc-date>-<short-id>`

Rules:

- prefix must be `tui/`
- milestone must be present
- branch name must not contain spaces
- branch name must not contain shell metacharacters
- branch name must be under 80 characters
- branch name must be recorded in artifacts before creation
- one branch maximum

The branch plan must be written before branch creation. If the branch name does
not match the policy, the TUI must stop before mutation and record the blocker.

## Future MG371B Changed-files Allowlist

Allowed future changed files for the first TUI-created docs-only PR:

- `docs/operator/MG371B_FIRST_TUI_CREATED_DOCS_ONLY_PR.md`
- `docs/operator/RATATUI_OPERATOR_CONSOLE.md`
- `docs/dev/PROGRESS.md`
- `docs/release/MANAGED_DEV_E2E_HANDOFF.md`
- `docs/release/STAGE_S1_1_CLOSE.md`

Forbidden:

- no app code
- no server code
- no workflow changes
- no package changes
- no Docker/runtime/production infra changes
- no generated binary artifacts
- no secrets

The allowlist must pass before any future MG371B draft PR is opened. A
disallowed path must stop the TUI before PR creation and be recorded in the
allowlist artifact.

## Future MG371B PR Policy

- one draft PR maximum
- PR title must start with:
  `MG371B First TUI-created Docs-only PR`
- PR body must include safety flags
- PR must be opened as draft
- CI must pass before ready
- no auto-merge
- no release/tag/assets
- no merge by TUI
- merge, if any, remains Codex-controller under explicit goal authorization
  after CI success

The future TUI may prepare draft PR metadata only within this policy. It must
not mark the PR ready, merge the PR, enable auto-merge or create any release,
tag or asset.

## Future MG371B TUI Action Policy

Allowed future TUI actions:

- preflight safety check
- branch name proposal
- docs-only changed-files allowlist validation
- draft PR metadata preparation
- exact authorization verification
- artifact write
- one branch creation only if authorized
- one draft PR creation only if authorized

Forbidden future TUI actions:

- no arbitrary shell
- no non-docs file write
- no task execution
- no task claim
- no worker loop
- no queue runner
- no run forever
- no live Hermes
- no MCP
- no auto-merge
- no release/tag/assets
- no production deploy
- no secrets
- no raw prompt/log/stdout/stderr/env/token dump

The TUI action path must remain a narrowly reviewed PR creation surface, not a
general execution, shell, worker, queue, deployment or release surface.

## Abort and Rollback Policy

Before branch creation:

- abort clears pending TUI PR state
- no branch/PR exists
- artifacts record `aborted_before_branch_creation=true`

After branch creation but before PR creation:

- abort must not delete branches automatically
- artifacts record `branch_created=true` and `pr_created=false`
- Codex controller must review cleanup separately

After PR creation:

- abort must not close PR automatically unless explicitly authorized
- artifacts record `branch_created=true` and `pr_created=true`
- PR remains draft
- Codex controller must review cleanup separately

Rollback and cleanup are intentionally separate from the future TUI creation
action. The first TUI-created branch/PR attempt must not silently delete
branches or close PRs as part of abort handling.

## Required Audit Artifacts for Future MG371B

Future artifact directory:

`.agent/tmp/operator-tui/mg371b-tui-created-docs-pr/`

Required artifact names:

- `mg371b-preflight.json`
- `mg371b-authorization-check.json`
- `mg371b-allowlist-check.json`
- `mg371b-branch-plan.json`
- `mg371b-pr-metadata.json`
- `mg371b-safety-report.json`
- `mg371b-action-history.json`
- `mg371b-result-report.json`

Required artifact fields:

- `authorization_phrase_matched`
- `branch_name`
- `changed_files`
- `docs_only_allowlist_passed`
- `tui_created_branch`
- `tui_created_pr`
- `pr_url`
- `pr_number`
- `draft_pr`
- `auto_merge_enabled=false`
- `release_created=false`
- `tag_created=false`
- `asset_uploaded=false`
- `token_printed=false`

Artifacts must use sanitized summaries only. They must not contain raw prompts,
logs, stdout, stderr, environment dumps, tokens, secrets, cookies, private keys
or full command output.

## MG371A Safety Boundary

- `MG371A_TUI_created_branch=false`
- `MG371A_TUI_created_PR=false`
- `real_execution_authorized=false`
- `worker_loop_authorized=false`
- `queue_runner_authorized=false`
- `run_forever_authorized=false`
- `live_hermes_authorized=false`
- `mcp_authorized=false`
- `auto_merge_authorized=false`
- `release_tag_asset_authorized=false`
- `token_printed=false`

## Evidence Artifacts

MG371A writes local, ignored design artifacts under
`.agent/tmp/operator-tui/mg371a-design-gate/`:

- `mg371a-design-report.json`
- `mg371a-design-report.md`
- `mg371a-safety-boundary.json`
- `mg371a-future-authorization-contract.json`
- `mg371a-future-allowlist.json`
- `mg371a-future-abort-policy.json`

The report schema is
`skybridge.operator_tui_mg371a_tui_created_docs_pr_authorization_design_gate.v1`.

## Next Recommendation

If MG371A passes, recommend:

`MG371B First TUI-created Docs-only PR under Explicit Authorization`

MG371B0 was inserted before MG371B as a capability-staging milestone. MG371B0
implements the TUI docs-only PR state machine, branch policy, allowlist policy,
draft PR metadata policy, provider boundary, abort policy and audit artifacts
behind disabled-by-default real-mutation gates and fake-provider smokes.

MG371B0 is not MG371B. It does not create a real TUI branch or PR, does not use
the future MG371B phrase as active real-mutation authorization, does not enable
real task execution, and does not authorize worker loops, queue runners, run
forever, auto-merge, release, tag or asset upload.

MG371B must require Jerry to provide the exact MG371B authorization phrase
before any TUI-created branch or PR:

`I_UNDERSTAND_AUTHORIZE_MG371B_FIRST_TUI_CREATED_DOCS_ONLY_BRANCH_AND_DRAFT_PR`

MG371B must remain one branch, one draft PR, docs-only, no auto-merge, no
release/tag/assets, no worker loop, no queue runner, no run forever, no live
Hermes, no MCP, no arbitrary shell and no secrets.

`token_printed=false`
