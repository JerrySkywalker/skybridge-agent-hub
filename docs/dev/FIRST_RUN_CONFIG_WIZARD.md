# First-run Config Wizard

The first-run config wizard is a preview-only model for choosing local product settings before a future installer exists.

The wizard validates the safe example config, displays only redacted profile metadata, and keeps all execution capabilities disabled by construction.

Validation is provided by:

```powershell
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-config.ps1 -Command validate
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-config.ps1 -Command redaction-check
```

Rejected content includes token-like strings, Authorization headers, private keys, cookies, unsafe execution flags, raw absolute secret paths, and `token_printed=true`.
