# Ratatui Operator Console

The Ratatui Operator Console is the terminal-native SkyBridge operator surface
for staged local and hosted-dev simulations. It exists so an operator can see
the same high-level pipeline, safety state and disabled action gates from a
plain terminal before later goals add reviewed apply behavior.

This is separate from Codex TUI. Codex TUI is an agent coding interface. The
SkyBridge Operator Console is a product control-plane view for SkyBridge state:
repo/cloud status, worker pairing, campaign progress, candidate review state,
managed-dev PR state and safety flags. MG368E makes the console a real
interactive confirmation/action runner for the existing fixture-safe
candidate and single-step paths, but it still is not a queue runner, worker
loop, run-forever controller or unattended executor.

This is also separate from the Web/Desktop dashboard. The Web/Desktop surfaces
remain richer read-only dashboards for normal inspection. The Ratatui console
is the lightweight manual simulation surface that can run in a terminal near
the local worker and can later host narrowly reviewed operator controls.

## MG368A Scope

MG368A adds only a fixture/read-only skeleton under `apps/operator-tui`.

Allowed behavior:

- render a deterministic `skybridge.operator_tui_state.v1` fixture;
- render five panels: Header / Global Status, Pipeline Timeline, Current
  Object, Action Menu and Safety Footer;
- run interactive fixture mode;
- run non-interactive snapshot mode for CI;
- write safe snapshot/report artifacts under `.agent/tmp/operator-tui/`;
- expose active refresh, safe-summary and quit actions only.

Forbidden behavior:

- no goal append;
- no candidate approval;
- no task creation;
- no task claim;
- no branch creation;
- no PR creation;
- no merge;
- no deploy mutation;
- no Hermes live call;
- no MCP run;
- no worker loop;
- no queue runner;
- no raw prompt, log, stdout, stderr, environment or token dump.

In MG368A and MG368B, mutation-capable actions are visible in the menu but
disabled with structured reasons:

- `action_disabled_in_mg368b`
- `requires_later_reviewed_gate`
- `execution_apply_disabled`
- `mutation_not_allowed_in_read_only_monitor`

## MG368B Scope

MG368B upgrades the skeleton into a read-only local/cloud monitor. It keeps the
same Ratatui app and the same five panels, but adds live observation modes:

- `--fixture`: deterministic fixture state from MG368A;
- `--local`: read-only local Git/repository state;
- `--cloud`: read-only cloud health, version and route parity state;
- `--local-cloud`: local repository state plus cloud state in one snapshot.

The live local fields are:

- current branch;
- current HEAD;
- local `main` commit;
- `origin/main` commit;
- `main_aligned`;
- `worktree_clean`;
- bounded `git status --porcelain=v1` summary;
- repository root;
- package manager marker.

The live cloud fields are:

- `/v1/health` ok status;
- `/v1/version` commit, image ref and image tag;
- cloud route parity status through the existing parity verifier;
- missing route count when parity is unavailable or incomplete.

The Current Object panel also shows the Stage S1.1 baseline and warning state:

- tracked warning: Vite chunk-size warning non-failing;
- resolved warning: GitHub Actions Node.js 20 deprecation resolved.

Pipeline operations remain fixture/stubbed in MG368B. Candidate review,
candidate append, bounded action preview, single-step start, pause and
abort/terminate controls are still disabled until later reviewed gates.

## MG368C Scope

MG368C upgrades the same console into an append-only/no-execution candidate
review/append console while preserving the MG368B local/cloud monitor. It
supports this reviewed flow:

```text
Hermes fixture candidate -> validate candidate -> review candidate -> append candidate -> stop
```

The candidate source is fixture-only. `generate_candidate_fixture` calls the
existing Hermes planner provider fixture path and does not call live Hermes or
an external LLM. Candidate validation checks the candidate path, hash, metadata,
allowed paths, forbidden paths, validation plan and safety text. Candidate
review shows safe metadata only: title, goal id, allowed paths, forbidden
paths, validation plan, risk level and the required exact confirmation.

MG368C enabled actions:

- `refresh_local_cloud_state`
- `generate_candidate_fixture`
- `validate_candidate`
- `review_candidate`
- `append_candidate`
- `copy_safe_summary`
- `quit`

MG368C disabled actions:

- `preview_bounded_action`
- `start_one_goal`
- `safe_pause`
- `abort_terminate`

Disabled execution actions report structured reasons:

- `requires_mg368d_single_step_gate`
- `execution_apply_disabled`
- `mutation_not_allowed_for_execution`
- `worker_loop_forbidden`
- `queue_runner_forbidden`

Review approval requires this exact confirmation:

```text
I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION
```

Append apply requires this exact confirmation:

```text
I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION
```

