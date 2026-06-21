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
forbidden actions and the next safe action. It excludes raw logs, raw prompts,
raw Hermes responses, raw notification payloads, tokens, cookies, secrets and
environment dumps.

## Status

`blocked` means a hard preview/convergence gate failed: cloud version is
unavailable, cloud commit does not match local HEAD, route parity failed,
non-deferred readiness blockers remain, requested heartbeat refresh failed, an
unsafe mutation flag is true, notification dry-run safety is unsafe, or any
child report indicates token output.

`partial` means there are no hard preview blockers, cloud commit aligns and a
worker is online or heartbeat was refreshed, but warning-class or
execution-deferred items remain. Goal 317 reports `not_on_main`,
`worktree_dirty` and `admin_escalation_unavailable` under
`deferred_execution_blockers` during PR development instead of treating them as
preview blockers, because Goal 317 validation does not authorize execution.

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

## Smoke

```powershell
corepack pnpm smoke:self-bootstrap-converge
```

The smoke is fixture-only. It covers non-main branch blocking, cloud commit
mismatch, partial status with warnings, heartbeat refresh failure, heartbeat
safety flag passthrough, unsafe mutation flags and `token_printed=false`.
