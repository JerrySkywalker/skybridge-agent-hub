. "$PSScriptRoot\smoke-productization-common.ps1"
$policy = Invoke-JsonScript "skybridge-backup-restore-preview.ps1" @("-Command", "backup-plan-preview")
Assert-False $policy.raw_artifacts_included "raw_artifacts_included"
Assert-False $policy.env_dumps_included "env_dumps_included"
Assert-False $policy.secrets_included "secrets_included"
Assert-False $policy.tokens_included "tokens_included"
Complete-Smoke "backup-restore-excludes-raw-artifacts"
