[CmdletBinding()]
param([switch]$DryRun, [switch]$Json)

$ErrorActionPreference = "Stop"
$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\skybridge-self-bootstrap-loop.ps1" -DryRun -MaxRounds 3 -Json
if ($LASTEXITCODE -ne 0) { throw "Self-bootstrap loop dry-run failed." }
$result = $output | ConvertFrom-Json
if (@($result.rounds).Count -ne 3) { throw "Expected 3 dry-run rounds." }
if (-not $result.notification) { throw "Expected dry-run notification preview." }
$summary = @{ ok = $true; rounds = @($result.rounds).Count; dry_run = $true; notification_status = $result.notification.status }
if ($Json) { $summary | ConvertTo-Json -Depth 8 } else { Write-Host "[smoke-self-bootstrap-loop] ok=$($summary.ok) rounds=$($summary.rounds)" }
