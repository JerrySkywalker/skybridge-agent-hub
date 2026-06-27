# Desktop Launch Console And Early Exit Fix

MG348 repairs the Desktop RC1 launch defect found during the MG347
post-release install smoke.

## MG347 Observed Issue

- Installer type used: unsigned NSIS setup EXE.
- Checksum verification passed before install.
- Manual install completed.
- Installed executable existed and reported version `0.1.0`.
- A brief unexpected cmd window appeared after install/launch.
- No SkyBridge Desktop window was clearly observed.
- No SkyBridge Desktop process remained running after 5 seconds.
- No cmd, MATLAB, Codex, or SkyBridge service process remained afterward.

## Root Cause

Two native launch issues were found in the Tauri Desktop app:

- `apps/desktop/src-tauri/src/main.rs` did not declare the Windows GUI
  subsystem for release builds.
- Passive startup status probes spawned `pwsh` without Windows hidden-window
  creation flags.

Those issues could make a packaged Windows app show a console window during
normal startup. Missing local worker config, offline cloud state, and failed
status probes remain nonfatal and should render warning state instead of
closing the app.

## Fix Applied

- Added the release Windows GUI subsystem attribute at the binary crate root:
  `#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]`.
- Added hidden Windows creation flags for passive `pwsh` status bridge
  invocations.
- Added a bounded diagnostic script:
  `scripts/powershell/skybridge-desktop-launch-diagnostics.ps1`.

The diagnostic script is read-only by default. It launches the app only when
`-AllowLaunch` is supplied and caps launch attempts at three.

## Launch Smoke Method

CI-safe static checks:

```powershell
corepack pnpm smoke:desktop-launch-diagnostics-status
corepack pnpm smoke:desktop-launch-diagnostics-inspect
corepack pnpm smoke:desktop-launch-no-console-fixture
corepack pnpm smoke:desktop-launch-no-fatal-missing-config
corepack pnpm smoke:desktop-launch-safety
corepack pnpm smoke:desktop-launch-report
```

Local package launch smoke after a fresh build:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-launch-diagnostics.ps1 -Command package-launch-check -AllowLaunch -TimeoutSeconds 10 -MaxAttempts 3 -WriteReport -Json
```

Expected result:

- no unexpected cmd or PowerShell console window
- process remains alive through the timeout unless manually closed
- main window is detectable or operator-observable
- no task claim
- no Codex execution
- no MATLAB execution
- no worker loop
- no project control unpause
- `token_printed=false`

## Local Staging

If the fresh package launch smoke passes, repaired installer artifacts may be
staged locally under:

- `.agent/tmp/desktop-launch-fix-staging/artifacts/`
- `.agent/tmp/desktop-launch-fix-staging/checksums/SHA256SUMS.txt`
- `.agent/tmp/desktop-launch-fix-staging/manifest.json`
- `.agent/tmp/desktop-launch-fix-staging/desktop-launch-fix-report.md`

These artifacts are inspection-only in MG348.

## MG348 Local Result

The fresh package launch diagnostic passed on the repaired local build:

- app version: `0.1.0`
- window title detected: `SkyBridge Desktop`
- process alive after 10 seconds: `true`
- unexpected console window detected: `false`
- cmd process detected: `false`
- PowerShell process with visible window detected: `false`
- Codex process detected: `false`
- MATLAB process detected: `false`
- SkyBridge worker service installed: `false`

Local staged repaired artifacts:

- `.agent/tmp/desktop-launch-fix-staging/artifacts/SkyBridge Desktop_0.1.0_x64_en-US.msi`
  - size bytes: `3186688`
  - SHA256: `0a3af392e4567d9d59d46532146cfb181d3ef3abf71989f0cff4162d48d8fbe7`
- `.agent/tmp/desktop-launch-fix-staging/artifacts/SkyBridge Desktop_0.1.0_x64-setup.exe`
  - size bytes: `2154243`
  - SHA256: `0c7aee48d6c98d9c8d4191cbae7e787d394bd1a4f8662d786125263a86e294ac`

Local reports:

- `.agent/tmp/desktop-launch-diagnostics/desktop-launch-diagnostics.md`
- `.agent/tmp/desktop-launch-diagnostics/desktop-launch-diagnostics.json`
- `.agent/tmp/desktop-launch-fix-staging/manifest.json`
- `.agent/tmp/desktop-launch-fix-staging/desktop-launch-fix-report.md`
- `.agent/tmp/desktop-launch-fix-staging/checksums/SHA256SUMS.txt`

## Limitations

- The Desktop installer remains unsigned.
- Launch diagnostics are bounded local checks, not a full installer
  publication.
- Static Desktop safety checks do not replace a later manual RC2 install smoke.
- The app may still report worker/cloud setup warnings when local config is
  missing or the worker is offline.

## MG348 No-Release Policy

MG348 does not create or move tags, create or update GitHub Releases, upload
installer assets, upload binaries, run task workers, run Codex, run MATLAB, or
start a worker loop.

## Future RC2 Path

If MG348 passes, a later goal may create a separate Desktop RC2 release, for
example `v0.1.0-bootstrap-alpha-desktop-rc2`. That release must rebuild from
its exact tag target, upload fresh assets, verify checksums, and keep the
existing `v0.1.0-bootstrap-alpha-rc1` and
`v0.1.0-bootstrap-alpha-desktop-rc1` releases unchanged.

`token_printed=false`
