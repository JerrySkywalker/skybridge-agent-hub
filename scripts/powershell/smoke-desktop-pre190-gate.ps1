$ErrorActionPreference = "Stop"

function Test-Pre190Gate {
  param(
    [Nullable[int]]$ActiveTasks,
    [Nullable[int]]$StaleLeases,
    [bool]$DetectedTokenPrinted,
    [string]$CurrentGoalId = "super-190-campaign-run-report-evidence-ledger",
    [string]$CurrentGoalStatus = "ready",
    [int]$LinkedTaskCount = 0,
    [int]$LinkedPrCount = 0
  )
  $unknown = $false
  $blocked = $false
  if ($null -eq $ActiveTasks) { $unknown = $true } elseif ($ActiveTasks -gt 0) { $blocked = $true }
  if ($null -eq $StaleLeases) { $unknown = $true } elseif ($StaleLeases -gt 0) { $blocked = $true }
  if ($DetectedTokenPrinted) { $blocked = $true }
  if ($CurrentGoalId -ne "super-190-campaign-run-report-evidence-ledger") { $unknown = $true }
  if ($CurrentGoalStatus -ne "ready") { $unknown = $true }
  if ($LinkedTaskCount -gt 0) { $blocked = $true }
  if ($LinkedPrCount -gt 0) { $blocked = $true }
  if ($blocked) { return "BLOCK" }
  if ($unknown) { return "WARN" }
  return "PASS"
}

$cases = @(
  @{ name = "clean"; expected = "PASS"; actual = Test-Pre190Gate -ActiveTasks 0 -StaleLeases 0 -DetectedTokenPrinted:$false },
  @{ name = "unknown-active"; expected = "WARN"; actual = Test-Pre190Gate -ActiveTasks $null -StaleLeases 0 -DetectedTokenPrinted:$false },
  @{ name = "active-task"; expected = "BLOCK"; actual = Test-Pre190Gate -ActiveTasks 1 -StaleLeases 0 -DetectedTokenPrinted:$false },
  @{ name = "stale-lease"; expected = "BLOCK"; actual = Test-Pre190Gate -ActiveTasks 0 -StaleLeases 1 -DetectedTokenPrinted:$false },
  @{ name = "linked-task"; expected = "BLOCK"; actual = Test-Pre190Gate -ActiveTasks 0 -StaleLeases 0 -DetectedTokenPrinted:$false -LinkedTaskCount 1 },
  @{ name = "linked-pr"; expected = "BLOCK"; actual = Test-Pre190Gate -ActiveTasks 0 -StaleLeases 0 -DetectedTokenPrinted:$false -LinkedPrCount 1 },
  @{ name = "token-detected"; expected = "BLOCK"; actual = Test-Pre190Gate -ActiveTasks 0 -StaleLeases 0 -DetectedTokenPrinted:$true }
)

foreach ($case in $cases) {
  if ($case.actual -ne $case.expected) {
    throw "Pre-190 gate case '$($case.name)' expected $($case.expected), got $($case.actual)."
  }
}

[pscustomobject]@{ ok = $true; scenario = "desktop-pre190-gate"; token_printed = $false; cases = $cases } | ConvertTo-Json -Depth 5 -Compress
