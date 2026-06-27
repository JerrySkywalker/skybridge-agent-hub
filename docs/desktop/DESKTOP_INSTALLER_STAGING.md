# Desktop Installer Staging

Mega Goal 345 proves that the Desktop app can be freshly built and that local
Windows installer artifacts can be staged with checksums and manifest metadata.
It is not an installer release.

## Scope

MG345 follows MG344 Desktop packaging readiness:

- MG344 documented the Tauri package inventory and packaging readiness.
- MG345 performs a fresh local build/package attempt and stages local artifacts
  under `.agent/tmp`.
- MG346 used a dedicated tag,
  `v0.1.0-bootstrap-alpha-desktop-rc1`, for the Desktop installer RC release.
- MG347 verifies the published release assets with a post-release download,
  checksum, manual install, and first-launch smoke.
- MG348 repairs the post-release launch console/early-exit defect and may stage
  repaired artifacts locally under `.agent/tmp/desktop-launch-fix-staging/`,
  without publishing them.

MG345 does not create or update a GitHub Release, create or move a tag, upload
installer assets, upload binaries, configure signing, or attach anything to the
existing `v0.1.0-bootstrap-alpha-rc1` release.

## Commands

CI-safe preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-installer-staging.ps1 -Command preview -Json
```

Fresh local build/package and staging:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-installer-staging.ps1 -Command build -CleanBeforeBuild -Json
```

The build command runs:

```powershell
corepack pnpm -C apps/desktop build
corepack pnpm -C apps/desktop tauri:build
```

## Staging Paths

MG345 writes local-only staging artifacts under:

- `.agent/tmp/desktop-installer-staging/artifacts/`
- `.agent/tmp/desktop-installer-staging/checksums/SHA256SUMS.txt`
- `.agent/tmp/desktop-installer-staging/manifest.json`
- `.agent/tmp/desktop-installer-staging/desktop-installer-staging.md`

Only build artifacts such as MSI, NSIS setup EXE, or a bounded portable EXE/ZIP
may be copied into the staging directory. Raw build logs, source maps, secrets,
token files, environment files, and unrelated target files must not be staged.

## Signing Status

Current signing status is unsigned / not configured. Windows may warn that the
installer is from an unknown publisher. Code signing setup is outside MG345 and
requires a later explicit authorization.

## Safety Policy

MG345 keeps these fields false:

- `release_created=false`
- `github_release_updated=false`
- `tag_created=false`
- `tag_moved=false`
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

## Manual Inspection

After a successful staging run, inspect:

```powershell
Get-Content .\.agent\tmp\desktop-installer-staging\manifest.json
Get-Content .\.agent\tmp\desktop-installer-staging\checksums\SHA256SUMS.txt
Get-ChildItem .\.agent\tmp\desktop-installer-staging\artifacts
```

Do not execute the installer as part of MG345. Do not attach these files to
`v0.1.0-bootstrap-alpha-rc1`. Use
[DESKTOP_INSTALLER_POST_RELEASE_SMOKE.md](DESKTOP_INSTALLER_POST_RELEASE_SMOKE.md)
for the MG347 manual-assisted install smoke of the published Desktop RC1 assets.
Use [DESKTOP_LAUNCH_CONSOLE_EXIT_FIX.md](DESKTOP_LAUNCH_CONSOLE_EXIT_FIX.md)
for the MG348 repaired-package launch smoke and local staging report.
