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

`blocked` means a hard convergence gate failed: local branch is not `main`,
the worktree is dirty, cloud version is unavailable, cloud commit does not
match local HEAD, route parity failed, readiness has blockers, requested
heartbeat refresh failed, an unsafe mutation flag is true, or any child report
indicates token output.

`partial` means there are no blockers, cloud commit aligns and a worker is
online or heartbeat was refreshed, but warning-class items remain. The current
expected live state is partial because Goal 315 task hygiene warnings, Hermes
exposure and Notification Center readiness are still warning-level work.

`pass` means no blockers, no readiness warnings, cloud commit aligns, a worker
is online and all safety flags remain clean.

At this stage `partial` is acceptable. It proves the cloud and local state are
converged enough for preview planning while keeping all execution gates closed.

## Goal 317 Boundary

The recommended next safe action from a partial result is a Goal 317 apply
plan that may repair evidence metadata and record keep-blocked/archive
decisions. Goal 316 does not apply those changes. It only reports the current
state and preserves the execution boundary.

## Smoke

```powershell
corepack pnpm smoke:self-bootstrap-converge
```

The smoke is fixture-only. It covers non-main branch blocking, cloud commit
mismatch, partial status with warnings, heartbeat refresh failure, heartbeat
safety flag passthrough, unsafe mutation flags and `token_printed=false`.
