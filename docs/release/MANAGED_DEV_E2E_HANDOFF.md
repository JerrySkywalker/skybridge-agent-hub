# Managed Dev E2E Handoff

This document freezes the managed development end-to-end capability baseline
through Stage S1.1, closing MG351-MG366C.

## Current State

- Current main commit: `c2bd551370f68950c2cd759de6a4f30b5e0396d8`
- Current cloud image:
  `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-c2bd551370f68950c2cd759de6a4f30b5e0396d8`
- Cloud health: `/v1/health` ok
- Cloud version: `/v1/version` matches the current main commit
- Cloud parity: ok
- `token_printed=false`

## Capability Matrix

| Milestone | Capability | Status | Manual entrypoint |
| --- | --- | --- | --- |
| M1 | Tool Provider Inventory | Complete. Direct provider available; Codex and MATLAB detected; Hermes optional/unavailable; MCP future. | `scripts/powershell/manual-tool-provider-check.ps1` |
| M2 | Single Goal Loop | Complete. Fixture passed and live `safe-local-smoke` passed after heartbeat apply. | `scripts/powershell/manual-single-goal-loop-test.ps1` |
| M3 | Static Multi-Step Campaign | Complete. Fixture sequenced safe-local-smoke, MATLAB, and Codex-report steps with evidence. | `scripts/powershell/manual-multi-goal-loop-test.ps1` |
| M4 | Local Codex Goal Markdown Generator | Complete. Fixture and local Codex generate-one passed; candidate remained unimported. | `scripts/powershell/manual-local-goal-generate-test.ps1` |
| M5 | Goal Append Review/Import | Complete. Candidate review, approval, and metadata append passed with no execution. | `scripts/powershell/manual-goal-append-review-test.ps1` |
| M6 | Bounded Goal Budget Loop | Complete. Ready-step, reviewed append, proposed generation, and budget-exhausted hold scenarios passed. | `scripts/powershell/manual-bounded-goal-loop-test.ps1` |
| M7 | Managed Development PR Pilot | Complete. Controller-native Git/GH path repaired; draft PR creation, CI observation, and human-review gate proven. | `scripts/powershell/manual-managed-dev-pr-pilot.ps1` |
| M8 | Campaign-Driven Managed Dev E2E | Complete. Reviewed goal to campaign step to bounded action to draft PR to CI to human review and merge gate passed. | `scripts/powershell/manual-managed-dev-campaign-test.ps1` |

## Post-Freeze Real Task

MG365 is the first managed-dev v2 real low-risk task after the M1-M8 freeze.
It inventories warning hygiene only:

- `docs/dev/WARNING_INVENTORY.md`
- `scripts/powershell/skybridge-warning-inventory.ps1`

The inventory tracks Vite chunk-size warnings and GitHub Actions Node.js 20
deprecation annotations as non-failing, tracked, and not suppressed. It does
not remediate either warning class, does not change build configuration, does
not change GitHub workflows, and does not alter CI thresholds. Remediation
requires a future explicit goal.

MG366B is the first warning remediation goal after that inventory. It updates
only Docker GitHub Action major versions to Node.js 24 runtime candidates and
does not change workflow topology, permissions, triggers, secrets, deploy
targets, Docker build semantics, warning suppression or CI thresholds. See
`docs/dev/ACTIONS_NODE_RUNTIME_HYGIENE.md`.

MG366A analyzes the remaining Vite chunk-size warning without changing build
behavior. It records the current oversized web and desktop entry chunks, likely
single-entry bundle causes, and remediation options. It does not suppress the
warning, raise Vite thresholds, change CI, change dependencies or perform
runtime chunk splitting. See `docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md`.

MG366C adds the Hermes Planner Provider Pilot as an advisory-only provider
surface. Fixture mode can generate one unapproved candidate markdown file, but
Hermes cannot approve, append, create tasks, execute, create branches or PRs,
merge, deploy, run worker loops or mutate `project_control`. Direct providers
remain the execution path. See
`docs/orchestrator/HERMES_PLANNER_PROVIDER.md`.

MG368A starts the Ratatui Operator Console as the next-stage manual simulation
surface. It is fixture/read-only only, shows the pipeline layout and safety
state, and keeps candidate append, goal start, task claim, worker loops, Hermes
live calls and MCP runs disabled until later reviewed gates.

MG368B keeps the same read-only boundary and adds live monitor value: the TUI
can read local Git branch/HEAD, local `main` and `origin/main` alignment,
bounded worktree status, cloud `/v1/health`, cloud `/v1/version`, cloud image
tag and route parity. It still does not append goals, approve candidates, start
goals, pause, terminate, create branches or PRs, merge, deploy, call Hermes
live, call MCP, start a worker loop or run a queue runner.

