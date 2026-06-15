$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$files = @(
  "scripts/powershell/skybridge-release-workflow-guard.ps1",
  "scripts/powershell/skybridge-installer-candidate.ps1",
  "scripts/powershell/skybridge-sandbox-installed-runtime.ps1",
  "scripts/powershell/skybridge-install-soak.ps1",
  "scripts/powershell/skybridge-recovery-sandbox.ps1",
  "scripts/powershell/skybridge-operator-demo-script.ps1",
  "scripts/powershell/skybridge-installer-soak-rc.ps1",
  "apps/web/src/main.tsx",
  "apps/desktop/src/main.tsx"
)
foreach ($relative in $files) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $root $relative)
  if ($text -match 'token_printed"\s*:\s*true|token_printed:\s*true|authorization\s*[:=]\s*bearer|-----BEGIN [A-Z ]*PRIVATE KEY-----') { throw "Unsafe marker found in $relative" }
}
$reports = @(
  ".agent/tmp/release-guard/workflow-side-effects.json",
  ".agent/tmp/installer-candidate/installer-report.json",
  ".agent/tmp/installer-candidate/sandbox-installed-runtime-report.json",
  ".agent/tmp/install-sandbox/install-upgrade-rollback-soak-report.json",
  ".agent/tmp/install-sandbox/recovery-sandbox-report.json",
  ".agent/tmp/operator-acceptance/operator-acceptance-v3-report.json",
  ".agent/tmp/operator-acceptance/operator-demo-script-report.json",
  ".agent/tmp/installer-candidate/installer-soak-rc-report.json"
)
foreach ($relative in $reports) {
  $path = Join-Path $root $relative
  if (Test-Path -LiteralPath $path) {
    $text = Get-Content -Raw -LiteralPath $path
    if ($text -match 'token_printed"\s*:\s*true|authorization\s*[:=]\s*bearer|-----BEGIN [A-Z ]*PRIVATE KEY-----') { throw "Unsafe report content in $relative" }
  }
}
[pscustomobject]@{ ok = $true; scenario = "installer-soak-265-272-token-printed-false"; token_printed = $false } | ConvertTo-Json -Compress
