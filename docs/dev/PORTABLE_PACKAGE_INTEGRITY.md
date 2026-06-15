# Portable Package Integrity

The integrity check verifies the repo-local portable package candidate without uploading it, installing it, or mutating host settings.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-artifact-integrity.ps1 -Command report
```

The report records sanitized package path, source commit, manifest checksum, package checksum when an archive exists, included entrypoints, forbidden exclusion patterns, and clean-room verification status.

Safety boundary:

- `upload_allowed=false`
- `install_allowed=false`
- `host_mutation_allowed=false`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `execution_enabled=false`
- `queue_apply_enabled=false`
- `token_printed=false`

