. "$PSScriptRoot\smoke-productization-common.ps1"
Invoke-JsonScript "skybridge-artifact-integrity.ps1" @("-Command", "report") | Out-Null
$path = Join-Path $RepoRoot ".agent/tmp/portable-package/package-rebuild-reproducibility-report.json"
Assert-FileExists ".agent/tmp/portable-package/package-rebuild-reproducibility-report.json"
$result = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
Assert-True $result.reproducible_manifest "reproducible_manifest"
Assert-True $result.reproducible_file_list "reproducible_file_list"
Assert-TokenPrintedFalse $result
Complete-Smoke "smoke-package-rebuild-reproducibility-preview"
