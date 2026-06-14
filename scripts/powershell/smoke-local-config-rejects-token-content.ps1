. "$PSScriptRoot\smoke-productization-common.ps1"
$temp = Join-Path $RepoRoot ".agent/tmp/product-readiness/unsafe-config.token.json"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $temp) | Out-Null
$unsafe = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures/productization/local-config.example.json")
$unsafe = $unsafe.TrimEnd("`r", "`n", "}") + ', "Authorization": "Bearer unsafeexampletoken12345" }'
$unsafe | Set-Content -LiteralPath $temp -Encoding utf8
$validation = Invoke-JsonScript "skybridge-local-config.ps1" @("-Command", "validate", "-Path", ".agent/tmp/product-readiness/unsafe-config.token.json")
Assert-False $validation.ok "validation.ok"
Remove-Item -LiteralPath $temp -Force
Complete-Smoke "local-config-rejects-token-content"
