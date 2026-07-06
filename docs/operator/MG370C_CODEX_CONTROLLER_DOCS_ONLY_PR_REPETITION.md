# MG370C Codex-controller Docs-only PR Repetition

## Baseline

Baseline commit:
`03742457dea2344eed79b574ec46743b65baec25`

Cloud version before PR creation:
`03742457dea2344eed79b574ec46743b65baec25`

Cloud image before PR creation:
`ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-03742457dea2344eed79b574ec46743b65baec25`

Previous gate:
`MG370B Review Gate for Codex-controller Docs-only PR Creation`

Previous gate result:
`codex_controller_docs_pr_result=pass`

## Authorization

- `second_real_docs_only_pr_creation_authorized=true`
- `authorized_by=Jerry`
- `actor=codex_controller`
- `scope=one docs-only branch and one draft PR`
- `TUI-created branch=false`
- `TUI-created PR=false`

The explicit authorization string for this milestone is:

`I_UNDERSTAND_AUTHORIZE_MG370C_SECOND_REAL_DOCS_ONLY_BRANCH_AND_DRAFT_PR_BY_CODEX_CONTROLLER_ONLY`

The PR lifecycle authorization string for this milestone is:

`I_UNDERSTAND_CODEX_MAY_CREATE_PUSH_OPEN_READY_AND_MERGE_MG370C_REAL_DOCS_ONLY_PR_AFTER_CI_SUCCESS`

## Repetition Details

- branch name:
  `codex/mg370c-codex-controller-docs-pr-repeat`
- PR number:
  `#304`
- PR URL:
  `https://github.com/JerrySkywalker/skybridge-agent-hub/pull/304`
- PR title:
  `MG370C Codex-controller Docs-only PR Repetition`
- changed files:
  - `docs/operator/MG370C_CODEX_CONTROLLER_DOCS_ONLY_PR_REPETITION.md`
  - `docs/operator/MG370B_CODEX_CONTROLLER_DOCS_ONLY_PR_REVIEW_GATE.md`
  - `docs/operator/RATATUI_OPERATOR_CONSOLE.md`
  - `docs/dev/PROGRESS.md`
  - `docs/release/MANAGED_DEV_E2E_HANDOFF.md`
  - `docs/release/STAGE_S1_1_CLOSE.md`
- docs-only allowlist check:
  passed locally before draft PR creation; final PR allowlist is recorded in
  the goal report
- CI status:
  pending final PR CI on the branch revision that includes the PR metadata
  update
- review gate status:
  draft PR first; ready and merge are allowed only after CI success
- merge status:
  pending final PR CI, ready transition and merge
- cloud parity after deploy:
  pending post-merge deploy verification if Deploy Cloud runs

This branch and PR are created by Codex controller. They are not created by the
TUI and do not enable TUI-created branch or PR behavior.

## Safety Boundary

- `TUI-created branch=false`
- `TUI-created PR=false`
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
- `token_printed=false`

## Evidence Artifacts

MG370C writes local, ignored evidence artifacts under
`.agent/tmp/operator-tui/mg370c-real-docs-pr-repeat/`:

- `mg370c-report.json`
- `mg370c-report.md`
- `mg370c-safety-report.json`
- `mg370c-pr-lifecycle.json`
- `mg370c-allowlist-check.json`

The report schema is
`skybridge.operator_tui_mg370c_real_docs_only_pr_repetition.v1`.

## Conclusion

Conclusion: pass after the second Codex-controller docs-only PR is created,
CI-passed, marked ready, merged and verified in cloud under this goal
authorization.

If it passes, MG370C proves Codex-controller docs-only PR creation is
repeatable across at least two real docs-only PRs.

This does not authorize TUI-created real PRs.

This does not authorize real task execution.

This does not authorize worker loop, queue runner or run forever.

This does not authorize auto-merge, release, tag or asset upload.

This does not authorize non-docs changes.

## Next Recommendation

If MG370C passes, proceed to
`MG370D Review Gate for Codex-controller Docs-only PR Repeatability`.

Do not proceed directly to TUI-created PRs.

`token_printed=false`
