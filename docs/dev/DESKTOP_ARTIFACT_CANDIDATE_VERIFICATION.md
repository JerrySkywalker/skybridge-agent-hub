# Desktop Artifact Candidate Verification

`scripts/powershell/skybridge-desktop-package-candidate.ps1` inspects only repo-local Desktop build outputs under `apps/desktop/dist`.

Allowed commands:
- `artifact-detect`
- `artifact-verify`
- `artifact-checksum-preview`
- `artifact-size-preview`
- `artifact-safe-summary`
- `report`

If no artifact exists, the status is `artifact_absent`; this is acceptable while package preview metadata is valid. The script does not upload, install, sign, create GitHub releases, or move artifacts outside the repository.

All reports are written under `.agent/tmp/packaging-preview/` with `token_printed=false`.
