# Backlog: PowerShell Shared Redaction Rules

## Background

PR #9 adds `packages/event-schema/src/redaction-rules.json` and TypeScript redaction helpers. PowerShell scripts still carry their own redaction behavior, so parity must be hardened in a focused follow-up.

## Tasks

- Load `packages/event-schema/src/redaction-rules.json` from PowerShell scripts.
- Apply key/value omit and replacement rules consistently in hook and runner paths.
- Add fixture tests proving TypeScript and PowerShell redact the same secret samples.
- Keep existing fail-open hook behavior.

## Completion Criteria

- `test-codex-hook-event.ps1 -RequireSpool` passes with shared JSON rules.
- TypeScript and PowerShell redaction fixture expectations match.
- Docs identify the shared rules as canonical.

## Safety Boundaries

- Do not upload raw prompts, patches, stdout or stderr.
- Do not weaken existing hook redaction.
- Do not make Codex hooks fail closed if SkyBridge is offline.