MG368C keeps the MG368B local/cloud monitor and enables one reviewed candidate
flow through the Ratatui console: fixture Hermes candidate generation,
candidate validation, review preview, exact-confirmed approval for append, and
fixture-safe append metadata. It is append-only/no-execution. It does not start
the appended goal, run a bounded action, create or claim tasks, create branches
or PRs, merge, deploy, call live Hermes, call MCP, start a worker loop or run a
queue runner.

MG368D keeps the MG368C candidate flow and adds the Ratatui single-step goal
control gate. The TUI can preview the next bounded action, exercise a
fixture-safe start-one gate, record a reason-gated fixture-safe pause, and
preview abort/terminate metadata. It remains one-action-only: no queue runner,
no worker loop, no run forever, no unbounded execution, no branch or PR
creation in CI, no merge, no deploy, no live Hermes, no MCP, no auto-merge, no
release/tag/assets and `token_printed=false`. The first real manual
hosted-dev experiment belongs to MG369.

MG368E is the Ratatui interactive unblocker added after the first MG369
attempt correctly stopped at the manual gate. It adds real keyboard action
selection, exact-confirmation input, reason input, status feedback and
sanitized artifacts for the existing MG368C/MG368D fixture-safe runners. It
does not perform MG369, create the docs-only experiment PR, execute tasks,
claim tasks, create branches or PRs by the TUI, merge, deploy, run a queue
runner, start a worker loop, run forever, call live Hermes, call MCP,
auto-merge, create release/tag/assets or print tokens.

MG368F is the Ratatui runtime architecture repair added after MG369 was blocked
again by interactive freeze risk. It splits the UI render/input loop from the
ViewModel, command request queue, one-command background runner, command result
handling, timeout handling, stale-result handling and sanitized runtime
artifacts. The TUI can now remain responsive while a fixture-safe command is
running, show `queued`/`running`/terminal command status, block a second command
with `command_already_running`, mark timed-out commands as `timed_out` and
ignore late stale results by command id. It does not retry MG369, execute
tasks, claim tasks, create branches or PRs by the TUI, merge, deploy, run a
queue runner, start a worker loop, run forever, call live Hermes, call MCP,
auto-merge, create release/tag/assets or print tokens.

MG368G is the Ratatui responsive layout and tabs repair added after MG368F.
It keeps the nonblocking runtime semantics unchanged but replaces the live
fixed five-panel stack with full, compact and tiny layout modes. Full mode
uses a status header, tab bar, current-tab detail area, side action/status
column and footer. Compact mode renders only the current tab plus header and
footer. Tiny mode renders a terminal-too-small message, current/minimum size,
command status, help/quit hints and `token_printed=false`. Tabs split the dense
operator details into Overview, Pipeline, Candidate, Single-step, Actions,
Runtime, Safety and Artifacts. MG368G does not retry MG369, execute tasks,
claim tasks, create branches or PRs by the TUI, merge, deploy, run a queue
runner, start a worker loop, run forever, call live Hermes, call MCP,
auto-merge, create release/tag/assets or print tokens.

MG368H is the Ratatui confirmation and reason UX hardening milestone added
after MG368G. It keeps runtime semantics unchanged and adds focused
confirmation/reason surfaces, visible exact confirmation strings, input length
and match feedback, Backspace, Ctrl+U clear, Esc cancel, Enter submit,
paste-friendly character input, non-empty reason enforcement, sanitized reason
preview and deterministic input UX artifacts. Confirmation mismatch is rejected
without dispatch and recorded as `exact_confirmation_mismatch`. Reason
sanitization redacts Authorization/Bearer/token/secret/password markers,
normalizes newlines/tabs and truncates long reasons. MG368H does not retry
MG369, execute tasks, claim tasks, create branches or PRs by the TUI, merge,
deploy, run a queue runner, start a worker loop, run forever, call live Hermes,
call MCP, auto-merge, create release/tag/assets or print tokens.

MG368I is the first human-operated Ratatui manual dry run after MG368F/G/H.
Jerry launched the TUI in `--local-cloud` mode with artifacts under
`.agent/tmp/operator-tui/manual-dry-run/`. The run is recorded as partial
pass / blocked: local/cloud state loaded at
`4e3335a4ed5e2b64d34dca71014857c3f483f52e`, cloud parity was ok, fixture
candidate generation and validation worked, and confirmation/reason surfaces
were exercised. The full intended sequence did not complete because exact
confirmation mismatches blocked review, append, start-one, safe pause and
abort-preview completion. MG368I did not perform MG369, execute tasks, claim
tasks, create branches or PRs by the TUI, merge, deploy, run a queue runner,
start a worker loop, run forever, call live Hermes, call MCP, auto-merge,
create release/tag/assets or print tokens. See
`docs/operator/MANUAL_DRY_RUN_MG368I.md`.

