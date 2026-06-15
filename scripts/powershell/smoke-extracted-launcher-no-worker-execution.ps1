. "$PSScriptRoot\smoke-productization-common.ps1"
Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "extract-smoke") | Out-Null
$launcher = Join-Path $RepoRoot ".agent/tmp/portable-package/extract-smoke/skybridge-agent-hub-portable/scripts/powershell/skybridge-launcher.ps1"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $launcher -Command "codex worker" -Json
if ($LASTEXITCODE -eq 0) { throw "Extracted launcher must reject worker execution text." }
$result = ($raw | Out-String).Trim() | ConvertFrom-Json
Assert-TokenPrintedFalse $result
Assert-False $result.starts_codex_worker "starts_codex_worker"
Complete-Smoke "extracted-launcher-no-worker-execution"
