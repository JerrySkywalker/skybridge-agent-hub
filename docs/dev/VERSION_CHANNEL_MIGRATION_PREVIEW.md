# Version Channel Migration Preview

The channel migration preview is local metadata only.

Previewed transition:

- from `v1.5.0-portable-package-rc`
- to `v1.6.0-clean-room-portable-acceptance-rc`
- channel: `local`

The preview does not contact GitHub, does not download binaries, does not upload artifacts and does not create a GitHub release.

Command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-upgrade-rollback-sandbox.ps1 -Command migration-preview
```

The migration model uses the sandbox upgrade sequence: snapshot current to previous, stage package under `.agent/tmp/install-sandbox/staging/`, replace current from staging and preserve previous for rollback. `token_printed=false`.
