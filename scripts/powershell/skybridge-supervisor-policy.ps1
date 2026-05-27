[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FixtureFile,
  [switch]$AllowHighRisk,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-DisplayTaskStatus {
  param($Task)
  if ($null -eq $Task) { return $null }
  $raw = if ($Task.raw_status) { [string]$Task.raw_status } elseif ($Task.status) { [string]$Task.status } else { "unknown" }
  $evidence = $Task.evidence_summary
  $recovered = $Task.recovered -eq $true -or ($evidence -and $evidence.recovered -eq $true)
  $ci = if ($Task.ci_status) { [string]$Task.ci_status } elseif ($evidence -and $evidence.ci_status) { [string]$evidence.ci_status } else { $null }
  if ($raw -eq "failed" -and $recovered) {
    if ($ci -eq "passed_after_rerun") { return "recovered" }
    return "failed/recovered"
  }
  return $raw
}

function Select-SupervisorProposal {
  param([array]$Proposals, [switch]$AllowHighRisk)
  $duplicateKeys = @($Proposals | Group-Object dedupe_key | Where-Object { $_.Name -and $_.Count -gt 1 } | ForEach-Object { $_.Name })
  $eligible = @($Proposals | Where-Object {
    $_.status -notin @("converted", "rejected") -and
    ($duplicateKeys -notcontains $_.dedupe_key) -and
    (@($_.required_capabilities) -contains "codex")
  })
  $safe = @($eligible | Where-Object { $_.risk -eq "low" })
  if (@($safe).Count -gt 0) {
    $docs = @($safe | Where-Object { $_.task_type -eq "docs" })
    if (@($docs).Count -gt 0) { return @($docs)[0] }
    return @($safe)[0]
  }
  if ($AllowHighRisk) {
    $high = @($eligible | Where-Object { $_.risk -eq "high" })
    if (@($high).Count -gt 0) { return @($high)[0] }
  }
  return $null
}

function Get-SupervisorDecision {
  param($Fixture, $SelectedProposal, [switch]$AllowHighRisk)
  if ($Fixture.control -and $Fixture.control.stop_requested -eq $true) {
    return [pscustomobject]@{ decision = "ask_human"; stop_reason = "project_stop_requested"; reason = "Project control has stop_requested=true." }
  }
  if (@($Fixture.workers | Where-Object { $_.status -eq "online" }).Count -eq 0) {
    return [pscustomobject]@{ decision = "stop_worker_unavailable"; stop_reason = "worker_unavailable"; reason = "No online worker is visible in project state." }
  }
  if ($Fixture.latest_task) {
    $display = Get-DisplayTaskStatus -Task $Fixture.latest_task
    if ($display -eq "completed" -or $display -eq "recovered") {
      return [pscustomobject]@{ decision = "continue"; stop_reason = $null; reason = "Latest task is $display." }
    }
    if ($display -eq "failed" -or $display -eq "failed/recovered") {
      return [pscustomobject]@{ decision = "stop_task_failed"; stop_reason = "task_failed"; reason = "Latest task status is $display." }
    }
  }
  if (-not $SelectedProposal) {
    $hasHigh = @($Fixture.proposals | Where-Object { $_.risk -eq "high" -and $_.status -notin @("converted", "rejected") }).Count -gt 0
    if ($hasHigh -and -not $AllowHighRisk) {
      return [pscustomobject]@{ decision = "ask_human"; stop_reason = "high_risk_requires_review"; reason = "Only high-risk proposals remain and -AllowHighRisk was not supplied." }
    }
    return [pscustomobject]@{ decision = "stop_no_safe_proposal"; stop_reason = "no_safe_proposal"; reason = "No low-risk codex proposal is available." }
  }
  return [pscustomobject]@{ decision = "continue"; stop_reason = $null; reason = "Selected one bounded proposal." }
}

$fixture = Get-Content -LiteralPath $FixtureFile -Raw | ConvertFrom-Json
$selected = Select-SupervisorProposal -Proposals @($fixture.proposals) -AllowHighRisk:$AllowHighRisk
$decision = Get-SupervisorDecision -Fixture $fixture -SelectedProposal $selected -AllowHighRisk:$AllowHighRisk
$result = [pscustomobject]@{
  ok = $true
  token_printed = $false
  selected_proposal_id = if ($selected) { $selected.proposal_id } else { $null }
  selected_risk = if ($selected) { $selected.risk } else { $null }
  latest_task_display_status = Get-DisplayTaskStatus -Task $fixture.latest_task
  decision = $decision
}

if ($Json) {
  $result | ConvertTo-Json -Depth 20 -Compress
} else {
  $result | Format-List
}
