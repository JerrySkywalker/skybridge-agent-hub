# Desktop Client Readiness Before Goal 190

SkyBridge Desktop is a standby operator tool. It is not an execution surface.

## Readiness Levels

MVP-readiness means:

- tray menu is available;
- status refresh is read-only;
- Heartbeat Now is the only mutation;
- no task execution controls exist;
- local metadata stays under `.agent/desktop-client/`;
- `token_printed=false` is preserved.

Operator-readiness before Goal 190 means:

- local desktop build and Rust check pass;
- status diagnostics are deterministic and structured;
- unknown status fields produce WARN, not false PASS;
- active tasks or stale leases produce BLOCK;
- Goal 190 current/ready state is visible;
- Goal 190 linked task ids and linked PR URLs are visible and must be zero;
- safe logs and `status.json` remain local-only;
- full Tauri bundle status is known.

Future execution-readiness is separate. It must be added only by a later reviewed goal with mode-aware confirmations, approval checks, audit, smokes and explicit operator approval.

## Allowed Actions

The desktop app may:

- show read-only SkyBridge status;
- call `skybridge-status.ps1 -ActiveOnly -Json`;
- call `skybridge-campaign.ps1 status -CampaignId dev-queue-189-200 -Json`;
- call `skybridge-worker-status.ps1 -Command status -Json`;
- call `skybridge-worker-status.ps1 -Command register-heartbeat -Json` from Heartbeat Now;
- write `.agent/desktop-client/status.json`;
- append concise local logs under `.agent/desktop-client/logs/`.

## Forbidden Actions

The desktop app must not:

- run `start-one` or `start-all`;
- run campaign `execute-step`;
- claim tasks;
- start `skybridge-edge-worker.ps1`;
- start any worker loop;
- create campaign-step-derived tasks;
- create PRs;
- execute Goal 190;
- print, display or persist tokens, raw Authorization headers, raw prompts, raw stdout/stderr or raw worker logs.

## Start The App

For development readiness:

```powershell
corepack pnpm -C apps/desktop tauri dev
```

For packaged readiness after local prerequisites are installed:

```powershell
corepack pnpm -C apps/desktop tauri build
```

## Verify It Is Safe

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-package.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-tauri-config.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-readonly-bridge.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-no-task-execution.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-readiness-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-safe-metadata.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-pre190-gate.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-heartbeat-only.ps1
```

Every smoke must return JSON with `ok=true` and `token_printed=false`.

## Pre-190 Readiness

The panel shows PASS only when:

- active tasks are `0`;
- stale leases are `0`;
- `token_printed=false`;
- current goal is `super-190-campaign-run-report-evidence-ledger`;
- current goal status is `ready`;
- Goal 190 linked task ids count is `0`;
- Goal 190 linked PR URLs count is `0`.

The panel shows WARN when any required field is unknown. Treat WARN as not accepted for Goal 190 unless the operator explicitly accepts dev-run-only readiness.

The panel shows BLOCK when active tasks, stale leases, token output, linked Goal 190 task ids or linked Goal 190 PR URLs are present. Stop and inspect before doing anything else.

Confirm Goal 190 is still unexecuted with:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command preflight -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command report -Json
```

Expected fields are active tasks `0`, stale leases `0`, current step `dev-queue-189-200:super-190-campaign-run-report-evidence-ledger`, no Goal 190 linked task ids, no Goal 190 linked PR URLs and `token_printed=false`.

## Logs And Local Files

Safe to inspect and paste:

- `.agent/desktop-client/status.json`;
- concise lines from `.agent/desktop-client/logs/desktop-client.log` after checking they contain no local machine secrets.

Local-only logs:

- anything under `.agent/desktop-client/logs/`;
- worker logs under `.agent/workers/`;
- campaign runner logs under `.agent/campaign-runners/`;
- Codex raw run logs or JSONL.

Do not paste raw worker logs, raw Codex logs, prompts, stdout/stderr, tokens or Authorization headers.

## Failure Handling

If status refresh fails:

1. Leave the app in standby.
2. Inspect the Bridge Warnings section.
3. Run the preflight command above from a terminal.
4. Treat unknown active task or stale lease fields as WARN until confirmed.

If worker heartbeat fails:

1. Do not start a worker loop.
2. Check the worker profile and token file outside the repository.
3. Run `skybridge-worker-status.ps1 -Command status -Json`.
4. Use Heartbeat Now again only after profile/token configuration is fixed.

If `active_tasks > 0` or `stale_leases > 0`:

1. Stop before Goal 190.
2. Run `skybridge-dev-queue-control.ps1 -Command report -Json`.
3. Inspect task and lease evidence through the existing runbooks.
4. Do not clear leases or tasks from the desktop app.

## Stop The App

Use the tray menu `Quit`, or close the desktop process from the terminal running `tauri dev`.

## Manual Operator Drill

Do not run unsafe actions during this drill.

1. Start the app:

```powershell
corepack pnpm -C apps/desktop tauri dev
```

2. Verify the window opens.
3. Verify tray items: Open SkyBridge, Refresh Status, Open Logs, Quit.
4. Verify the mode strip shows `STANDBY / READ ONLY`, `HEARTBEAT ONLY MUTATION` and `EXECUTION DISABLED`.
5. Verify campaign, safety gate and Pre-190 readiness fields.
6. Click Refresh Status.
7. Click Heartbeat Now (heartbeat-only).
8. Confirm no task was created, no task was claimed, no PR was created, no worker loop started, and Goal 190 remains unexecuted:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command preflight -Json
```

9. Inspect `.agent/desktop-client/status.json`.
10. Inspect `.agent/desktop-client/logs/`.
11. Confirm `token_printed=false`.
12. Confirm `git status --short` is clean except ignored `.agent/desktop-client/` metadata.

## Bundle Status

Goal 188I requires a real bundle attempt:

```powershell
corepack pnpm -C apps/desktop tauri build
```

If this fails because local Windows/Tauri prerequisites are missing, desktop readiness is not fully bundle-accepted. Goal 190 should not proceed until either the bundle passes or the operator explicitly accepts dev-run-only readiness.

Goal 188I bundle validation passed after adding the existing Windows `.ico` file to the Tauri bundle icon list. The successful build produced MSI and NSIS installer artifacts under `apps/desktop/src-tauri/target/release/bundle/`, which remains ignored build output.

## Next Operator Action

After this goal merges, run the desktop readiness smokes and the Tauri bundle command from clean latest `main`. Only after those pass, or after explicit operator acceptance of a documented bundle blocker, prepare a separate bounded Goal 190 run.
