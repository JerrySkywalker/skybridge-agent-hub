# SkyBridge Desktop Client MVP

SkyBridge Desktop is the first local resident client for operators who want SkyBridge status visible outside a terminal. The MVP is intentionally conservative: it is a tray app with a read-only status window and one explicitly labeled heartbeat action.

## Scope

The current app lives in `apps/desktop` and uses Tauri v2, React, TypeScript and Vite. It is packaged as `@skybridge/desktop` with Tauri identifier `space.jerryskywalker.skybridge.desktop`.

Development commands:

- `corepack pnpm -C apps/desktop dev` starts Vite only on `127.0.0.1:1420`.
- `corepack pnpm -C apps/desktop tauri:dev` starts the full Tauri desktop app.
- `corepack pnpm -C apps/desktop tauri dev` also starts the full Tauri desktop app.

`dev` must not call `tauri dev` because Tauri already runs `corepack pnpm dev` as `beforeDevCommand`.

The MVP displays:

- worker id `laptop-zenbookduo`;
- worker status from `skybridge-worker-status.ps1 -Command status`;
- project id `skybridge-agent-hub`;
- campaign id `dev-queue-189-200`;
- current step Goal 190;
- previous step Goal 189 completed;
- active task count;
- stale lease count;
- last refresh time;
- `token_printed=false`.

## Tray

The tray menu has:

- Open SkyBridge: shows and focuses the main window.
- Refresh Status: runs the read-only status bridge and focuses the main window.
- Open Logs: opens `.agent/desktop-client/logs/`.
- Quit: exits the desktop process.

The tray does not claim tasks, start a worker loop, execute campaign steps, or start Goal 190.

## Read-only Status Bridge

The Rust bridge shells out to existing PowerShell wrappers with fixed, narrow commands:

```powershell
skybridge-status.ps1 -ActiveOnly -Json
skybridge-campaign.ps1 status -CampaignId dev-queue-189-200 -Json
skybridge-worker-status.ps1 -Command status -Json
```

The bridge writes safe metadata only to `.agent/desktop-client/status.json` and appends operational messages under `.agent/desktop-client/logs/`. These paths are ignored by git. Token contents are never written or displayed.

## Heartbeat Now

Heartbeat Now is the only MVP mutation. The UI labels it as a heartbeat mutation and calls:

```powershell
skybridge-worker-status.ps1 -Command register-heartbeat -Json
```

This refreshes worker registration/heartbeat only. It does not claim tasks, start the worker loop, run `start-one`, run `start-all`, create campaign-step tasks, create PRs, or execute Goal 190.

## Goal 190 Safety

Goal 190 remains ready/current but unexecuted. The Desktop Client MVP must not be used as an execution control surface. Before any future execution mode exists, the Pre-190 Acceptance Gate must pass and the operator must explicitly approve a bounded launch.

Goal 188I adds the readiness gate for using the desktop client before Goal 190. See [DESKTOP_CLIENT_READINESS.md](DESKTOP_CLIENT_READINESS.md) for the MVP-readiness, operator-readiness and future execution-readiness definitions, manual drill, safe log locations and validation commands.

Goal 188I follow-up also adds fixture-only desktop visual QA. It captures local screenshots under `.agent/tmp/desktop-visual-qa/` and does not call Tauri commands, production endpoints or worker token files.

## Roadmap

Future desktop work can add:

- resident heartbeat loop;
- autostart;
- standby, armed and execute modes;
- guarded control actions;
- notification integration;
- richer local logs and diagnostics;
- mode-aware confirmation flows for any future mutation.

Execution controls must remain disabled until a separate reviewed goal adds safety gates, confirmations and smokes.