Append apply is fixture-safe in CI. It writes reviewed/append metadata under
`.agent/tmp/goal-append/operator-tui-candidate-flow/`, leaves the appended
step pending and stops. MG368C does not start the appended goal, run a bounded
action, create a task, claim a task, create a branch, create a PR, merge,
deploy, call live Hermes, call MCP, start a worker loop or run a queue runner.

## MG368D Scope

MG368D upgrades the same console into a single-step goal control gate. The
candidate flow from MG368C remains available, and the local/cloud monitor from
MG368B remains visible. MG368D adds four gated controls:

- `preview_bounded_action`
- `start_one_goal`
- `safe_pause`
- `abort_terminate`

All actions are visible as active in the MG368D action menu:

- `refresh_local_cloud_state`
- `generate_candidate_fixture`
- `validate_candidate`
- `review_candidate`
- `append_candidate`
- `preview_bounded_action`
- `start_one_goal`
- `safe_pause`
- `abort_terminate`
- `copy_safe_summary`
- `quit`

The active menu does not mean unattended execution. Mutation-capable controls
still require exact confirmations and constrained modes.

Start-one fixture mode requires:

```text
I_UNDERSTAND_START_ONE_GOAL_SINGLE_STEP_ONLY_NO_QUEUE_LOOP
```

Safe pause requires a non-empty sanitized reason and:

```text
I_UNDERSTAND_SAFE_PAUSE_SINGLE_STEP_PIPELINE_WITH_REASON
```

Abort/terminate fixture metadata apply requires a non-empty sanitized reason
and:

```text
I_UNDERSTAND_ABORT_TERMINATE_PREVIEW_OR_FIXTURE_ONLY_NO_PROCESS_KILL
```

MG368D distinguishes three operating concepts:

- preview: read the appended candidate metadata and compute the next bounded
  action without mutating runtime state;
- fixture-safe apply: write sanitized `.agent/tmp/...` single-step metadata for
  CI and smoke tests only;
- manual mode: exact-confirmation wiring for a future human-operated path, with
  the first real experiment deferred to MG369.

The one-action-only rule is strict. A start action performs at most one
single-step gate action and stops. It must not start a queue, start all goals,
run forever, create a worker loop, run a queue runner, start parallel work or
continue after the first action.

Automated MG368D smokes are fixture-safe. In those smokes,
`start_one_goal_performed=true` means only the TUI gate metadata path was
exercised. It does not mean a real task was created, claimed or executed.
Fixture start, safe pause and abort preview keep `task_created=false`,
`task_claimed=false`, `execution_started=false`, `branch_created=false`,
`pr_created=false`, `draft_pr_created=false`, `worker_loop_started=false`,
`queue_runner_started=false`, `run_forever_started=false`,
`auto_merge_enabled=false`, `release_created=false`, `tag_created=false`,
`asset_uploaded=false` and `token_printed=false`.

MG369 is required for the first real manual single-step hosted-dev experiment
through the TUI.

## MG368E Scope

MG368E unblocks the MG369 manual experiment by adding real interactive
Ratatui action handling. The interactive loop now supports action selection,
hotkeys, exact-confirmation input, reason input, status feedback and sanitized
artifact writing.

Keyboard map:

- `r`: refresh local/cloud state;
- `g`: generate fixture candidate;
- `v`: validate candidate;
- `e`: review candidate;
- `a`: append candidate;
- `p`: preview bounded action;
- `s`: start one goal;
- `h`: safe pause;
- `x`: abort/terminate preview;
- `c`: copy/render safe summary;
- `q`: quit.

Up/Down moves the selected action and Enter activates it. Actions that require
confirmation enter confirmation-input mode inside the TUI. Safe pause and
abort/terminate first require a non-empty reason, then the exact confirmation.

Exact confirmations remain unchanged:

```text
I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION
I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION
I_UNDERSTAND_START_ONE_GOAL_SINGLE_STEP_ONLY_NO_QUEUE_LOOP
I_UNDERSTAND_SAFE_PAUSE_SINGLE_STEP_PIPELINE_WITH_REASON
I_UNDERSTAND_ABORT_TERMINATE_PREVIEW_OR_FIXTURE_ONLY_NO_PROCESS_KILL
```

Confirmation mismatches are rejected and recorded as blocked. Reason text is
sanitized before it reaches the fixture-safe runner: Authorization headers,
Bearer tokens, `token=`, `password=` and `secret=` markers are redacted, long
reasons are truncated, and `token_printed=false` remains mandatory.

Interactive actions reuse the existing MG368C/MG368D runners:

- candidate actions dispatch to fixture generation, validation, review
  approval, append preview and fixture-safe append apply;
- single-step actions dispatch to bounded preview, fixture start-one,
  reason-gated fixture pause and abort preview.

MG368E does not perform MG369. It writes this manual gate message:

```text
MG369 manual experiment can now be attempted by Jerry. This TUI supports confirmation-gated interactive actions, but real docs-only PR creation must be authorized and reported in MG369.
```

