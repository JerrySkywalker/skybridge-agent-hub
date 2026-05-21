# Codex Hooks Setup

Example hook config is stored at:

```text
config/codex/hooks.example.json
```

For project-level use, copy it to:

```text
.codex/hooks.json
```

For user-level use, copy relevant commands to:

```text
~/.codex/hooks.json
```

This starter includes:

```text
scripts/powershell/codex-dashboard-hook.ps1
scripts/powershell/codex-guard-hook.ps1
```

The dashboard hook sends normalized events to `/v1/events`.

The dashboard hook is fail-open: if the server is offline, Codex continues and the normalized event is still appended to `~/.codex/dashboard/events.jsonl`.

Set these optional environment variables:

```text
SKYBRIDGE_API_BASE=http://127.0.0.1:8787
SKYBRIDGE_NODE_ID=local-dev
CODEX_DASHBOARD_TOKEN=
```

The hook maps `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest` and `Stop` into `skybridge.agent_event.v1`. It does not upload full commands, stdout or stderr by default; it only sends a small summary.

The guard hook blocks high-risk destructive commands, force pushes to protected branches and obvious secret material. It is intended for `PreToolUse`.
