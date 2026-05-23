# Bootstrap Environment Loading

PowerShell `$env:` values are process-local. A value set in one terminal is inherited by child processes from that terminal, but a new Codex session, Hermes session or PowerShell window starts from its own environment and will not automatically receive those variables.

SkyBridge automation can load local bootstrap notification settings from:

```text
$HOME\.skybridge\bootstrap-notify.env.ps1
```

Set `SKYBRIDGE_BOOTSTRAP_ENV_FILE` to point at a different file when testing or when a machine needs a different local path.

## Create The Local File

Create the directory and copy the tracked placeholder template:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.skybridge"
Copy-Item .\config\bootstrap-notify.env.example.ps1 "$HOME\.skybridge\bootstrap-notify.env.ps1"
notepad "$HOME\.skybridge\bootstrap-notify.env.ps1"
```

Replace the placeholder values locally. Do not commit the edited file and do not paste real topics, passwords, tokens or webhook URLs into prompts, logs, issues, PRs or repository files.

## Test In A New Window

Open a new PowerShell window from outside the current Codex session and run:

```powershell
cd V:\src\skybridge-agent-hub
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\load-bootstrap-env.ps1 -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge bootstrap env test" `
  -Message "Dry-run only" `
  -Severity warning `
  -DryRun `
  -Json
```

The JSON output reports which variables are present or missing, but never prints their values. Real delivery still requires passing `-Send` to `notify-bootstrap.ps1`.

## Script Loading

These scripts load the same helper before using bootstrap notification variables:

- `notify-bootstrap.ps1`
- `skybridge-iterate.ps1`
- `skybridge-ci-guardian.ps1`
- `skybridge-hermes-supervisor.ps1`
- `smoke-bootstrap-notification.ps1`

The loader fails open when the local file is absent, so dry-runs and local checks still work without notification credentials.

## Exposure Response

If a real topic, password, token or webhook URL is accidentally pasted into a prompt, log, PR or repository file, rotate that credential immediately and remove the exposed value from the affected location. Treat ntfy topics and webhook URLs as sensitive operational routing data.
