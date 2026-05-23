# Codex Phone Notification Smoke

This smoke test proves the full operator notification chain:

```text
Codex exec -> notify-bootstrap.ps1 -> local bootstrap env -> ntfy -> phone
```

`scripts/powershell/smoke-codex-phone-notification.ps1` launches a nested `codex exec` run with a narrow prompt that tells Codex to run `notify-bootstrap.ps1`. The notifier, not the prompt, loads local settings from:

```text
$HOME\.skybridge\bootstrap-notify.env.ps1
```

That local file must exist for the dry-run smoke to prove ntfy is configured. Do not commit it, and do not paste real topics, passwords, tokens or webhook URLs into prompts, logs, issues, PRs or repository files.

## Dry Run

The default path is safe and sends no phone notification:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-phone-notification.ps1 -DryRun
```

Package script:

```powershell
corepack pnpm smoke:codex-phone-notification
```

Dry-run mode instructs Codex to run:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge Codex phone smoke" `
  -Message "Codex exec invoked notify-bootstrap.ps1 for a dry-run smoke test." `
  -Severity info `
  -DryRun `
  -Json
```

The smoke writes Codex artifacts under `.agent/codex-phone-smoke/<timestamp>/`:

- `codex.jsonl`
- `last-message.md`
- `summary.json`

The summary reports whether Codex appeared to run `notify-bootstrap.ps1` and whether output included the expected dry-run configured ntfy result.

The wrapper uses `codex exec --sandbox danger-full-access` so the nested Codex process can spawn local PowerShell reliably on Windows. The nested prompt still instructs Codex to run only the notifier command, avoid environment values, avoid file edits and avoid deployment. Default dry-run mode cannot send a phone notification.

## Real Phone Send

Real delivery is a manual operator test. Do not run `-Send` in CI or default checks.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-phone-notification.ps1 -Send -Severity urgent
```

Send mode instructs Codex to run `notify-bootstrap.ps1 -Send`, which can publish to ntfy and reach the subscribed phone. Use it only from a trusted local machine after confirming `$HOME\.skybridge\bootstrap-notify.env.ps1` contains the intended local notification settings.
