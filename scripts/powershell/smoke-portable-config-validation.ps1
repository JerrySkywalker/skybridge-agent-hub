. "$PSScriptRoot\smoke-productization-common.ps1"
Assert-FileExists "fixtures/productization/portable-config.example.json"
$config = Get-Content -Raw (Join-Path $RepoRoot "fixtures/productization/portable-config.example.json") | ConvertFrom-Json
Assert-TokenPrintedFalse $config
Assert-TokenPrintedFalse $config.validation
Assert-True $config.validation.ok "portable config validation ok"
Assert-False $config.profile.execution_enabled "execution_enabled"
Assert-False $config.profile.queue_apply_enabled "queue_apply_enabled"
Assert-False $config.profile.remote_execution_enabled "remote_execution_enabled"
Assert-False $config.profile.arbitrary_command_enabled "arbitrary_command_enabled"
Complete-Smoke "portable-config-validation"
