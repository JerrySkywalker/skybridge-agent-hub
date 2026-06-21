# Self-Bootstrap Convergence

Goal 316 adds `skybridge-self-bootstrap-converge.ps1` as the one-command
operator check for the current self-bootstrap state. It replaces the manual
sequence of reading git status, cloud version JSON, route parity output,
worker heartbeat proof, readiness JSON and task hygiene JSON.

The command is safe by default. It runs read-only checks and emits a compact
`skybridge.self_bootstrap_convergence.v1` report. It does not execute tasks,
claim tasks, requeue tasks, archive tasks, write evidence, unpause
`project_control`, call `start-one`, call `run-until-hold`, run Codex or print
tokens.

## Run

```powershell
. "$HOME\.skybridge\skybridge.env.ps1"
. "$HOME\.skybridge\worker.env.ps1"

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-self-bootstrap-converge.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -RefreshHeartbeat `
  -Json
```

`-RefreshHeartbeat` is explicit because heartbeat is the only allowed mutation
in this command. The refresh path delegates to
`skybridge-worker-heartbeat-proof.ps1 -HeartbeatOnly` and must still prove:

```text
tasks_claimed=false
codex_run_called=false
queue_apply_called=false
campaign_metadata_advanced=false
start_one_called=false
run_until_hold_called=false
project_control_unpaused=false
token_printed=false
```

Useful reporting options:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-self-bootstrap-converge.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -OutputJsonFile .agent\tmp\self-bootstrap-convergence.json `
  -OutputMarkdownFile .agent\tmp\self-bootstrap-convergence.md `
  -Json
```

The Markdown report is intentionally compact. It includes status, blockers,
warnings, cloud/local commit alignment, worker status, hygiene counts,
execution second-gate status, start-one preview status, forbidden actions and
the next safe action. It excludes raw logs, raw prompts, raw Hermes responses,
raw notification payloads, tokens, cookies, secrets and environment dumps.

## Status

`blocked` means a hard preview/convergence gate failed: cloud version is
unavailable, cloud commit does not match local HEAD, route parity failed,
non-deferred readiness blockers remain, requested heartbeat refresh failed, an
unsafe mutation flag is true, notification dry-run safety is unsafe, or any
child report indicates token output.

`partial` means there are no hard preview blockers, cloud commit aligns and a
worker is online or heartbeat was refreshed, but warning-class or
execution-deferred items remain. Goal 317 reports `not_on_main` and
`worktree_dirty` under `deferred_execution_blockers` during PR development
instead of treating them as preview blockers, because Goal 317 validation does
not authorize execution. Goal 318 also remains `partial` when
`execution_second_gate.execution_forbidden=true` or
`start_one_preview.status=no_safe_candidate`.

When no real notification or admin escalation provider is configured, the
bootstrap notifier can satisfy blocker notice support for dry-run convergence
only. In that state convergence should show
`notification_readiness.blocker_notice_supported=true` and should not report
`admin_escalation_unavailable`. It still keeps `can_start_one=false` and
`can_run_until_hold=false` until a later execution-class goal proves real
admin escalation readiness.

`pass` means no blockers, no readiness warnings, cloud commit aligns, a worker
is online and all safety flags remain clean.

At this stage `partial` is acceptable. It proves the cloud and local state are
converged enough for preview planning while keeping all execution gates closed.

## Goal 317 Boundary

Goal 317 extends convergence with:

- task hygiene apply preview status;
- notification readiness dry-run status;
- residual task hygiene warnings;
- an explicit next safe action.

The recommended next safe action from a partial result is to keep
`project_control` paused and review the Goal 317 preview/dry-run outputs.
Goal 317 PR validation must not run live `-Apply`. The operator may run the
metadata-only apply command only after merge, with the exact confirmation
string, and only for the fixed task ids documented in
[TASK_HYGIENE_APPLY.md](TASK_HYGIENE_APPLY.md).

`start-one` remains forbidden until Goal 318 or a later explicit
execution-class goal opens a separate gate.

## Goal 318 Boundary

Goal 318 extends convergence with:

- `execution_second_gate.status`;
- `start_one_preview.status`;
- `start_one_preview.selected_candidate`, when a safe candidate exists;
- `execution_forbidden`;
- `can_start_one_false_reason`.

The expected Goal 318 live convergence remains:

```text
status=partial
readiness.project_control_state=paused
readiness.can_start_one=false
readiness.can_run_until_hold=false
execution_second_gate.allowed_preview_only=true
execution_second_gate.allowed_execution=false
start_one_preview.would_claim=false
start_one_preview.would_run_codex=false
token_printed=false
```

Convergence may include a selected candidate from the preview, but that is not
authorization to claim it. The selected candidate is a review target for a
future Goal 319 apply pilot only.

## Smoke

```powershell
corepack pnpm smoke:self-bootstrap-converge
```

The smoke is fixture-only. It covers non-main branch blocking, cloud commit
mismatch, partial status with warnings, heartbeat refresh failure, heartbeat
safety flag passthrough, execution second-gate and start-one preview summaries,
unsafe mutation flags and `token_printed=false`.
