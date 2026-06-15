. "$PSScriptRoot\smoke-productization-common.ps1"
foreach ($command in @("status", "start", "ports", "locks", "cleanup", "demo", "safe-summary", "report")) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-session.ps1") -Command $command -Json
  if ($LASTEXITCODE -ne 0) { throw "local-session $command failed" }
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  if ($text -notmatch '"token_printed"\s*:\s*false') { throw "Expected token_printed=false for $command" }
}
Complete-Smoke "local-session-token-printed-false"
