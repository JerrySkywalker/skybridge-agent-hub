# Server-Side Supervisor Option

SkyBridge can evolve toward server-side supervision, but the current pilot keeps execution local and bounded.

## Mode A: Local Execution, Cloud Hermes Supervision

This is the current supported mode.

- Windows runs Codex, Git, GitHub CLI, auto-merge sweep and local validation scripts.
- The Hermes API remains private behind an SSH tunnel.
- Hermes health and capabilities are checked through `http://127.0.0.1:18642`.
- GitHub branch protection and required checks remain the merge gate.
- Bootstrap ntfy provides the phone fallback path.

Safe commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-hermes-tunnel.ps1 -CheckOnly
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\watch-hermes-health.ps1 -Once
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-hermes-nightly-pilot.ps1 -UseHermesApi
```

## Mode B: Future Cloud Worker Clone

This is not implemented in the current pilot.

A future server-side worker could clone SkyBridge, run a constrained queue worker and report back to the operator. That requires a separate design for host isolation, secret storage, repo credentials, audit logs, update/rollback and rate limits.

For now:

- do not deploy a worker;
- do not run Codex on the production server;
- do not edit `/opt`, OpenResty, Authelia, 1Panel or Docker daemon configuration;
- do not expose Hermes publicly;
- do not enable WSS remote execution.

## Read-Only Hermes Health Inspection

From an operator shell that already has private access to the server, use read-only checks only:

```bash
curl -fsS http://127.0.0.1:8642/health
curl -fsS http://127.0.0.1:8642/v1/capabilities
```

Do not paste API keys into logs. If the server requires authorization, set the header only in a private shell and avoid shell history capture.

## Bootstrap Notification Env Guidance

Keep notification configuration outside Git. On a future server-side worker, use private environment management equivalent to the local `$HOME\.skybridge\bootstrap-notify.env.ps1` file:

```powershell
$env:SKYBRIDGE_BOOTSTRAP_NTFY_URL = "https://ntfy.sh"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC = "<private-topic>"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN = "<optional-token>"
```

Record only configured/skipped/sent status in docs or PRs. Do not record topics, tokens, webhook URLs or credentials.

## Rollback And Disable Checklist

For the current local pilot:

1. Disable the Windows Task Scheduler entry if one was created manually.
2. Stop the SSH tunnel process.
3. Remove `HERMES_API_BASE` and `HERMES_API_KEY` from the current shell.
4. Move local Hermes and bootstrap env files out of `$HOME\.skybridge\` if the machine is no longer trusted.
5. Run `start-hermes-tunnel.ps1 -CheckOnly` and `watch-hermes-health.ps1 -Once` to confirm the local supervisor path is disabled or degraded as expected.

For any future server worker:

1. Stop the worker service.
2. Revoke worker GitHub and notification credentials.
3. Preserve sanitized logs for audit.
4. Rotate Hermes and notification credentials if exposure is suspected.
5. Verify no public listener was added for Hermes.
