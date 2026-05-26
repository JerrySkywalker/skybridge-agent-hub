# Hermes Self-Bootstrap Runbook

This runbook validates the first Hermes-planned self-bootstrap loop. It is local-first, dry-run by default for notifications, and bounded to docs-only or low-risk work.

## Setup

Start the SkyBridge API:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
```

Configure Hermes locally, outside Git:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\load-hermes-env.ps1 -Json
```

Expected real values are `HERMES_API_BASE`, `HERMES_API_KEY` and optionally `HERMES_MODEL`. Keep `HERMES_API_BASE` on loopback through the private tunnel.

## Start Worker

Prepare local worker config:

```powershell
Copy-Item .\config\edge-worker.homepc.example.json .\config\edge-worker.json
```

Register and heartbeat:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -Register `
  -Heartbeat `
  -Json
```

## Submit Master Goal

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area goal `
  -Command submit `
  -Json
```

## Run One Round

Dry-run planner only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-planner.ps1 -DryRun -Json
```

Real one-round loop:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area loop `
  -Command run-once `
  -Json
```

## Run Three Rounds

Dry-run loop:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-bootstrap-loop.ps1 -DryRun -Json
```

Real bounded loop:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area loop `
  -Command run-max-rounds `
  -MaxRounds 3 `
  -Json
```

Add `-Send` only on `skybridge-self-bootstrap-loop.ps1` when one non-urgent final phone summary is desired. The CLI bridge intentionally keeps notification sends out of the short command path.

## Planner State Feedback

Real planner calls build a compact state snapshot with:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\build-planner-compact-state.ps1 -Json
```

The self-bootstrap loop stores the snapshot under `.agent/self-bootstrap/<timestamp>/compact-state-round-<n>.json` and passes it to Hermes. These snapshots are local runtime artifacts and are not committed. They include completed tasks, open tasks, open PRs, merged PRs, changed files, CI status, auto-merge defaults, locked files, duplicate dedupe keys, `do_not_repeat` and remaining acceptance status.

Hermes must not repeat any `do_not_repeat` dedupe key or create tasks that touch `locked_files` from open PRs. If acceptance is already met, Hermes should return `stop`; if PRs are still pending and no independent safe work exists, return `wait`.

## PR Lifecycle Defaults

- Child task PRs: auto PR plus auto-merge when the lifecycle classifier and merge policy mark them eligible.
- Parent/super-goal PRs: auto PR plus manual merge by default.
- High-risk PRs: auto PR for review only; no auto-merge and notify a human.
- Duplicate, stale or conflicting PRs: block, update or close only according to `config/merge-coordinator-policy.example.json`.
- Merge coordination starts in per-project serial mode.

Run a safe coordinator preview:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-merge-coordinator.ps1 -Json
```

## Pause Or Stop

- Stop the edge worker loop with `Ctrl+C`.
- Return `wait`, `stop` or `blocked` from Hermes to prevent new task creation.
- Patch the master goal to `paused`, `completed` or `blocked` through `/v1/goals/:goalId` if manual intervention is needed.

## Failure Recovery

- Planner unavailable: verify the private tunnel and local Hermes env, then rerun dry-run smoke.
- Invalid JSON: the planner retries JSON repair twice; persistent failure is blocked.
- Missing worker config: create `config/edge-worker.json` from the example and keep it uncommitted.
- Worker failure: inspect local `.agent/workers/<worker>/<task>/` logs; SkyBridge stores only summaries and PR links.
- CI failure: use `skybridge-ci-guardian.ps1` with repair attempts only under a reviewed goal.

## Security Boundaries

- No production deployment.
- No secrets, env files, tokens, cookies or private keys in commits.
- No GitHub settings mutation or force-push.
- No public Hermes exposure.
- No destructive remote commands.
- Auto-merge remains policy-gated and disabled by default.
- At most one non-urgent notification per round or one final summary, and only with explicit `-Send`.

## Required Hermes Run Reporting

All Hermes-related final reports should include:

- endpoint used, such as `/v1/responses`, `/v1/chat/completions` or `/v1/runs`;
- model name or configured model alias;
- runtime mode, such as private loopback tunnel;
- planner mode: real, dry-run or fixture;
- whether session continuity was used;
- whether tool execution was disabled, avoided or unavailable.

Do not print `HERMES_API_KEY`.
