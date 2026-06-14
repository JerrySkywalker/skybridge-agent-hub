. "$PSScriptRoot\smoke-productization-common.ps1"
$temp = Join-Path $RepoRoot ".agent/tmp/product-readiness/unsafe-config.execution.json"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $temp) | Out-Null
$unsafe = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures/productization/local-config.example.json")
$unsafe = $unsafe -replace '"execution_enabled": false', '"execution_enabled": true'
$unsafe | Set-Content -LiteralPath $temp -Encoding utf8
$validation = Invoke-JsonScript "skybridge-local-config.ps1" @("-Command", "validate", "-Path", ".agent/tmp/product-readiness/unsafe-config.execution.json")
Assert-False $validation.ok "validation.ok"
Remove-Item -LiteralPath $temp -Force
Complete-Smoke "local-config-rejects-execution-enabled"