The same safety boundary remains: no real task execution, no real branch
creation, no real PR creation, no merge, no deploy, no queue runner, no worker
loop, no run forever, no live Hermes, no MCP, no auto-merge, no release, tag or
asset creation and `token_printed=false`.

## MG368F Scope

MG368F repairs the Ratatui runtime architecture after MG369 was blocked by
interactive usability risk. The observed blocker was not a missing business
capability: the TUI could freeze because the render/input loop, state
collection, PowerShell probes, candidate actions, single-step actions and
artifact writing were too tightly coupled on the interactive path.

MG368F separates the console into:

- UI render/input loop;
- ViewModel state rendered by the five existing panels;
- command request model;
- one-command background command runner;
- command result handling;
- timeout handling;
- stale-result handling;
- sanitized runtime artifact writing.

The command request model is `OperatorCommand` and covers:

- `RefreshLocalCloud`;
- `GenerateCandidateFixture`;
- `ValidateCandidate`;
- `ReviewCandidate`;
- `AppendCandidate`;
- `PreviewBoundedAction`;
- `StartOneFixture`;
- `SafePauseFixture`;
- `AbortPreview`;
- `CopySafeSummary`.

The result model records a command id, command, status, start/finish time,
duration, safe result summary, artifact paths, blockers, warnings and
`token_printed=false`. Command status values are:

- `idle`;
- `queued`;
- `running`;
- `completed`;
- `blocked`;
- `failed`;
- `timed_out`.

Interactive action dispatch now enqueues one background command and returns to
the UI loop. The UI continues rendering while the command is running and shows
a minimal runtime banner in the existing Current Object panel:

- `UI responsive while command runs`;
- current command status;
- active command label/id;
- last command result.

The one-action-only rule remains strict. If a command is running, a second
mutation-capable command is blocked with `command_already_running`. There is no
parallel candidate flow, no parallel single-step flow and no queue longer than
one active command. MG368F does not add a background queue loop.

Timeouts are enforced by the runtime. The default interactive timeout is 30
seconds, with deterministic smoke scenarios using shorter internal timeouts.
When a command times out, the ViewModel moves to `timed_out`, the UI remains
responsive, the timeout report records `timed_out=true`, and any later result
from that command is treated as stale. MG368F does not require process kill.

Stale results carry the command id/generation that produced them. If a result
arrives after timeout or after a newer command is active, it is not applied to
the current ViewModel and the runtime records `stale_result_ignored=true`.

MG368F does not retry MG369, create a docs-only experiment PR, create a real
branch, create a real PR, execute tasks, claim tasks, merge, deploy, run a
queue runner, start a worker loop, run forever, call live Hermes, call MCP,
auto-merge, create release/tag/assets or print tokens.

Runtime refactor artifacts are written under
`.agent/tmp/operator-tui/runtime-refactor/`:

- `runtime-state.json`;
- `runtime-report.json`;
- `runtime-report.md`;
- `command-history.json`;
- `timeout-report.json`;
- `stale-result-report.json`.

The runtime report schema is
`skybridge.operator_tui_runtime_refactor_report.v1`.

Deferred follow-up milestones:

- MG368H: confirmation UX hardening;
- MG368I: manual dry run;
- MG369A/B: real manual experiment after the runtime and UX work are reviewed.

## MG368G Scope

MG368G makes the Ratatui console usable in normal and small Windows Terminal
sizes without changing runtime semantics. The blocker after MG368F was visual
density: the nonblocking runtime worked, but the old five-panel vertical stack
was still too cramped for real manual operation.

The console now detects three layout modes:

- full: width >= 120 and height >= 40;
- compact: width >= 80 and height >= 24;
- tiny: below compact threshold.

Full layout keeps a persistent status header, tab bar, wide current-tab detail
area, side action/status column and command/safety footer. Compact layout keeps
only the compact status header, tab bar, current tab and footer visible. Tiny
layout does not attempt to render the full operator surface; it shows a
terminal-too-small message, current size, minimum recommended size, current
command status, `? help`, `q quit` and `token_printed=false`.

The required tabs are:

- Overview;
- Pipeline;
- Candidate;
- Single-step;
- Actions;
- Runtime;
- Safety;
- Artifacts.

Tab navigation:

- `Tab` or `]`: next tab;
- `Shift+Tab` or `[`: previous tab;
- `?`: toggle the help surface;
- `q` or Esc: quit.

The Actions tab is the compact-mode home for the full action menu. Full mode
also shows the action menu as a side panel. Tiny mode intentionally hides the
full action list and shows only minimal key hints.

Candidate, single-step, runtime, safety and artifact details are no longer
packed into one Current Object view in the live UI. They are split into their
matching tabs. Runtime status remains visible through the header/footer and
the Runtime tab, including active command, command status, last result and
timeout/stale-result notes. Safety status remains visible through the footer
and Safety tab.

