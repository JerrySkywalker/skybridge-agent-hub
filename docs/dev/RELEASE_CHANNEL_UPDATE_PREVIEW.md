# Release Channel Update Preview

`scripts/powershell/skybridge-update-preview.ps1` models local release channels and update plans without performing an update.

Channels:

- `local-dev`
- `bootstrap-complete`
- `productization-preview`

Reports:

- `.agent/tmp/upgrade-preview/update-preview-report.json`
- `.agent/tmp/upgrade-preview/update-preview-report.md`

No network update, GitHub release creation, binary install, self-modification, service mutation, registry mutation or Startup mutation is allowed.

token_printed=false
