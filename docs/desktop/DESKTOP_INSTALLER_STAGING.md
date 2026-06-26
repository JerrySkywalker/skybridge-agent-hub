# Desktop Installer Staging

Mega Goal 345 proves that the Desktop app can be freshly built and that local
Windows installer artifacts can be staged with checksums and manifest metadata.
It is not an installer release.

## Scope

MG345 follows MG344 Desktop packaging readiness:

- MG344 documented the Tauri package inventory and packaging readiness.
- MG345 performs a fresh local build/package attempt and stages local artifacts
  under `.agent/tmp`.
- A later installer release goal, likely MG346, should use a dedicated tag such
  as `v0.1.0-bootstrap-alpha-desktop-rc1`.

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
`v0.1.0-bootstrap-alpha-rc1`. The future Desktop installer RC should get its own
reviewed tag, release body, checksum file, and upload authorization.