MG368G writes deterministic layout artifacts under
`.agent/tmp/operator-tui/layout/`:

- `layout-state.json`;
- `layout-report.json`;
- `layout-report.md`;
- `full-snapshot.txt`;
- `compact-snapshot.txt`;
- `tiny-snapshot.txt`.

The layout report schema is `skybridge.operator_tui_layout_report.v1`.

MG368G does not retry MG369, change the command runtime semantics, execute
tasks, claim tasks, create branches or PRs by the TUI, merge, deploy, run a
queue runner, start a worker loop, run forever, call live Hermes, call MCP,
auto-merge, create release/tag/assets or print tokens.

Deferred follow-up milestones:

- MG368I: manual dry run;
- MG369A/B: real manual experiment after the runtime and UX work are reviewed.

## MG368H Scope

MG368H hardens the confirmation and reason-entry UX without changing the
MG368F runtime semantics or the MG368G layout model. The blocker after MG368G
was not command capability: exact confirmations and pause/abort reasons were
still too easy to mistype and too hard to recover from during manual use.

When an action requires exact confirmation, the TUI now switches from the
normal tabbed surface to a focused confirmation surface. It shows:

- action name;
- risk class: `fixture-safe | metadata-only | no real execution`;
- required exact confirmation string;
- current input length;
- whether the input matches exactly;
- mismatch or waiting feedback;
- keys: Enter submit, Esc cancel, Ctrl+U clear and Backspace delete;
- the rule that `q` only quits from normal mode and is treated as text input in
  confirmation mode.

Required confirmation strings are:

```text
I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION
I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION
I_UNDERSTAND_START_ONE_GOAL_SINGLE_STEP_ONLY_NO_QUEUE_LOOP
I_UNDERSTAND_SAFE_PAUSE_SINGLE_STEP_PIPELINE_WITH_REASON
I_UNDERSTAND_ABORT_TERMINATE_PREVIEW_OR_FIXTURE_ONLY_NO_PROCESS_KILL
```

If the submitted input does not match, the action is rejected, the UI remains
responsive, `exact_confirmation_mismatch` is recorded, mismatch feedback is
shown, and retry/cancel context remains visible through the input UX report.
The command runner is not invoked for mismatched confirmation.

Safe pause and abort/terminate first show a focused reason surface. The reason
must be non-empty. The surface shows a sanitized preview and then proceeds to
the exact confirmation surface after the reason is accepted. Sanitization
redacts Authorization/Bearer/token/secret/password markers, replaces
newlines/tabs with spaces and truncates overly long reasons. Raw reason text,
prompts, logs, stdout, stderr, environment values and tokens are not persisted.

Input editing is intentionally simple and paste-friendly:

- normal characters are appended as terminal key events;
- pasted text is accepted when the terminal delivers it as ordinary character
  events;
- Backspace deletes one character;
- Ctrl+U clears the current input;
- Esc cancels the input mode;
- Enter submits the current field.

The normal `?` help surface now describes tab navigation, action triggering,
confirmation mode, reason mode, cancel behavior and `token_printed=false`.
Inside confirmation and reason mode, `?` is ordinary input unless a later goal
adds a non-disruptive inline help overlay.

MG368H writes deterministic input UX artifacts under
`.agent/tmp/operator-tui/input-ux/`:

- `input-ux-state.json`;
- `input-ux-report.json`;
- `input-ux-report.md`;
- `confirmation-mismatch.json`;
- `reason-sanitization.json`;
- `confirmation-dialog-snapshot.txt`;
- `reason-dialog-snapshot.txt`.

The input UX report schema is
`skybridge.operator_tui_input_ux_report.v1`.

MG368H does not retry MG369, change command runtime semantics, execute tasks,
claim tasks, create branches or PRs by the TUI, merge, deploy, run a queue
runner, start a worker loop, run forever, call live Hermes, call MCP,
auto-merge, create release/tag/assets or print tokens.

Deferred follow-up milestones:

- MG368I: Ratatui manual dry run;
- MG369A/B: real manual experiment after MG368H and MG368I are reviewed.

## Snapshot Mode

