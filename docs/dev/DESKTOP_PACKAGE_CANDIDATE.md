# Desktop Package Candidate

The Desktop package candidate is metadata-only. It previews the build command and artifact manifest without uploading, installing, publishing or creating a GitHub release.

Commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-package-candidate.ps1 -Command candidate-plan
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-desktop-package-candidate.ps1 -Command report
```

Reports:

- `.agent/tmp/packaging-preview/desktop-package-candidate.json`
- `.agent/tmp/packaging-preview/desktop-package-candidate.md`
- `.agent/tmp/packaging-preview/artifact-manifest-preview.json`

token_printed=false
