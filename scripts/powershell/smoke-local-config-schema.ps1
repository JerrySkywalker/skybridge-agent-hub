. "$PSScriptRoot\smoke-productization-common.ps1"
Assert-FileExists "fixtures/productization/local-config.example.json"
$config = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures/productization/local-config.example.json") | ConvertFrom-Json
if ($config.schema -ne "skybridge.local_config.v1") { throw "schema mismatch" }
if ($config.profile.schema -ne "skybridge.local_config_profile.v1") { throw "profile schema mismatch" }
Assert-False $config.profile.execution_enabled "execution_enabled"
Assert-TokenPrintedFalse $config
Complete-Smoke "local-config-schema"