CI and smoke tests must use snapshot mode instead of interactive raw-terminal
mode:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --fixture --snapshot --write-report --output-dir .agent/tmp/operator-tui
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --local-cloud --snapshot --write-report --output-dir .agent/tmp/operator-tui/local-cloud
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --candidate-flow --candidate-action generate --snapshot --write-report --output-dir .agent/tmp/operator-tui/candidate-flow
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --candidate-flow --candidate-action validate --snapshot --write-report --output-dir .agent/tmp/operator-tui/candidate-flow
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --candidate-flow --candidate-action review-approve --review-confirm I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION --snapshot --write-report --output-dir .agent/tmp/operator-tui/candidate-flow
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --candidate-flow --candidate-action append-apply-fixture --append-confirm I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION --snapshot --write-report --output-dir .agent/tmp/operator-tui/candidate-flow
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --single-step --single-step-action preview --snapshot --write-report --output-dir .agent/tmp/operator-tui/single-step
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --single-step --single-step-action start-fixture --start-confirm I_UNDERSTAND_START_ONE_GOAL_SINGLE_STEP_ONLY_NO_QUEUE_LOOP --snapshot --write-report --output-dir .agent/tmp/operator-tui/single-step
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --single-step --single-step-action safe-pause --pause-reason "manual hold" --pause-confirm I_UNDERSTAND_SAFE_PAUSE_SINGLE_STEP_PIPELINE_WITH_REASON --snapshot --write-report --output-dir .agent/tmp/operator-tui/single-step
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --single-step --single-step-action abort-preview --abort-reason "operator preview" --snapshot --write-report --output-dir .agent/tmp/operator-tui/single-step
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --interactive-unblocker-smoke no-real-execution --output-dir .agent/tmp/operator-tui/interactive-unblocker
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --runtime-refactor-smoke no-real-execution --output-dir .agent/tmp/operator-tui/runtime-refactor
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --layout-smoke no-real-execution --output-dir .agent/tmp/operator-tui/layout
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --input-ux-smoke no-real-execution --output-dir .agent/tmp/operator-tui/input-ux
```

Fixture snapshot mode writes:

- `.agent/tmp/operator-tui/operator-tui-snapshot.txt`
- `.agent/tmp/operator-tui/operator-tui-state.json`
- `.agent/tmp/operator-tui/operator-tui-report.json`
- `.agent/tmp/operator-tui/operator-tui-report.md`

Local-cloud snapshot mode writes:

- `.agent/tmp/operator-tui/local-cloud/operator-tui-snapshot.txt`
- `.agent/tmp/operator-tui/local-cloud/operator-tui-state.json`
- `.agent/tmp/operator-tui/local-cloud/operator-tui-report.json`
- `.agent/tmp/operator-tui/local-cloud/operator-tui-report.md`

Candidate-flow snapshot mode writes:

- `.agent/tmp/operator-tui/candidate-flow/operator-tui-candidate-snapshot.txt`
- `.agent/tmp/operator-tui/candidate-flow/operator-tui-candidate-state.json`
- `.agent/tmp/operator-tui/candidate-flow/operator-tui-candidate-report.json`
- `.agent/tmp/operator-tui/candidate-flow/operator-tui-candidate-report.md`
- `.agent/tmp/operator-tui/candidate-flow/generated-candidate.md`
- `.agent/tmp/operator-tui/candidate-flow/candidate-state.json`
- `.agent/tmp/operator-tui/candidate-flow/candidate-report.md`

Single-step snapshot mode writes:

- `.agent/tmp/operator-tui/single-step/operator-tui-single-step-snapshot.txt`
- `.agent/tmp/operator-tui/single-step/operator-tui-single-step-state.json`
- `.agent/tmp/operator-tui/single-step/operator-tui-single-step-report.json`
- `.agent/tmp/operator-tui/single-step/operator-tui-single-step-report.md`
- `.agent/tmp/operator-tui/single-step/operator-tui-single-step-preview.json`
- `.agent/tmp/operator-tui/single-step/operator-tui-single-step-preview.md`

Interactive unblocker simulation writes:

- `.agent/tmp/operator-tui/interactive-unblocker/interactive-state.json`
- `.agent/tmp/operator-tui/interactive-unblocker/interactive-report.json`
- `.agent/tmp/operator-tui/interactive-unblocker/interactive-report.md`
- `.agent/tmp/operator-tui/interactive-unblocker/last-action.json`
- `.agent/tmp/operator-tui/interactive-unblocker/manual-gate.md`

Runtime refactor simulation writes:

- `.agent/tmp/operator-tui/runtime-refactor/runtime-state.json`
- `.agent/tmp/operator-tui/runtime-refactor/runtime-report.json`
- `.agent/tmp/operator-tui/runtime-refactor/runtime-report.md`
- `.agent/tmp/operator-tui/runtime-refactor/command-history.json`
- `.agent/tmp/operator-tui/runtime-refactor/timeout-report.json`
- `.agent/tmp/operator-tui/runtime-refactor/stale-result-report.json`

Responsive layout simulation writes:

- `.agent/tmp/operator-tui/layout/layout-state.json`
- `.agent/tmp/operator-tui/layout/layout-report.json`
- `.agent/tmp/operator-tui/layout/layout-report.md`
- `.agent/tmp/operator-tui/layout/full-snapshot.txt`
- `.agent/tmp/operator-tui/layout/compact-snapshot.txt`
- `.agent/tmp/operator-tui/layout/tiny-snapshot.txt`

The report schema is `skybridge.operator_tui_report.v1`. In MG368A it must
report `fixture_used=true`, `interactive_started=false`,
`mutation_attempted=false`, `append_attempted=false`,
`approval_attempted=false`, `task_created=false`, `task_claimed=false`,
`execution_started=false`, `branch_created=false`, `pr_created=false`,
`merge_performed=false`, `deploy_triggered=false`,
`worker_loop_started=false`, `queue_runner_started=false`,
`hermes_live_called=false`, `mcp_run_called=false` and
`token_printed=false`.

In MG368B local-cloud mode it must additionally report
`mode=local-cloud`, `local_state_loaded=true`, `cloud_state_loaded=true` when
cloud is reachable, and `local_cloud_parity_checked=true` when cloud parity was
checked. If cloud configuration is unavailable, the TUI reports sanitized
blockers/warnings instead of raw response bodies.

In MG368C candidate-flow mode it reports
`skybridge.operator_tui_candidate_flow_report.v1`, `mode=candidate-flow`,
`local_state_loaded=true`, `cloud_state_loaded=true`,
`cloud_parity_shown=true`, candidate generated/validated/review/append flags,
the appended step id for fixture-safe append, and the same no-execution safety
flags. `append_performed=true` is allowed only after the exact append
confirmation and only for the fixture-safe append path.

In MG368D single-step mode it reports
`skybridge.operator_tui_single_step_report.v1`, `mode=single-step-control`,
`local_state_loaded=true`, `cloud_state_loaded=true`,
`cloud_parity_shown=true`, candidate appended state, the appended step id,
bounded preview result, start-one result, safe-pause result,
abort/terminate result, required confirmations, matched confirmations and the
same no-loop/no-execution/no-release safety flags.

In MG368E interactive-unblocker mode it reports
`skybridge.operator_tui_interactive_unblocker_report.v1`,
`mode=interactive-unblocker`, `interactive_loop_available=true`,
`keyboard_actions_registered=true`, `confirmation_input_available=true`,
`reason_input_available=true`, candidate/single-step dispatchability flags,
confirmation mismatch rejection, reason-required enforcement, sanitized reason
enforcement, `manual_gate_written=true` and the same no-real-execution safety
flags.

In MG368F runtime-refactor mode it reports
`skybridge.operator_tui_runtime_refactor_report.v1`,
`mode=runtime-refactor`, `ui_loop_nonblocking=true`,
`background_command_runner_available=true`,
`command_request_model_available=true`,
`command_result_model_available=true`, `view_model_available=true`,
`one_command_at_a_time_enforced=true`, `command_timeout_enforced=true`,
stale-result state, running-state rendering, last command status, command
history count and the same no-real-execution/no-loop/no-release safety flags.

In MG368G layout-responsive mode it reports
`skybridge.operator_tui_layout_report.v1`,
`mode=layout-responsive`, full/compact/tiny layout availability,
tab-model availability, active tab, tab list, small/tiny window support,
terminal-too-small message availability, compact action-menu availability,
runtime status visibility, safety status visibility and the same
no-real-execution/no-loop/no-release safety flags.

MG368I manual dry-run evidence is stored under
`.agent/tmp/operator-tui/manual-dry-run/` and summarized in
`docs/operator/MANUAL_DRY_RUN_MG368I.md`. The first human-operated run was
partial pass / blocked: local/cloud status loaded, candidate generation and
validation worked, and confirmation/reason surfaces were exercised, but exact
confirmation mismatches blocked review, append, start-one, safe-pause and
abort-preview completion.

MG368J is the focused manual reliability repair after MG368I. It does not
reattempt MG368I, does not start MG369A, does not create a real docs-only
managed-dev PR from the TUI and does not enable real execution. It adds:

- confirmation mismatch diagnostics with expected/actual lengths, first
  mismatch index, leading/trailing whitespace detection, CR/LF/tab detection,
  non-ASCII detection, truncated-input detection, retry guidance,
  normalization metadata and `raw_input_persisted=false`;
- one documented normalization path: a single trailing CR/LF from terminal
  paste may be trimmed, with `confirmation_normalized=true` and a recorded
  normalization reason;
- a running command guard that displays the active command, elapsed seconds and
  wait guidance, visually marks mutation-capable actions as blocked while
  running, prevents new mutation-capable commands from being enqueued and
  records `command_already_running` only when the operator tries anyway;
- an interactive manual timeout default of `120000` ms, with timeout still
  enforced and bounded smoke simulations still fast;
- `--manual-dry-run-guide`, which opens a manual guide/checklist surface for
  the next MG368I reattempt, lists all required steps, shows the current step,
  required next action, command-running/wait state, required confirmation,
  pause/abort reason suggestions and completed/blocked status without
  auto-executing any step;
- machine-readable tab/layout evidence under
  `.agent/tmp/operator-tui/manual-reliability/`.

MG368J writes:

- `.agent/tmp/operator-tui/manual-reliability/reliability-state.json`
- `.agent/tmp/operator-tui/manual-reliability/reliability-report.json`
- `.agent/tmp/operator-tui/manual-reliability/reliability-report.md`
- `.agent/tmp/operator-tui/manual-reliability/confirmation-diagnostics.json`
- `.agent/tmp/operator-tui/manual-reliability/running-guard-report.json`
- `.agent/tmp/operator-tui/manual-reliability/manual-timeout-report.json`
- `.agent/tmp/operator-tui/manual-reliability/dry-run-guide-report.json`
- `.agent/tmp/operator-tui/manual-reliability/tab-layout-history.json`

The MG368J report schema is
`skybridge.operator_tui_manual_reliability_report.v1`.

Recommended command for the next MG368I reattempt:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --manual-dry-run-guide `
  --runtime-timeout-ms 120000 `
  --output-dir .agent/tmp/operator-tui/manual-reliability
```

