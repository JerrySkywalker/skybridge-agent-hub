$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$files = @(
  "scripts/powershell/skybridge-install-sandbox.ps1",
  "scripts/powershell/skybridge-uninstall-sandbox.ps1",
  "scripts/powershell/skybridge-upgrade-rollback-sandbox.ps1",
  "scripts/powershell/skybridge-local-soak.ps1",
  "scripts/powershell/skybridge-operator-acceptance.ps1",
  "apps/web/src/main.tsx",
  "apps/desktop/src/main.tsx"
)
foreach ($relative in $files) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $root $relative)
  if ($text -match 'token_printed"\s*:\s*true|token_printed:\s*true') { throw "token_printed=true marker found in $relative" }
}
$reports = @(
  ".agent/tmp/install-sandbox/install-sandbox-report.json",
  ".agent/tmp/local-session/extended-fixture-soak-report.json",
  ".agent/tmp/local-session/stability-cleanup-report.json",
  ".agent/tmp/operator-acceptance/operator-acceptance-v2-report.json"
)
foreach ($relative in $reports) {
  $path = Join-Path $root $relative
  if (Test-Path -LiteralPath $path) {
    $text = Get-Content -Raw -LiteralPath $path
    if ($text -match 'token_printed"\s*:\s*true|authorization\s*[:=]\s*bearer|-----BEGIN [A-Z ]*PRIVATE KEY-----') { throw "Unsafe report content in $relative" }
  }
}
[pscustomobject]@{ ok = $true; scenario = "sandbox-install-261-264-token-printed-false"; token_printed = $false } | ConvertTo-Json -Compress
