# Update Channel Manifest Preview

The update channel manifest is an offline preview. It describes local channels and artifact checksums without downloading, installing, or writing outside the repository staging area.

Channels:

- `local-dev`
- `portable-package-rc`
- `sandbox-installer-rc`
- `installer-promotion-rc`

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-channel-manifest.ps1 -Command report -Json
```

The manifest keeps `network_update_allowed=false`, `manual_upload_allowed=false`, `github_release_manual_creation_allowed=false`, and `token_printed=false`.
