# Sandboxed Installer Candidate

`scripts/powershell/skybridge-installer-candidate.ps1` creates a repo-local installer candidate under `.agent/tmp/installer-candidate/`.

This is not a host installer. It stages entrypoints, launcher scripts, doctor/demo scripts, and runbooks, then verifies an install root under `.agent/tmp/installer-candidate/install-root`.

Allowed writes:

- `.agent/tmp/installer-candidate/dist/`
- `.agent/tmp/installer-candidate/stage/`
- `.agent/tmp/installer-candidate/install-root/`

Forbidden behavior:

- registry writes
- Startup folder writes
- scheduled tasks
- service creation
- powercfg mutation
- PATH mutation
- uploads
- manual GitHub Release creation
- worker execution or queue apply

`token_printed=false`
