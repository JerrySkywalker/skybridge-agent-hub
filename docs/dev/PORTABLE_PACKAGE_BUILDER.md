# Portable Package Builder

`scripts/powershell/skybridge-portable-package.ps1` creates a repo-local portable package candidate under `.agent/tmp/portable-package`.

Safe commands:

- `status`
- `plan`
- `build-preview`
- `build-package`
- `manifest`
- `verify`
- `extract-preview`
- `extract-smoke`
- `safe-summary`
- `report`

The builder uses an allowlist of known entrypoints, scripts, docs, fixtures and UI source markers. It does not upload artifacts, create releases, install software or mutate host settings.
