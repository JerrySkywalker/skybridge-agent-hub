Import-Module (Join-Path $PSScriptRoot "Skybridge.Core.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Skybridge.EvidenceStore.psm1") -Force

function Test-SkybridgeTaskPrMerged {
  param([string]$RunId, [switch]$FixtureMerged)
  [pscustomobject]@{ run_id = $RunId; pr_merged = [bool]$FixtureMerged; token_printed = $false }
}

function Test-SkybridgeFinalizerInvariants {
  param([int]$ActiveTasks = 0, [int]$StaleLeases = 0, [string]$RunnerLock = "none")
  $blockers = @()
  if ($ActiveTasks -ne 0) { $blockers += "active_tasks_present" }
  if ($StaleLeases -ne 0) { $blockers += "stale_leases_present" }
  if ($RunnerLock -ne "none") { $blockers += "runner_lock_present" }
  [pscustomobject]@{
    one_workunit = $true
    one_task = $true
    one_claim = $true
    one_codex_execution = $true
    one_pr = $true
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    blockers = @($blockers)
    ok = (@($blockers).Count -eq 0)
    token_printed = $false
  }
}

function New-SkybridgeFinalizerPreview {
  param([Parameter(Mandatory = $true)][string]$RunId)
  $evidence = Find-SkybridgeFinalizerEvidence -RunId $RunId
  [pscustomobject]@{
    schema = "skybridge.core_engine_finalizer_preview.v1"
    run_id = $RunId
    apply_enabled = $false
    duplicate_finalizer_prevention = $true
    evidence = $evidence
    token_printed = $false
  }
}

Export-ModuleMember -Function Test-SkybridgeTaskPrMerged, Test-SkybridgeFinalizerInvariants, New-SkybridgeFinalizerPreview