## MG368K Scope

MG368K repairs the operator experience before another manual dry run. It keeps
the MG368J reliability safety boundary, but adds a simpler guided path, a
bilingual interface layer, fixture-only YOLO testing and a deterministic
Codex self-drive harness.

The simplified guide is enabled with `--operator-guide` or `--simple-guide`.
It shows one operator step at a time instead of the full tabbed surface:
current step, next action, command status, safe-to-continue state, one primary
key, expected result, current blocker, compact hints and footer safety flags.
The full tab layout remains available when guide mode is not requested.

Language support is available with:

```powershell
--lang en
--lang zh-CN
```

In normal interactive mode, `L` toggles the visible UI language. Status labels,
guide steps, action labels, confirmation/reason dialog labels, running-guard
messages, timeout guidance, mismatch diagnostics, footer help, safety status
and tiny-layout warnings are translated. Exact confirmation strings are not
translated.

Fixture-only YOLO mode is enabled with `--yolo-fixture-only`. It bypasses exact
confirmation entry only for fixture-safe/no-real-execution TUI dry-run actions:
generate candidate fixture, validate candidate, review fixture metadata,
append fixture metadata, preview bounded action, start one fixture-safe goal,
safe pause fixture with a canned reason and abort preview fixture with a canned
reason. It does not enable real task execution, TUI-created branch/PR creation,
the queue runner, worker loop, run forever, live Hermes, MCP, auto-merge,
release/tag or asset upload.

