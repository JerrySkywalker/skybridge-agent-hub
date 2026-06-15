# Install Soak And Recovery

`scripts/powershell/skybridge-install-soak.ps1` runs bounded sandbox cycles:

- install, upgrade, rollback
- install and uninstall preview
- rollback rehearsal

Defaults:

- max cycles: 3
- max duration: 240 seconds
- sandbox only
- no host mutation
- no raw logs
- no background process left running

Reports:

- `.agent/tmp/install-sandbox/install-upgrade-rollback-soak-report.json`
- `.agent/tmp/install-sandbox/install-uninstall-soak-report.json`
- `.agent/tmp/install-sandbox/recovery-sandbox-report.json`

`token_printed=false`
