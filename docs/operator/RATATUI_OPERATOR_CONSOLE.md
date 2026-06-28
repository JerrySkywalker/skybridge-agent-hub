# Ratatui Operator Console

The Ratatui Operator Console is the terminal-native SkyBridge operator surface
for staged local and hosted-dev simulations. It exists so an operator can see
the same high-level pipeline, safety state and disabled action gates from a
plain terminal before later goals add reviewed apply behavior.

This is separate from Codex TUI. Codex TUI is an agent coding interface. The
SkyBridge Operator Console is a product control-plane view for SkyBridge state:
repo/cloud status, worker pairing, campaign progress, candidate review state,
managed-dev PR state and safety flags.

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

All mutation-capable actions are visible in the menu but disabled with
structured reasons:

- `action_disabled_in_mg368a`
- `requires_later_reviewed_gate`
- `execution_apply_disabled`
- `mutation_not_allowed_in_fixture`

## Snapshot Mode

CI and smoke tests must use snapshot mode instead of interactive raw-terminal
mode:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- --fixture --snapshot --write-report --output-dir .agent/tmp/operator-tui
```

Snapshot mode writes:

- `.agent/tmp/operator-tui/operator-tui-snapshot.txt`
- `.agent/tmp/operator-tui/operator-tui-state.json`
- `.agent/tmp/operator-tui/operator-tui-report.json`
- `.agent/tmp/operator-tui/operator-tui-report.md`

The report schema is `skybridge.operator_tui_report.v1`. In MG368A it must
report `fixture_used=true`, `interactive_started=false`,
`mutation_attempted=false`, `append_attempted=false`,
`approval_attempted=false`, `task_created=false`, `task_claimed=false`,
`execution_started=false`, `branch_created=false`, `pr_created=false`,
`merge_performed=false`, `deploy_triggered=false`,
`worker_loop_started=false`, `queue_runner_started=false`,
`hermes_live_called=false`, `mcp_run_called=false` and
`token_printed=false`.

## Safety Policy

MG368A is read-only and fixture-only:

- no start_one_apply in MG368A;
- no start_queue_apply in MG368A;
- no `start_one_apply`;
- no `start_queue_apply`;
- no worker loop;
- no run forever;
- no auto-merge;
- no release, tag or asset creation;
- no secret, env, proxy, token or log mutation;
- `token_printed=false`.

The console must not become an execution surface until a later reviewed gate
changes that boundary.

## Future Phases

- MG368B Ratatui Read-only Local/Cloud Monitor: replace fixture-only status
  with read-only local/cloud observation while preserving disabled apply gates.
- MG368C Candidate Review/Append Console: add reviewed candidate inspection and
  append workflow behind explicit safety gates.
- MG368D Single-step Goal Control Gate: add one reviewed single-step control
  path with execution apply still gated.
- MG369 Manual Single-step Hosted-dev Experiment: perform the first manual
  single-step hosted-dev experiment through the TUI after the prior gates are
  reviewed.

`token_printed=false`
