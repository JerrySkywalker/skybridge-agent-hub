# Stop Hook Diagnostics

`scripts/powershell/skybridge-stop-hook-diagnostics.ps1` explains bounded stop-hook timeouts using safe metadata only.

Supported commands:

- `status`
- `analyze-timeout`
- `cleanup-preview`
- `safe-summary`
- `report`

The diagnostic does not read raw hook logs, persist raw logs, kill arbitrary processes or mutate host settings. `token_printed=false`
