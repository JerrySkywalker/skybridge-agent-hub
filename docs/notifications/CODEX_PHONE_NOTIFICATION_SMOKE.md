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

## Troubleshooting

Missing env:
Dry-run success for this smoke expects the nested Codex output to show ntfy as configured. If it reports skipped or missing env, verify `$HOME\.skybridge\bootstrap-notify.env.ps1` exists on the local machine or point `SKYBRIDGE_BOOTSTRAP_ENV_FILE` at a local env loader. Do not commit that file.

Missing `-Send`:
The default and package-script path use `-DryRun`; they prove command routing without delivering to the phone. A real phone notification requires the wrapper `-Send` switch, which causes the nested notifier call to include `notify-bootstrap.ps1 -Send`.

Wrong topic:
Check the subscribed phone topic against the severity-specific topic selection. `urgent` can route to `SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC`; `info` and `warning` use the normal topic. Keep real topic names out of prompts, logs, commits and PR text.

ACL denied:
If the nested notifier reports an auth or ACL failure, fix the local ntfy token or basic-auth settings outside the repo and retry dry-run first. The smoke should report failure without exposing credential values.

Sandbox mode:
If Codex does not appear to run `notify-bootstrap.ps1`, run the wrapper from the repository root and keep its `--sandbox danger-full-access` behavior. This is for local PowerShell process spawning on Windows; it does not authorize production deployment, file edits or secret disclosure.

## Real Phone Send

Real delivery is a manual operator test. Do not run `-Send` in CI or default checks.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-phone-notification.ps1 -Send -Severity urgent
```

Send mode instructs Codex to run `notify-bootstrap.ps1 -Send`, which can publish to ntfy and reach the subscribed phone. Use it only from a trusted local machine after confirming `$HOME\.skybridge\bootstrap-notify.env.ps1` contains the intended local notification settings.
