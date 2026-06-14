. "$PSScriptRoot\smoke-productization-common.ps1"
$candidate = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "report")
Assert-FileExists ".agent/tmp/local-runtime/local-runtime-apply-candidate.json"
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".agent/tmp/local-runtime/local-runtime-apply-candidate.json")
Assert-NoUnsafeText $text
Assert-TokenPrintedFalse $candidate
Complete-Smoke "local-runtime-apply-candidate-token-printed-false"
