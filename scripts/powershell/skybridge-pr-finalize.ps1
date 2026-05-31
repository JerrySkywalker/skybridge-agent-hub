[CmdletBinding()]
param(
  [string]$Repo = "JerrySkywalker/skybridge-agent-hub",
  [int]$PR = 0,
  [string]$PrUrl,
  [string]$TaskId,
  [string]$CampaignId,
  [string]$StepId,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenFile,
  [string]$TokenEnvVar,
  [string[]]$ExpectedFiles = @(),
  [string[]]$AllowedPaths = @(),
  [int]$CheckTimeoutSeconds = 900,
  [int]$PollIntervalSeconds = 30,
  [switch]$AllowAutoMerge,
  [switch]$AllowEvidenceRepair,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$Json,
  [string]$FixtureFile,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Write-PrFinalizerResult {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 60 -Compress; return }
  "PR:           $($Result.pr.number)"
  "State:        $($Result.pr.state)"
  "CI:           $($Result.ci_status)"
  "Safe:         $($Result.safe_to_merge)"
  "Decision:     $($Result.decision)"
  "TokenPrinted: false"
}

function Get-PrNumberFromInput {
  if ($PR -gt 0) { return $PR }
  if ($PrUrl -match "/pull/(\d+)") { return [int]$Matches[1] }
  if ($TaskId -and -not $FixtureFile) {
    $config = [pscustomobject]@{ api_base = $ApiBase; project_id = $ProjectId; auth_mode = if ($TokenFile -or $TokenEnvVar) { "bearer_token" } else { "none" }; token_file = $TokenFile; token_env_var = $TokenEnvVar }
    $task = (Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))" -ApiBase $ApiBase -Config $config).task
    $candidate = if ($task.result.pr_url) { [string]$task.result.pr_url } else { [string]$task.pr_url }
    if ($candidate -match "/pull/(\d+)") { return [int]$Matches[1] }
  }
  throw "Unable to determine PR number. Supply -PR, -PrUrl, -TaskId, or -FixtureFile."
}

function Convert-GhPrToSummary {
  param($Pr)
  $files = @($Pr.files | ForEach-Object { if ($_.path) { [string]$_.path } elseif ($_.filename) { [string]$_.filename } })
  $checks = @()
  foreach ($node in @($Pr.statusCheckRollup)) {
    $name = if ($node.name) { [string]$node.name } elseif ($node.context) { [string]$node.context } else { "unknown" }
    $status = if ($node.status) { [string]$node.status } else { [string]$node.state }
    $conclusion = if ($node.conclusion) { [string]$node.conclusion } else { [string]$node.state }
    $checks += [pscustomobject]@{ name = $name; status = $status; conclusion = $conclusion }
  }
  [pscustomobject]@{
    number = [int]$Pr.number
    url = [string]$Pr.url
    state = [string]$Pr.state
    isDraft = [bool]$Pr.isDraft
    merged = [bool]$Pr.merged
    mergeCommit = if ($Pr.mergeCommit.oid) { [string]$Pr.mergeCommit.oid } else { $null }
    files = @($files)
    checks = @($checks)
  }
}

function Get-PrFixtureSummary {
  $fixture = Get-Content -Raw -LiteralPath $FixtureFile | ConvertFrom-Json
  Convert-GhPrToSummary -Pr $fixture
}

function Get-PrLiveSummary {
  param([int]$Number)
  $json = gh pr view $Number --repo $Repo --json number,url,state,isDraft,merged,mergeCommit,files,statusCheckRollup
  if ($LASTEXITCODE -ne 0) { throw "gh pr view failed for PR #$Number." }
  Convert-GhPrToSummary -Pr ($json | ConvertFrom-Json)
}

function Get-PrCiStatus {
  param($Summary)
  $checks = @($Summary.checks)
  if ($checks.Count -eq 0) { return "unknown" }
  $states = @($checks | ForEach-Object { ("$($_.status) $($_.conclusion)").ToLowerInvariant() })
  if (@($states | Where-Object { $_ -match "pending|queued|in_progress|waiting|requested" }).Count -gt 0) { return "pending" }
  if (@($states | Where-Object { $_ -match "cancelled|timed_out|action_required" }).Count -gt 0) { return "cancelled" }
  if (@($states | Where-Object { $_ -match "failure|failed" }).Count -gt 0) {
    $names = @($checks | ForEach-Object { $_.name }) -join " "
    if ($names -match "(?i)(checkout|network|cache|setup)") { return "transient_failed" }
    return "real_failed"
  }
  if (@($states | Where-Object { $_ -match "skipped" }).Count -eq $states.Count) { return "skipped" }
  if (@($states | Where-Object { $_ -match "success|passed|completed" }).Count -gt 0) { return "passed" }
  "unknown"
}

