# Codex Hooks Setup

Example hook config is stored at:

```text
config/codex/hooks.example.json
```

For user-level use, preview the generated config first:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\install-codex-hooks.ps1
```

Install only after reviewing the dry-run output:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\install-codex-hooks.ps1 -Apply
```

The installer writes `~/.codex/hooks.json`, backs up an existing hooks file under `~/.codex/skybridge-backups`, and writes no secrets. Restore the latest backup with:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\restore-codex-hooks.ps1 -Apply
```

This starter includes:

```text
scripts/powershell/codex-dashboard-hook.ps1
scripts/powershell/codex-guard-hook.ps1
```

The dashboard hook sends normalized events to `/v1/events`.

The dashboard hook is fail-open: if the server is offline, Codex continues and normalized redacted events are queued under `.agent/spool/codex-hook` by default. Override with `SKYBRIDGE_CODEX_SPOOL_DIR`.

Set these optional environment variables:

```text
SKYBRIDGE_API_BASE=http://127.0.0.1:8787
SKYBRIDGE_NODE_ID=local-dev
CODEX_DASHBOARD_TOKEN=
SKYBRIDGE_CODEX_SPOOL_DIR=
```

The hook maps `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest` and `Stop` into `skybridge.agent_event.v1`. It does not upload full commands, prompts, patch bodies, stdout or stderr by default; it only sends bounded summaries.

The guard hook blocks high-risk destructive commands, force pushes to protected branches and obvious secret material. It is intended for `PreToolUse`.

## Test and Replay

Run fixture tests through the exact hook script path:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\test-codex-hook-event.ps1 -RequireSpool
```

Replay queued events after SkyBridge comes back:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\replay-codex-hook-spool.ps1
```

Run the full local integration smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-hook-integration.ps1 `
  -ApiBase http://127.0.0.1:8787
```

## Troubleshooting

- Server offline: events remain in `queue.jsonl`; run `replay-codex-hook-spool.ps1` after `/health` succeeds.
- Hook not firing: verify `~/.codex/hooks.json`, command paths and PowerShell execution policy.
- Invalid payload: run `test-codex-hook-event.ps1`; optional JSON fields must be omitted rather than serialized as `null`.
- Spool replay still failing: check `SKYBRIDGE_API_BASE`, server `/v1/events` validation response and local firewall rules.
- Redaction concerns: inspect `events.jsonl`; it should contain normalized redacted events only, never raw hook stdin.
- Windows path issues: prefer the installer because it generates absolute script paths for the current checkout.
