# Desktop Packaging Readiness

Mega Goal 344 starts the post-RC1 Desktop packaging track. This document records what is package-ready now, what remains blocked or warning-classified, and what must stay disabled before an installer release.

## Current Inventory

- Desktop app location: `apps/desktop`
- Framework: Tauri v2 with a React/Vite frontend
- Package manager: `pnpm` through Corepack
- Frontend build command: `corepack pnpm -C apps/desktop build`
- Local package command: `corepack pnpm -C apps/desktop tauri:build`
- Tauri config: `apps/desktop/src-tauri/tauri.conf.json`
- Rust package manifest: `apps/desktop/src-tauri/Cargo.toml`
- App name: `SkyBridge Desktop`
- App identifier: `space.jerryskywalker.skybridge.desktop`
- App version: `0.1.0`
- Windows target status: bundle config is active with `targets: all`
- Icon status: `icons/icon.png` and `icons/icon.ico` are configured and present
- Signing status: unsigned, not configured
- Expected output directories:
  - `apps/desktop/dist`
  - `apps/desktop/src-tauri/target/release/bundle`

## Artifact Status

The readiness checker can inspect existing local artifacts without uploading them. A package build may produce unsigned Windows artifacts such as:

- `apps/desktop/src-tauri/target/release/bundle/msi/*.msi`
- `apps/desktop/src-tauri/target/release/bundle/nsis/*-setup.exe`

Existing local artifacts are for inspection only. MG344 does not publish installers, upload binaries, attach assets to a GitHub Release, or create a Desktop release tag.

MG345 adds the fresh-build staging layer. See
[DESKTOP_INSTALLER_STAGING.md](DESKTOP_INSTALLER_STAGING.md) for the command
that runs a clean local Desktop build/package attempt, stages only installer
artifacts under `.agent/tmp/desktop-installer-staging/`, and writes checksums
and a manifest without uploading anything.

## Known Warnings

- `signing_not_configured`: Windows code signing is not configured.
- `unsigned_installer_expected`: Windows users should expect unsigned installer warnings until a separate signing goal authorizes and configures signing.
- `desktop_safety_static_scan_only`: the checker verifies the Desktop source
  statically; it does not prove every rendered control state. MG345 reuses this
  static Desktop safety check while staging artifacts.
- `local_build_not_attempted`: CI-safe smokes use preview/report mode and do not require a full Tauri build.

## Known Blockers

There is no current packaging blocker in preview mode after MG344's metadata check. A future full build can still fail closed with explicit categories such as:

- `node_dependency_missing`
- `rust_missing`
- `tauri_cli_missing`
- `windows_sdk_missing`
- `webview2_missing`
- `desktop_package_build_failed`

## Bootstrap Alpha RC1 Boundary

- Bootstrap Alpha RC1 remains tagged as `v0.1.0-bootstrap-alpha-rc1`.
- The RC1 tag remains attached to commit `4473257548bd0fc26e05002d968f8525b37bac8b`.
- Desktop packaging readiness is post-RC1 work on `main`.
- A real installer release requires a later dedicated tag and release, for example `v0.1.0-bootstrap-alpha-desktop-rc1`.
- No Desktop installer is attached to the existing `v0.1.0-bootstrap-alpha-rc1` GitHub Release by MG344.

## Disabled In Packaged App

These capabilities must remain absent or disabled in Desktop packaging:

- arbitrary shell
- arbitrary prompt execution
- queue runner
- worker loop
- live apply without exact-confirmation-only PowerShell path
- MATLAB arbitrary command
- Codex arbitrary prompt
- PR creation
- auto-merge
- background autonomous execution

The Desktop app is an operator surface for status, preview, handoff, and explicit safe flows. It must not become an arbitrary execution surface as part of packaging readiness.

## Checker

Run the CI-safe readiness check:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-packaging-readiness.ps1 -Command build-preview -Json
```

Write a local safe report:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-packaging-readiness.ps1 -Command audit -WriteReport -Json
```

Reports are written under:

- `.agent/tmp/desktop-packaging/desktop-packaging-readiness.md`
- `.agent/tmp/desktop-packaging/desktop-packaging-readiness.json`

Reports must keep these safety fields false:

- `release_created=false`
- `tag_created=false`
- `tag_moved=false`
- `github_release_updated=false`
- `installer_uploaded=false`
- `binary_uploaded=false`
- `task_created=false`
- `task_claimed=false`
- `execution_started=false`
- `codex_run_called=false`
- `matlab_run_called=false`
- `worker_loop_started=false`
- `project_control_unpaused=false`
- `token_printed=false`

## Full Local Build

A full local package attempt is optional and manual in MG344:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-packaging-readiness.ps1 -Command build-local -Json
```

The command does not sign, upload, release, tag, claim tasks, run Codex, run MATLAB, or mutate deployment infrastructure. If local prerequisites are missing, it reports a blocker instead of pretending the package is ready.
