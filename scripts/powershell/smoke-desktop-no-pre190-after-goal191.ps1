$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ui = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
$visual = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "scripts\desktop-visual-qa.mjs")

foreach ($required in @(
  "Queue Readiness",
  "Operator Readiness",
  "super-191-readonly-operator-dashboard",
  "goal190IsCurrent",
  "previous_step_summary"
)) {
  if (($ui + "`n" + $visual) -notmatch [regex]::Escape($required)) {
    throw "Goal 191 desktop wording/contract missing: $required"
  }
}

foreach ($forbidden in @("Pre-190 {status.pre190_readiness.state}", "<h2>Pre-190 Readiness</h2>", "Goal 190 PR links 0")) {
  if ($ui -match [regex]::Escape($forbidden)) {
    throw "Legacy Pre-190 primary wording remains after Goal 191: $forbidden"
  }
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-no-pre190-after-goal191"
  token_printed = $false
} | ConvertTo-Json -Compress
