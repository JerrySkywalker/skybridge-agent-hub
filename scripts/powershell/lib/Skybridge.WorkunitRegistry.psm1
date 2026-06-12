Import-Module (Join-Path $PSScriptRoot "Skybridge.Core.psm1") -Force

function Get-SkybridgeCompletedRuns {
  @(
    @{ run_id = "managed-mode-pilot-208"; evidence = ".agent/tmp/managed-mode-pilot-208/finalizer-evidence.json" }
    @{ run_id = "managed-mode-run-209"; evidence = ".agent/tmp/managed-mode-run-209/finalizer-evidence.json" }
    @{ run_id = "managed-mode-run-210"; evidence = ".agent/tmp/managed-mode-run-210/finalizer-evidence.json" }
    @{ run_id = "managed-mode-run-211"; evidence = ".agent/tmp/managed-mode-run-211/finalizer-evidence.json" }
  ) | ForEach-Object {
    $full = Resolve-SkybridgePath $_.evidence
    [pscustomobject]@{
      run_id = $_.run_id
      state = if (Test-Path -LiteralPath $full -PathType Leaf) { "completed" } else { "missing_evidence" }
      evidence_path = $_.evidence
      evidence_hash = if (Test-Path -LiteralPath $full -PathType Leaf) { (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
      token_printed = $false
    }
  }
}

function Get-SkybridgeRunRegistrySummary {
  param([int]$ActiveTasks = 0, [int]$StaleLeases = 0, [string]$RunnerLock = "none", [int]$OpenManagedModePrCount = 0)
  $runs = @(Get-SkybridgeCompletedRuns)
  [pscustomobject]@{
    schema = "skybridge.core_engine_completed_run_registry.v1"
    completed_run_count = @($runs | Where-Object { $_.state -eq "completed" }).Count
    completed_runs = $runs
    open_run_count = 0
    next_run_id = "managed-mode-run-212"
    duplicate_run_prevention = $true
    open_review_hold = ($OpenManagedModePrCount -gt 0)
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    token_printed = $false
  }
}

function New-SkybridgeTwoWorkunitDependencyGraph {
  [pscustomobject]@{
    schema = "skybridge.two_workunit_dependency_graph.v1"
    workunits = @(
      [pscustomobject]@{ workunit_id = "workunit-a"; depends_on = @(); token_printed = $false }
      [pscustomobject]@{ workunit_id = "workunit-b"; depends_on = @("workunit-a-finalized"); token_printed = $false }
    )
    token_printed = $false
  }
}

Export-ModuleMember -Function Get-SkybridgeCompletedRuns, Get-SkybridgeRunRegistrySummary, New-SkybridgeTwoWorkunitDependencyGraph
