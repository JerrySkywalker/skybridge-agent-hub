# Desktop Worker V1 Runbook

The Desktop resident worker is a preview shell in v1. It displays release status, resource gate state, failure budget state, evidence/audit state, and disabled execution flags. It does not execute Codex or claim tasks.

Build and inspect:

```powershell
corepack pnpm -C apps/desktop build
Push-Location apps/desktop/src-tauri; cargo check; Pop-Location
```

The supported launch mode is local development/preview. Installer packaging is deferred to a later goal.

Required invariant: `token_printed=false`.
