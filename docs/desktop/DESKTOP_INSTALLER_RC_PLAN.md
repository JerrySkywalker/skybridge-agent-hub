# Desktop Installer RC Plan

This is the future release plan for a Desktop installer release candidate. MG344 does not create this tag or publish installer assets.

## Proposed Future Release

- Proposed future tag: `v0.1.0-bootstrap-alpha-desktop-rc1`
- Base relationship: post-`v0.1.0-bootstrap-alpha-rc1` Desktop packaging track
- Release type: pre-release
- GitHub Release assets: published by MG346 after a separate installer-release
  authorization.
- Post-release install smoke: MG347, documented in
  [DESKTOP_INSTALLER_POST_RELEASE_SMOKE.md](DESKTOP_INSTALLER_POST_RELEASE_SMOKE.md).
- Launch console/early-exit repair: MG348, documented in
  [DESKTOP_LAUNCH_CONSOLE_EXIT_FIX.md](DESKTOP_LAUNCH_CONSOLE_EXIT_FIX.md).

## Why Not Attach To Existing RC1

`v0.1.0-bootstrap-alpha-rc1` is the Bootstrap Alpha control-plane RC. Its GitHub Release has no assets and represents the tagged source and evidence chain already audited for RC1.

Desktop installer readiness is later work on `main`. Attaching a new installer to the existing RC1 release would blur the version boundary between the tagged RC1 source and post-tag Desktop packaging work.

## Expected Artifact Types

A future Desktop installer RC may include:

- unsigned Windows installer, if produced
- portable artifact, if produced
- checksum file
- packaging audit report

No installer or binary artifact is uploaded in MG344 or MG345. MG345 may stage
fresh local artifacts under `.agent/tmp/desktop-installer-staging/` for operator
inspection only. MG346 publishes the Desktop RC1 release assets; MG347 verifies
download, checksum, manual install, first launch, and optional uninstall
checklists without creating or updating releases.
MG348 repairs the launch console/early-exit defect locally and does not publish
an RC2 installer.

## Windows Unsigned Installer Warning

Current signing status is unsigned / not configured. Windows may show a SmartScreen or unknown publisher warning for unsigned artifacts. Signing setup is not part of MG344 and requires a separate operator authorization.

## First-Run Flow

The Desktop first-run flow should stay focused on:

- selecting or confirming API base
- showing worker identity and heartbeat status
- showing safe operator panels
- keeping task execution disabled unless a future goal authorizes a narrow exact-confirmation path

## Worker Identity And Heartbeat Setup

The packaged app may show the existing worker identity and heartbeat readiness surfaces. It must not start a worker loop, claim tasks, execute tasks, or run queue processing as part of first run.

## Uninstall Guidance

A future installer RC should document:

- where app data is stored
- how to remove the Desktop app
- how to stop any separately installed worker service
- how to leave cloud/server state untouched

## Rollback Guidance

Rollback should use the prior Desktop package artifact or uninstall the Desktop app. It must not move the Bootstrap Alpha RC1 tag, recreate GitHub Releases, mutate production deployment infrastructure, or reset worker task state.

## Release Checklist

Before a future installer release:

- packaging readiness checker passes
- fresh installer staging manifest exists for the target commit
- full local Desktop package build succeeds on the target Windows host
- artifact list is audited
- checksum is generated
- unsigned warning is documented, or signing is separately configured
- Desktop safety scan passes
- no arbitrary shell or prompt execution is exposed
- no task creation, claim, or execution is introduced
- GitHub Release target and assets are reviewed

## Explicit Non-Goals

- no auto-update unless already present and separately audited
- no code signing unless separately authorized
- no public stable release
- no arbitrary execution features
- no worker loop start
- no background autonomous queue processing
- no PR creation by worker runner
- no auto-merge
- no Codex arbitrary prompt
- no MATLAB arbitrary command
- `token_printed=false`
