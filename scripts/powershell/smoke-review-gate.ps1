[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\review-gate-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

function Base-Readiness {
  param([string]$State = "paused", [string[]]$Blockers = @(), [string[]]$Warnings = @())
  [pscustomobject]@{
    schema = "skybridge.self_bootstrap_readiness.v1"
    ok = $true
    status = "partial"
    blockers = @($Blockers)
    warnings = @($Warnings)
    control_plane = [pscustomobject]@{ project_control = [pscustomobject]@{ state = $State; token_printed = $false }; token_printed = $false }
    token_printed = $false
  }
}

$notificationPath = Write-Fixture "notification.json" ([pscustomobject]@{
  schema = "skybridge.operator_notification_readiness.v1"
  ok = $true
  report_delivery_supported = $true
  review_gate_supported = $true
  token_printed = $false
})
$campaignPath = Write-Fixture "campaign.json" ([pscustomobject]@{ campaign_status = "completed"; old_residue_excluded = $true; evidence_state = [pscustomobject]@{ evidence_present = $true; token_printed = $false }; token_printed = $false })
$operatorPath = Write-Fixture "operator.json" ([pscustomobject]@{ ok = $true; token_printed = $false })

function Invoke-Gate {
  param([string]$Name, $Readiness, $Bounded, [string[]]$Extra = @())
  $readinessPath = Write-Fixture "$Name-readiness.json" $Readiness
  $boundedPath = Write-Fixture "$Name-bounded.json" $Bounded
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-review-gate.ps1 `
    -FixtureReadinessFile $readinessPath `
    -FixtureNotificationFile $notificationPath `
    -FixtureBoundedRunFile $boundedPath `
    -FixtureCampaignReportFile $campaignPath `
    -FixtureOperatorReportFile $operatorPath `
    @Extra `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "review gate failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.review_gate.v1") { throw "Unexpected review gate schema." }
  Assert-False $result.allowed_unbounded_run "$Name allowed_unbounded_run"
  Assert-False $result.allowed_daemon "$Name allowed_daemon"
  Assert-False $result.token_printed "$Name token_printed"
  $result
}

$boundedPreview = [pscustomobject]@{
  stop_reason = "preview_ready"
  evidence_summary = [pscustomobject]@{ evidence_present = $true; token_printed = $false }
  old_residue_exclusion = [pscustomobject]@{ no_old_residue_eligible = $true; token_printed = $false }
  forbidden_actions = [pscustomobject]@{ recursive_run_until_hold = $false; daemon_implemented = $false; token_printed = $false }
  token_printed = $false
}
$boundedNoSafe = [pscustomobject]@{
  stop_reason = "no_safe_candidate"
  evidence_summary = [pscustomobject]@{ evidence_present = $true; token_printed = $false }
  old_residue_exclusion = [pscustomobject]@{ no_old_residue_eligible = $true; token_printed = $false }
  forbidden_actions = [pscustomobject]@{ recursive_run_until_hold = $false; daemon_implemented = $false; token_printed = $false }
  token_printed = $false
}

$previewOnly = Invoke-Gate -Name "preview-only" -Readiness (Base-Readiness) -Bounded $boundedNoSafe
if ($previewOnly.gate_status -ne "safe_to_continue_preview_only") { throw "Expected preview-only gate." }
Assert-True $previewOnly.allowed_preview "preview allowed"

$boundedSafe = Invoke-Gate -Name "bounded-safe" -Readiness (Base-Readiness) -Bounded $boundedPreview
if ($boundedSafe.gate_status -ne "safe_to_continue_bounded") { throw "Expected bounded-safe gate." }
Assert-True $boundedSafe.allowed_bounded_run "bounded allowed"

$review = Invoke-Gate -Name "needs-review" -Readiness (Base-Readiness -Blockers @("active_tasks_present")) -Bounded $boundedPreview
if ($review.gate_status -ne "needs_operator_review") { throw "Expected needs operator review gate." }
Assert-True $review.needs_operator_review "needs review"

$blocked = Invoke-Gate -Name "blocked" -Readiness (Base-Readiness -State "running") -Bounded $boundedPreview
if ($blocked.gate_status -ne "blocked") { throw "Expected blocked gate." }

$failed = Invoke-Gate -Name "failed-closed" -Readiness (Base-Readiness) -Bounded $boundedPreview -Extra @("-FixtureUnboundedEnabled")
if ($failed.gate_status -ne "failed_closed") { throw "Expected failed_closed gate." }

$summary = [pscustomobject]@{
  ok = $true
  smoke = "review-gate"
  scenarios = @("preview_only_state", "bounded_safe_state", "needs_operator_review_state", "blocked_state", "rejects_unbounded_daemon_state", "token_printed_false")
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "review-gate" }
