# Installer Artifact Provenance

Installer artifact provenance records the source commit, source tag state, sanitized package path, package checksum, and checksum pointers to related safe reports.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-installer-promotion.ps1 -Command artifact-provenance -Json
```

The provenance contract keeps `manual_upload_allowed=false`, `github_release_manual_creation_allowed=false`, `host_mutation_allowed=false`, and `token_printed=false`.
