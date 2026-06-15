# Portable Local Bundle Policy

The portable bundle is metadata and script layout only. It is not an installer.

Policy:

- `host_mutation_allowed=false`
- `install_allowed=false`
- `upload_allowed=false`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `execution_enabled=false`
- `queue_apply_enabled=false`
- worker, workunit, claim, task PR and generic queue apply routes remain excluded

Verification is handled by `scripts/powershell/skybridge-portable-bundle.ps1 -Command verify`.
