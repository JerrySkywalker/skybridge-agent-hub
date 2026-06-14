# Desktop Packaging Preview

Desktop packaging preview is metadata-only. It describes the build and artifact plan but does not upload artifacts, create GitHub releases, install packages or mutate system settings.

Commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-packaging-preview.ps1 -Command desktop-build-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-packaging-preview.ps1 -Command report -Json
```

Report paths:

- `.agent/tmp/packaging-preview/desktop-packaging-preview.json`
- `.agent/tmp/packaging-preview/desktop-packaging-preview.md`

Safety:

- `uploads_artifacts=false`
- `creates_github_release=false`
- `installs_package=false`
- `mutates_system_settings=false`
- `token_printed=false`