MG368J is a repair milestone for the MG368I blockers. It adds confirmation
mismatch diagnostics, running command guard UX, a `120000` ms manual timeout
default, manual timeout guidance, `--manual-dry-run-guide` and
machine-readable tab/layout evidence under
`.agent/tmp/operator-tui/manual-reliability/`. MG368J does not reattempt
MG368I, does not start MG369A, does not create a TUI branch/PR and does not
enable real execution. The next milestone remains MG368I-R2 before MG369A.

MG368K follows the blocked MG368I-R2 manual operation and simplifies the
Ratatui operator experience before another human dry run. It adds
`--operator-guide`, `--lang en`, `--lang zh-CN`, the normal-mode `L` language
toggle, `--yolo-fixture-only` and `--self-drive-dry-run`. The self-drive
harness only runs in fixture-only mode and writes
`.agent/tmp/operator-tui/ux-yolo/` evidence. MG368K does not perform MG369,
execute real tasks, create TUI branches or PRs, start queue/worker loops, run
forever, call live Hermes or MCP, auto-merge, create release/tag/assets or
print tokens. The next milestone is MG368I-R3 with the simplified guide and
fixture-only YOLO path.

MG368L supersedes MG368I-R3 manual proof as a blocker for fixture-only
acceptance. The accepted fixture-only gate is Codex self-drive full fixture
flow with `self_drive_completed_full_fixture_flow=true`,
`yolo_fixture_only=true`, `raw_input_persisted=false` and
`token_printed=false`. Manual TUI evidence is optional only for the
fixture-only/no-real-execution stage and must be reported as
`manual_verification_performed=false` when absent. This is not a claim that
human-operated TUI validation passed, and it does not authorize real
execution, TUI-created branch/PR creation, queue/worker loops, live Hermes,
MCP, auto-merge, releases, tags or assets.

MG369A-YOLO is the first fixture-only single-step TUI experiment after the
MG368L policy update. It used Codex self-drive, `--yolo-fixture-only`, the
simplified guide and a `120000` ms timeout to exercise candidate generation,
candidate validation, fixture metadata review/append, bounded single-step
preview, start-one fixture, safe pause fixture and abort preview fixture.
Evidence is under `.agent/tmp/operator-tui/mg369a-yolo/`, with the report
schema `skybridge.operator_tui_mg369a_yolo_report.v1`. The result is a
fixture-only self-drive pass, not real execution and not human-operated
validation. The TUI did not create a real branch or PR, did not create or claim
tasks, did not start execution, did not start queue/worker loops, did not run
forever, did not call live Hermes or MCP, did not auto-merge and did not create
release/tag/assets. `token_printed=false`.

MG369B-YOLO reviews and freezes the MG369A-YOLO fixture-only success boundary.
It records `fixture_experiment_result=pass`, but explicitly rejects broader
interpretations: not real execution, not human-operated validation, not
production hosted development, not authorization for TUI-created real
branches/PRs, and not authorization for worker loops or queue runners. The
review artifacts are under `.agent/tmp/operator-tui/mg369b-yolo-review/`.
The next recommended milestone is MG369C-YOLO Controlled Docs-only PR Creation
Simulation. Do not proceed directly to real execution.

MG369C-YOLO executes that recommendation as a metadata-only TUI simulation. It
adds `--simulate-docs-pr` to the self-drive fixture-only path and records a
simulated docs-only PR lifecycle from `not_started` through
`completed_simulation`. The simulated changed file is docs-only:
`docs/operator/MG369C_YOLO_DOCS_ONLY_PR_SIMULATION.md`. The TUI does not create
that file during simulation, does not create a real branch or PR, does not run
`git push`, does not run `gh pr create`, does not call the GitHub API, does not
start execution, does not start queue/worker loops and does not create
release/tag/assets. Evidence is under `.agent/tmp/operator-tui/mg369c-yolo/`
with schema `skybridge.operator_tui_mg369c_yolo_docs_pr_simulation.v1`.
`token_printed=false`.

MG369D-YOLO reviews and freezes the MG369C-YOLO docs-only PR simulation
evidence. It records the controlled docs-only PR creation simulation as pass,
but only as a metadata-only simulation: not real PR creation, not real branch
creation, not real execution and not human-operated validation. The review
keeps `real_pr_creation_authorized=false`,
`tui_real_branch_pr_authorized=false`, `real_execution_authorized=false`,
`worker_loop_authorized=false`, `queue_runner_authorized=false`,
`TUI_created_branch=false`, `TUI_created_PR=false`, `git_push_called=false`,
`gh_pr_create_called=false`, `github_api_called=false` and
`token_printed=false`. Review artifacts are under
`.agent/tmp/operator-tui/mg369d-yolo-review/` with schema
`skybridge.operator_tui_mg369d_yolo_docs_pr_simulation_review_gate.v1`.

