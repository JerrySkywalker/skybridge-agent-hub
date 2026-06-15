. "$PSScriptRoot\smoke-productization-common.ps1"
$path = Join-Path $PSScriptRoot "skybridge-launcher.ps1"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $path -Command "unknown-command" -Json
if ($LASTEXITCODE -eq 0) { throw "Unknown command must fail closed." }
$result = ($raw | Out-String).Trim() | ConvertFrom-Json
if ($result.schema -ne "skybridge.launcher_safe_error.v1") { throw "Expected safe error schema." }
Assert-TokenPrintedFalse $result
if ($result.code -ne "unknown_command") { throw "Expected unknown_command." }
Complete-Smoke "launcher-unknown-command-safe-error"
