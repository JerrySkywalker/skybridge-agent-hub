# Backlog: PowerShell Shared Redaction Rules

## Background

PR #9 adds `packages/event-schema/src/redaction-rules.json` and TypeScript redaction helpers. PowerShell scripts still carry their own redaction behavior, so parity must be hardened in a focused follow-up.

## Tasks

- Load `packages/event-schema/src/redaction-rules.json` from PowerShell scripts.
- Apply key/value omit and replacement rules consistently in hook and runner paths.
- Add fixture tests proving TypeScript and PowerShell redact the same secret samples.
- Keep existing fail-open hook behavior.
- Add a fallback embedded rule set or clear warning if the JSON file is unavailable during local hook execution.
- Document versioning expectations for the shared redaction policy.

## Completion Criteria

- `test-codex-hook-event.ps1 -RequireSpool` passes with shared JSON rules.
- TypeScript and PowerShell redaction fixture expectations match.
- Docs identify the shared rules as canonical.
- Existing hook redaction coverage does not regress for commands, prompts, patches, stdout or stderr.
- Offline spool and replay behavior remains fail-open and redacted.

## Safety Boundaries

- Do not upload raw prompts, patches, stdout or stderr.
- Do not weaken existing hook redaction.
- Do not make Codex hooks fail closed if SkyBridge is offline.
- Do not require network access or package installation from hook scripts.

## Validation Commands

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\test-codex-hook-event.ps1 -RequireSpool
corepack pnpm --filter @skybridge-agent-hub/event-schema test
corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook test
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\validate-powershell.ps1
```

## CI/CD Impact

This should strengthen existing PR and AI-branch smoke checks without adding secrets. CI should continue to run fixture-only hook validation and must not archive raw hook input.
