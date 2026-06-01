[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$goalPackDir = Join-Path $repoRoot "goals\dev-queue-189-200"

$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign.ps1" validate-pack -GoalPackDir $goalPackDir -Json | ConvertFrom-Json
if (-not $result.validation.ok -or $result.validation.goal_count -ne 12) { throw "dev queue validation failed" }

$expected = @(
  "super-189-ci-guardian-pr-finalizer-hardening",
  "super-190-campaign-run-report-evidence-ledger",
  "super-191-readonly-operator-dashboard",
  "super-192-dashboard-safe-actions",
  "super-193-notification-attention-loop",
  "super-194-worker-service-mode",
  "super-195-manual-goal-queue-management",
  "super-196-campaign-locking-multi-campaign-queue",
  "super-197-multi-worker-readiness",
  "super-198-multi-project-support",
  "super-199-hermes-goal-draft-generator",
  "super-200-controlled-goal-draft-review-import"
)
$actual = @($result.validation.payload.metadata.dependency_order)
if (($actual -join "|") -ne ($expected -join "|")) { throw "dev queue dependency order changed" }
foreach ($goal in @($result.validation.payload.goals)) {
  if ([string]::IsNullOrWhiteSpace([string]$goal.markdown_hash)) { throw "missing markdown hash for $($goal.goal_id)" }
}

$summary = [pscustomobject]@{
  ok = $true
  goal_count = $result.validation.goal_count
  dependency_order = $actual
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 20 -Compress } else { $summary | Format-List }
