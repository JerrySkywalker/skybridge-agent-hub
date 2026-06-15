# Stop Hook Timeout Runbook

For a message such as `Stop hook failed: hook timed out after 30s`:

1. Run `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-stop-hook-diagnostics.ps1 -Command analyze-timeout`.
2. Run `-Command cleanup-preview` if stale safe metadata is suspected.
3. Inspect `.agent/tmp/local-launcher/stop-hook-diagnostics.json`.
4. Avoid reading raw logs or killing arbitrary processes.

Likely safe explanations include long post-run hooks, slow cleanup, stale child process metadata, blocked file handle, network wait, large report write or unknown.