Codex can exercise the full guide flow without Jerry pasting long
confirmations:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --operator-guide `
  --yolo-fixture-only `
  --self-drive-dry-run `
  --output-dir .agent/tmp/operator-tui/ux-yolo
```

`--self-drive-dry-run` is rejected unless `--yolo-fixture-only` is present.
The harness records step history, language toggles, confirmation bypass
evidence, running-guard evidence and no-real-execution safety flags, then exits
deterministically.

Recommended manual command after MG368K, before retrying a real exact
confirmation dry run:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --operator-guide `
  --yolo-fixture-only `
  --lang zh-CN `
  --runtime-timeout-ms 120000 `
  --output-dir .agent/tmp/operator-tui/ux-yolo
```

For English UI, replace `--lang zh-CN` with `--lang en`.

MG368K also hardens confirmation input behavior. Confirmation buffers start
empty when opened, action hotkeys are not inserted into confirmation text,
Ctrl+U resets the buffer to length `0`, Esc cancels and clears the buffer,
successful submit clears the buffer, mismatches keep sanitized diagnostics
without raw input, and duplicate-paste diagnostics set
`likely_duplicate_paste=true`. Bracketed paste is enabled when supported by the
terminal backend.

MG368K writes:

- `.agent/tmp/operator-tui/ux-yolo/ux-yolo-state.json`
- `.agent/tmp/operator-tui/ux-yolo/ux-yolo-report.json`
- `.agent/tmp/operator-tui/ux-yolo/ux-yolo-report.md`
- `.agent/tmp/operator-tui/ux-yolo/self-drive-report.json`
- `.agent/tmp/operator-tui/ux-yolo/bilingual-report.json`
- `.agent/tmp/operator-tui/ux-yolo/confirmation-buffer-report.json`
- `.agent/tmp/operator-tui/ux-yolo/yolo-safety-report.json`
- `.agent/tmp/operator-tui/ux-yolo/simplified-guide-snapshot.txt`
- `.agent/tmp/operator-tui/ux-yolo/simplified-guide-zh-snapshot.txt`

The MG368K report schema is
`skybridge.operator_tui_ux_yolo_report.v1`.

## MG368L Fixture-only YOLO Acceptance

MG368L clarifies acceptance after MG368K. MG368I-R3 was repeatedly blocked by
missing Jerry manual TUI evidence. For fixture-only/no-real-execution TUI
validation, Codex self-drive evidence is now sufficient.

Accepted fixture-only gate:

```text
Codex self-drive full fixture flow
```

Self-drive validation command:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --operator-guide `
  --yolo-fixture-only `
  --self-drive-dry-run `
  --lang zh-CN `
  --runtime-timeout-ms 120000 `
  --output-dir .agent/tmp/operator-tui/mg368l-self-drive
