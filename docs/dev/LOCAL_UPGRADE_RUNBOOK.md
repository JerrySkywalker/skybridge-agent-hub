# Local Upgrade Runbook

Local upgrades are source checkout upgrades plus safe metadata review.

1. Confirm no active work:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-complete.ps1 -Command gate
```

2. Pull latest code when the worktree is clean:

```powershell
git status -sb
git pull --ff-only
```

3. Reinstall and validate:

```powershell
corepack pnpm install
corepack pnpm check
```

4. Regenerate safe product reports:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-product-profile.ps1 -Command report
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-diagnostics.ps1 -Command report
```

Do not back up raw logs, environment dumps, prompts, transcripts, tokens or secret-bearing paths.

token_printed=false
