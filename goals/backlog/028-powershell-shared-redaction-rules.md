# Backlog: PowerShell Shared Redaction Rules

## Background

PR #9 adds `packages/event-schema/src/redaction-rules.json` and TypeScript redaction helpers. PowerShell scripts still carry their own redaction behavior, so parity must be hardened in a focused follow-up.

Nightly CI/CD Guardian round 3 started this by adding `scripts/powershell/shared-redaction.ps1`, wiring the Codex dashboard hook through it, and adding `scripts/powershell/test-shared-redaction-rules.ps1` for a TypeScript/PowerShell parity smoke. Remaining work should focus on broader runner-path adoption and deeper fixture coverage.

## Tasks

- [x] Load `packages/event-schema/src/redaction-rules.json` from the Codex hook PowerShell path.
- [x] Apply key/value omit and replacement rules consistently in runner telemetry paths.
- [x] Add fixture tests proving TypeScript and PowerShell redact the same secret samples.
- Keep existing fail-open hook behavior.
- [x] Add a fallback embedded rule set or clear warning if the JSON file is unavailable during local hook execution.
- [x] Document versioning expectations for the shared redaction policy.

## Completion Criteria

- `test-codex-hook-event.ps1 -RequireSpool` passes with shared JSON rules.
- TypeScript and PowerShell redaction fixture expectations match.
- Runner dry-run telemetry records the shared redaction policy and redacts token-like payload text.
- Docs identify the shared rules as canonical.
- Shared-rule fixture coverage includes secret keys, bearer values, API keys, private-key markers and raw prompt/patch/output fields across TypeScript and PowerShell.
- PowerShell shared-rule coverage includes `ConvertFrom-Json` object values, not only hashtable literals.
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