```

Manual TUI evidence is optional when all of these are true:

- `--yolo-fixture-only` is active;
- the action sequence is fixture-safe/no-real-execution;
- self-drive records `self_drive_completed_full_fixture_flow=true`;
- safety flags show no real task execution, no TUI branch/PR creation, no
  queue/worker loop, no run forever, no live Hermes, no MCP, no auto-merge and
  no release/tag/assets.

Manual TUI evidence remains mandatory for any real execution or production
mutation. Fixture-only YOLO does not authorize real task execution, TUI-created
branches or PRs, queue runners, worker loops, run forever, live Hermes, MCP,
auto-merge, releases, tags or asset uploads.

If no manual evidence exists, docs must say
`manual_verification_performed=false`. Self-drive evidence is not human proof,
and fixture-only YOLO is not production execution.

The MG368L policy note is
`docs/operator/MG368L_SELF_DRIVE_YOLO_ACCEPTANCE.md`.

## MG369A-YOLO Fixture Single-Step Experiment

MG369A-YOLO is the first MG369-class fixture-only single-step TUI experiment
under the MG368L self-drive acceptance policy. It uses the simplified guide,
fixture-only YOLO mode and Codex self-drive harness to exercise the candidate
flow, bounded single-step preview, start-one fixture action, safe pause fixture
and abort preview fixture without enabling real execution.

Experiment command:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --operator-guide `
  --yolo-fixture-only `
  --self-drive-dry-run `
  --lang zh-CN `
  --runtime-timeout-ms 120000 `
  --output-dir .agent/tmp/operator-tui/mg369a-yolo
```

MG369A-YOLO writes sanitized fixture-only artifacts under
`.agent/tmp/operator-tui/mg369a-yolo/`, including
`mg369a-yolo-report.json`, `mg369a-yolo-report.md`,
`mg369a-action-history.json`, `mg369a-safety-report.json` and
`mg369a-artifact-index.json`.

The experiment report is
`docs/operator/MG369A_YOLO_FIXTURE_SINGLE_STEP_EXPERIMENT.md`.

MG369A-YOLO does not claim human-operated validation passed, does not perform
real execution and does not allow the TUI to create a real branch or PR.

## Safety Policy

MG368A and MG368B are read-only. MG368C is candidate review/append only.
MG368D is a single-step gate with fixture-safe CI paths and manual-mode wiring
for a future goal. MG368E adds interactive input and dispatch for those same
fixture-safe paths. The safety boundary remains:

- no start_one_apply in MG368A;
- no start_one_apply in MG368B;
- no start_one_apply in MG368C;
- no unconfirmed start_one_goal in MG368D;
- no unconfirmed interactive action in MG368E;
- no blocking action execution on the interactive UI path in MG368F;
- no runtime semantic change in MG368G;
- no start_queue_apply in MG368A;
- no start_queue_apply in MG368B;
- no start_queue_apply in MG368C;
- no start_queue_apply in MG368D;
- no `start_one_apply`;
- no `start_queue_apply`;
- no bounded action apply in MG368C;
- no unbounded execution in MG368D;
- no MG369 docs-only PR creation in MG368E;
- no MG369 retry in MG368F;
- no MG368I reattempt or MG369A start in MG368J;
- no real execution, TUI branch/PR creation, queue/worker loop, live Hermes,
  MCP, auto-merge, release/tag/assets or exact-confirmation bypass outside
  fixture-only mode in MG368K;
- no start all;
- no worker loop;
- no queue runner;
- no run forever;
- no parallel execution;
- no task creation;
- no task claim;
- no branch or PR creation by the TUI;
- no live Hermes call;
- no MCP run;
- no auto-merge;
- no release, tag or asset creation;
- no secret, env, proxy, token or log mutation;
- `token_printed=false`.

The console must not become a queue runner, worker loop, run-forever
controller or unattended executor.

## Future Phases

- MG368I-R3 Ratatui Manual Dry Run with Simplified Guide and Fixture-only YOLO:
  superseded for fixture-only acceptance by MG368L self-drive YOLO policy.
- MG369A-YOLO Fixture Single-Step Experiment: passed as a fixture-only
  self-drive report. It was not real execution and not human-operated
  validation.
- MG369B-YOLO Fixture Experiment Review Gate: continue only under a separate
  explicit goal. Any future real execution still requires explicit human
  authorization.

`token_printed=false`
