# Ratatui Operator Console

The Ratatui Operator Console is the terminal-native SkyBridge operator surface
for staged local and hosted-dev simulations. It exists so an operator can see
the same high-level pipeline, safety state and disabled action gates from a
plain terminal before later goals add reviewed apply behavior.

This is separate from Codex TUI. Codex TUI is an agent coding interface. The
SkyBridge Operator Console is a product control-plane view for SkyBridge state:
repo/cloud status, worker pairing, campaign progress, candidate review state,
managed-dev PR state and safety flags. MG368C makes the console an
append-only/no-execution candidate review surface; it still is not an
execution runner.

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

MG368C upgrades the same console into a candidate review/append console while
preserving the MG368B local/cloud monitor. It supports this reviewed flow:

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

## Safety Policy

MG368A and MG368B are read-only. MG368C is candidate review/append only and
does not execute:

- no start_one_apply in MG368A;
- no start_one_apply in MG368B;
- no start_one_apply in MG368C;
- no start_queue_apply in MG368A;
- no start_queue_apply in MG368B;
- no start_queue_apply in MG368C;
- no `start_one_apply`;
- no `start_queue_apply`;
- no bounded action apply in MG368C;
- no worker loop;
- no queue runner;
- no run forever;
- no task creation;
- no task claim;
- no branch or PR creation by the TUI;
- no live Hermes call;
- no MCP run;
- no auto-merge;
- no release, tag or asset creation;
- no secret, env, proxy, token or log mutation;
- `token_printed=false`.

The console must not become an execution surface until MG368D or a later
reviewed gate changes that boundary.

## Future Phases

- MG368D Single-step Goal Control Gate: add one reviewed single-step control
  path with execution apply still gated.
- MG369 Manual Single-step Hosted-dev Experiment: perform the first manual
  single-step hosted-dev experiment through the TUI after the prior gates are
  reviewed.

`token_printed=false`