function Test-PathAllowed {
  param([string]$Path, [string[]]$Patterns)
  if ($Patterns.Count -eq 0) { return $true }
  $normalized = $Path.Replace("\", "/")
  foreach ($pattern in $Patterns) {
    $p = ([string]$pattern).Replace("\", "/")
    if ($p.EndsWith("/**") -and $normalized.StartsWith($p.Substring(0, $p.Length - 3))) { return $true }
    if ($normalized -eq $p -or $normalized -like $p) { return $true }
  }
  return $false
}

function Get-UnsafeFileReasons {
  param($Summary)
  $patterns = @($AllowedPaths)
  if ($patterns.Count -eq 0) { $patterns = @($ExpectedFiles) }
  $reasons = @()
  foreach ($file in @($Summary.files)) {
    if ($file -match "(?i)(^|/)(\.env|.*secret.*|.*token.*|id_rsa|private-key)" -or $file -match "^(deploy/|\.github/settings|server-root|/opt/)") {
      $reasons += "unsafe_file:$file"
    } elseif (-not (Test-PathAllowed -Path $file -Patterns $patterns)) {
      $reasons += "file_outside_allowed_paths:$file"
    }
  }
  @($reasons)
}

function Repair-TaskEvidence {
  param($Summary, [string]$CiStatus)
  if (-not $TaskId -or -not $AllowEvidenceRepair -or $DryRun -or -not $Apply) { return $false }
  $config = [pscustomobject]@{ api_base = $ApiBase; project_id = $ProjectId; auth_mode = if ($TokenFile -or $TokenEnvVar) { "bearer_token" } else { "none" }; token_file = $TokenFile; token_env_var = $TokenEnvVar }
  Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/evidence-repair" -ApiBase $ApiBase -Config $config -Body @{
    evidence_summary = @{
      task_id = $TaskId
      pr_url = $Summary.url
      merge_commit = $Summary.mergeCommit
      changed_files = @($Summary.files)
      validation_status = if ($CiStatus -eq "passed") { "passed" } else { "unknown" }
      ci_status = $CiStatus
      recovered = $true
      recovery_status = "recovered"
      summary = "Recovered after child PR finalizer verified merge/check evidence."
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  } | Out-Null
  return $true
}

$effectiveDryRun = $DryRun -or -not $Apply
$summary = if ($FixtureFile) { Get-PrFixtureSummary } else { Get-PrLiveSummary -Number (Get-PrNumberFromInput) }
$ciStatus = Get-PrCiStatus -Summary $summary
$unsafeReasons = @(Get-UnsafeFileReasons -Summary $summary)
$safeToMerge = $unsafeReasons.Count -eq 0 -and $ciStatus -eq "passed"
$decision = if ($unsafeReasons.Count -gt 0) {
  "blocked_unsafe_files"
} elseif ($ciStatus -eq "pending") {
  "wait_pending"
} elseif ($ciStatus -eq "transient_failed") {
  "rerun_transient_once"
} elseif ($ciStatus -eq "real_failed") {
  "blocked_real_ci_failure"
} elseif ($safeToMerge -and $AllowAutoMerge) {
  if ($effectiveDryRun) { "would_auto_merge" } else { "auto_merge" }
} elseif ($safeToMerge) {
  "safe_no_auto_merge"
} else {
  "blocked_unknown_ci"
}

$actions = @()
if (-not $effectiveDryRun -and -not $FixtureFile) {
  if ($summary.isDraft -and $safeToMerge) {
    gh pr ready $summary.number --repo $Repo | Out-Null
    $actions += "marked_ready"
  }
  if ($decision -eq "rerun_transient_once") {
    gh run rerun --failed | Out-Null
    $actions += "reran_failed_jobs"
  }
  if ($decision -eq "auto_merge") {
    gh pr merge $summary.number --repo $Repo --squash --auto | Out-Null
    $actions += "enabled_auto_merge"
  }
}
$evidenceRepaired = if ($summary.merged -or $decision -in @("safe_no_auto_merge", "auto_merge", "would_auto_merge")) { Repair-TaskEvidence -Summary $summary -CiStatus $ciStatus } else { $false }

Write-PrFinalizerResult ([pscustomobject]@{
  ok = ($decision -notin @("blocked_unsafe_files", "blocked_real_ci_failure", "blocked_unknown_ci"))
  command = "finalize-pr"
  mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }
  project_id = $ProjectId
  token_printed = $false
  pr = $summary
  task_id = $TaskId
  campaign_id = $CampaignId
  step_id = $StepId
  ci_status = $ciStatus
  unsafe_reasons = @($unsafeReasons)
  safe_to_merge = $safeToMerge
  decision = $decision
  actions = @($actions)
  evidence_repaired = [bool]$evidenceRepaired
  safety = @{
    no_auto_merge_outside_allowed_paths = $true
    no_auto_merge_real_failed_ci = $true
    no_raw_token_output = $true
  }
})
