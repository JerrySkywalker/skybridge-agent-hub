# Desktop Package Candidate RC

The Desktop package candidate remains local and metadata-only for release-candidate planning.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-desktop-package-candidate.ps1 -Command report
```

Reports:
- `.agent/tmp/packaging-preview/desktop-artifact-candidate.json`
- `.agent/tmp/packaging-preview/desktop-artifact-verification.json`
- `.agent/tmp/packaging-preview/desktop-artifact-manifest.md`

No upload, install, signing, or GitHub release creation is permitted.
