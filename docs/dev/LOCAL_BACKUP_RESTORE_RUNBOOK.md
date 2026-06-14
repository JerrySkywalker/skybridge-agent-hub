# Local Backup Restore Runbook

Safe backup scope:

- selected `.agent/tmp` metadata reports after review
- documentation changes
- sanitized product readiness reports

Do not back up:

- `.env`
- `.data` databases containing local telemetry
- `.agent/runs`
- raw worker logs
- raw Codex logs
- raw CI or GitHub logs
- prompts, transcripts, stdout or stderr
- tokens, cookies, private keys or approval secrets

Recommended safe metadata refresh:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-diagnostics.ps1 -Command report
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-packaging-preview.ps1 -Command report
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command report
```

Restore by checking out source, installing dependencies, and regenerating reports. Do not restore secrets from productization backups.

token_printed=false
