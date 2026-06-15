. "$PSScriptRoot\smoke-productization-common.ps1"
$path = Join-Path $PSScriptRoot "skybridge-launcher.ps1"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $path -Command "codex worker" -Json
if ($LASTEXITCODE -eq 0) { throw "Worker execution text must fail closed." }
$result = ($raw | Out-String).Trim() | ConvertFrom-Json
Assert-TokenPrintedFalse $result
Assert-False $result.starts_codex_worker "starts_codex_worker"
Complete-Smoke "launcher-blocks-worker-execution"
