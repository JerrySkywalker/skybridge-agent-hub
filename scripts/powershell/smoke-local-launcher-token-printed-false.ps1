. "$PSScriptRoot\smoke-productization-common.ps1"
foreach ($script in @("skybridge-launcher.ps1", "skybridge-session-supervisor.ps1", "skybridge-operator-walkthrough.ps1")) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $script) -Command safe-summary -Json
  if ($LASTEXITCODE -ne 0) { throw "$script safe-summary failed" }
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  if ($text -notmatch '"token_printed"\s*:\s*false') { throw "Expected token_printed=false in $script" }
}
Complete-Smoke "local-launcher-token-printed-false"