MG370A is the first real docs-only PR creation milestone after MG369D. It is
explicitly authorized for exactly one Codex-controller docs-only branch and one
draft PR. This does not authorize TUI-created real branches or PRs, real task
execution, worker loops, queue runners, run forever, live Hermes, MCP,
auto-merge, release, tag or asset upload. The branch is
`codex/mg370a-first-real-docs-only-pr`; the report is
`docs/operator/MG370A_FIRST_REAL_DOCS_ONLY_PR_CREATION.md`. The draft PR is
PR #302:
`https://github.com/JerrySkywalker/skybridge-agent-hub/pull/302`.

MG370B reviews MG370A and records
`MG370A Codex-controller docs-only PR creation: pass`. It confirms PR #302 was
created by Codex controller, not TUI, passed the docs-only allowlist, passed CI,
merged, completed post-merge workflows, deployed successfully and verified cloud
parity ok. MG370B freezes `TUI-created branch=false`, `TUI-created PR=false`,
`real_task_execution_enabled=false`, `real_execution_authorized=false`,
`tui_real_branch_pr_authorized=false`, `worker_loop_authorized=false`,
`queue_runner_authorized=false`, `auto_merge_enabled=false`,
`release_created=false`, `tag_created=false`, `asset_uploaded=false` and
`token_printed=false`. Review artifacts are under
`.agent/tmp/operator-tui/mg370b-review/` with schema
`skybridge.operator_tui_mg370b_codex_controller_docs_pr_review_gate.v1`.

## Stage S1.1 Close

MG367 closes Stage S1.1 as a roadmap-freeze milestone. The stage close records
the final MG351-MG366C main/cloud baseline, keeps the same safety boundaries,
and adds only read-only audit and smoke wiring. See
`docs/release/STAGE_S1_1_CLOSE.md` and
`scripts/powershell/skybridge-stage-s1-1-close.ps1`.

## PR Evidence

- PR #267: Tool Provider Contract and Local Direct Provider Inventory
- PR #268: Local+Cloud Single Goal Loop Controller
- PR #269: Multi-Step Static Campaign Loop
- PR #270: Local Codex Goal Markdown Generator
- PR #271: Goal Append Review and Import
- PR #272: Bounded Goal Budget Loop
- PR #273: Managed Development PR Pilot
- PR #274: closed, not merged, superseded fallback proof
- PR #275: Managed Dev Git/GH Provider Repair
- PR #276: merged controller-native managed-dev pilot proof
- PR #277: Campaign-Driven Managed Dev E2E implementation
- PR #278: managed-dev campaign delegate repair
- PR #279: merged campaign-driven managed-dev pilot proof
- PR #280: Managed Dev E2E handoff and capability freeze
- PR #281: Warning inventory real task
- PR #282: GitHub Actions Node runtime hygiene
- PR #283: Vite chunk warning analysis
- PR #284: Hermes Planner Provider Pilot

## Safety Boundary

- No auto-merge by default.
- No unbounded loop.
- No worker loop.
- No queue runner.
- No release, tag, or asset mutation.
- No production infrastructure mutation.
- No arbitrary shell surface.
- No Codex generation or execution unless a future exact goal authorizes it.
- No MATLAB, Hermes, or MCP execution.
- Hermes planner/provider output requires human review before append and cannot
  execute in the same invocation.
- No task creation or claim outside explicitly scoped safe/manual goals.
- No unsanitized prompts, logs, process streams, sensitive browser/session
  material, provider auth material, proxy profiles, or environment snapshots in
  reports.
- `token_printed=false`

## Manual Audit

Run a read-only local handoff audit:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-dev-e2e-handoff.ps1 -Command audit -ExpectedCommit c2bd551370f68950c2cd759de6a4f30b5e0396d8 -ExpectedCloudImage ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-c2bd551370f68950c2cd759de6a4f30b5e0396d8 -Json -WriteReport
```

The audit is read-only. It must not mutate Git, GitHub PR state, deployment,
tasks, worker state, or provider state.

## Known Warnings

- Existing Vite chunk-size warnings remain non-failing, tracked and analyzed in
  `docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md`.
- GitHub Actions Node.js 20 deprecation annotations for Docker actions were
  remediated by MG366B action-version hygiene.
- Cloud deploy workflow run selection hygiene may need a future cleanup if older
  failed workflow runs are still selected by legacy verification helpers.

## Recommended Next Milestones

After MG370B, continue only under a new explicit goal:

1. MG370C Codex-controller Docs-only PR Repetition if MG370B passes.
2. Any real execution path requires explicit human authorization.
3. Any TUI-created real branch or PR requires a separate later milestone after
   MG370B and a repeatability gate.

`token_printed=false`
