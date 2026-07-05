# MG368I Ratatui Manual Dry Run

MG368I records Jerry's first human-operated Ratatui dry run after the
MG368F nonblocking runtime, MG368G responsive layout/tabs and MG368H focused
confirmation/reason UX repairs.

## Result

- conclusion: partial pass / blocked
- operator: Jerry
- manual operation date/time: 2026-07-05 03:41 UTC
- local time: 2026-07-05 11:41 Asia/Shanghai
- baseline commit: `4e3335a4ed5e2b64d34dca71014857c3f483f52e`
- cloud version: `4e3335a4ed5e2b64d34dca71014857c3f483f52e`
- cloud image:
  `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-4e3335a4ed5e2b64d34dca71014857c3f483f52e`
- cloud health: ok
- cloud parity: ok
- terminal/window notes: not recorded in the machine-readable artifacts
- layout mode observed: not directly recorded in the artifacts
- tabs exercised: not directly recorded in the artifacts
- token_printed=false

The manual dry run was actually performed. It did not prove a passing MG368I
operator run because the exact confirmations were not accepted in the captured
artifact history. The TUI remained safe: no real task execution, branch
creation, PR creation, worker loop, queue runner, run-forever path, live
Hermes call, MCP run, auto-merge, release, tag or asset upload occurred.

## Command

Jerry opened the TUI from `V:\src\skybridge-agent-hub` with:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --output-dir .agent/tmp/operator-tui/manual-dry-run
```

## Manual Evidence

The evidence is manual-run evidence, not automated smoke proof. The source
artifacts are under `.agent/tmp/operator-tui/manual-dry-run/`.

Required MG368I summary artifacts:

- `.agent/tmp/operator-tui/manual-dry-run/manual-dry-run-state.json`
- `.agent/tmp/operator-tui/manual-dry-run/manual-dry-run-report.json`
- `.agent/tmp/operator-tui/manual-dry-run/manual-dry-run-report.md`
- `.agent/tmp/operator-tui/manual-dry-run/manual-action-history.json`
- `.agent/tmp/operator-tui/manual-dry-run/manual-artifact-index.json`
- `.agent/tmp/operator-tui/manual-dry-run/manual-safety-report.json`

Original TUI artifacts preserved:

- `.agent/tmp/operator-tui/manual-dry-run/interactive-report.json`
- `.agent/tmp/operator-tui/manual-dry-run/interactive-state.json`
- `.agent/tmp/operator-tui/manual-dry-run/last-action.json`
- `.agent/tmp/operator-tui/manual-dry-run/manual-gate.md`
- `.agent/tmp/operator-tui/manual-dry-run/operator-tui-state.json`
- `.agent/tmp/operator-tui/manual-dry-run/operator-tui-report.json`
- `.agent/tmp/operator-tui/manual-dry-run/operator-tui-candidate-report.json`
- `.agent/tmp/operator-tui/manual-dry-run/operator-tui-candidate-state.json`
- `.agent/tmp/operator-tui/manual-dry-run/generated-candidate.md`

## Operation Summary

What the artifacts prove:

- local/cloud state loaded: yes
- cloud version matched the MG368H baseline: yes
- cloud parity: ok
- nonblocking runtime usable: partially yes; queued, command-already-running
  and timeout paths were observed without freezing the captured artifact flow
- candidate fixture generated: yes
- candidate fixture validated: yes
- confirmation UX exercised: yes
- reason UX exercised: yes
- sanitized reason handling exercised: yes
- exact confirmation mismatch rejection exercised: yes
- preview bounded action attempted: yes
- start-one fixture action attempted: yes
- safe pause attempted: yes
- abort preview attempted: yes

What the artifacts do not prove:

- full/compact/tiny layout modes exercised: not directly recorded
- tab navigation exercised: not directly recorded
- review candidate accepted: no
- append candidate accepted: no
- preview bounded action completed: no
- start one fixture-safe goal completed: no
- safe pause completed: no
- abort preview completed: no

## Action History

The action history recorded these important states:

- `refresh_local_cloud_state`: blocked by `command_already_running`, then
  timed out on later attempts
- `generate_candidate_fixture`: queued, then later timed out
- `validate_candidate`: attempted while a command was already running
- `review_candidate`: blocked by `exact_confirmation_mismatch`
- `append_candidate`: blocked by `exact_confirmation_mismatch`
- `preview_bounded_action`: attempted while a command was already running
- `start_one_goal`: blocked by `exact_confirmation_mismatch`
- `safe_pause`: blocked by `exact_confirmation_mismatch`
- `abort_terminate`: blocked by `exact_confirmation_mismatch`

The final recorded action was `abort_terminate` with
`exact_confirmation_mismatch`.

## Blockers

- Exact confirmation mismatch prevented review, append, start, safe pause and
  abort completion.
- Candidate review and append did not complete.
- Single-step fixture flow did not complete.
- Safe pause reason was not accepted into a completed action.
- Abort preview reason was not accepted into a completed action.
- Tab and layout exercise were not directly evidenced in machine-readable
  artifacts.

## Warnings

- The manual TUI artifacts prove real human operation, but they do not prove
  the intended full dry-run sequence succeeded.
- Nonblocking runtime guard behavior was exercised through
  `command_already_running` and timeout states.
- Automated smoke evidence remains separate from this manual evidence.

## MG368J Follow-Up Repair

MG368I remains partial pass / blocked. MG368J was added after this run as a
focused reliability repair. It adds confirmation mismatch diagnostics, running
command guard UX, a safer manual timeout default, a manual dry-run guide mode
and machine-readable tab/layout evidence under
`.agent/tmp/operator-tui/manual-reliability/`.

MG368J does not reattempt MG368I and does not start MG369A. A new MG368I
reattempt is required before MG369A.

Recommended command for MG368I-R2:

```powershell
cargo run --manifest-path apps/operator-tui/Cargo.toml -- `
  --local-cloud `
  --manual-dry-run-guide `
  --runtime-timeout-ms 120000 `
  --output-dir .agent/tmp/operator-tui/manual-reliability
```

## Safety Flags

- TUI-created branch=false
- TUI-created PR=false
- real_task_execution_enabled=false
- real_branch_creation_enabled=false
- real_pr_creation_enabled=false
- task_created=false
- task_claimed=false
- execution_started=false
- worker_loop_started=false
- queue_runner_started=false
- run_forever_started=false
- hermes_live_called=false
- mcp_run_called=false
- auto_merge_enabled=false
- release_created=false
- tag_created=false
- asset_uploaded=false
- token_printed=false

## Boundary Statements

MG369 was not performed.

The TUI did not create a real branch or PR.

The repository PR for this document was created and merged by Codex under the
MG368I goal authorization.

## Conclusion

MG368I is a partial pass / blocked manual dry run. The operator could launch
and interact with the Ratatui surface, local/cloud status loaded, candidate
fixture generation/validation worked, and confirmation/reason safety surfaces
were exercised. The run did not satisfy the full intended dry-run sequence
because exact confirmation mismatches blocked review, append, single-step,
safe-pause and abort-preview completion.

The next milestone should not be MG369A yet. The next practical step is another
MG368I manual dry-run reattempt or a focused TUI input usability repair goal,
depending on whether the doubled input and command timeout behavior can be
reproduced.

`token_printed=false`
