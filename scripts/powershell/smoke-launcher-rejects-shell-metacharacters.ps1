. "$PSScriptRoot\smoke-productization-common.ps1"
$path = Join-Path $PSScriptRoot "skybridge-launcher.ps1"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $path -Command "status;whoami" -Json
if ($LASTEXITCODE -eq 0) { throw "Shell metacharacter command must fail closed." }
$result = ($raw | Out-String).Trim() | ConvertFrom-Json
Assert-TokenPrintedFalse $result
if ($result.code -ne "unsafe_command_rejected") { throw "Expected unsafe_command_rejected." }
Complete-Smoke "launcher-rejects-shell-metacharacters"
