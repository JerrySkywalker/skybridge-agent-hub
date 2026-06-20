[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [int]$TimeoutSeconds = 30,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.ApiBase.psm1") -Force

$apiBaseWasBound = $PSBoundParameters.ContainsKey("ApiBase")
$ApiBase = Resolve-SkybridgeApiBase -ApiBase $ApiBase -ParameterWasBound $apiBaseWasBound
Assert-SkybridgeApiBaseUsable -ApiBase $ApiBase
Assert-SkybridgeApiBaseService -ApiBase $ApiBase -TimeoutSeconds $TimeoutSeconds | Out-Null

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Get-Count {
  param($Object, [string]$Name)
  $value = Get-Prop -Object $Object -Name $Name -Default 0
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return 0 }
  return [int]$value
}

function Invoke-StatusReport {
  $args = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $PSScriptRoot "skybridge-status.ps1"),
    "-ApiBase", $ApiBase,
    "-ProjectId", $ProjectId,
    "-Hygiene",
    "-ShowLeases",
    "-ShowAll",
    "-Json",
    "-TimeoutSeconds", [string]$TimeoutSeconds
  )
  if ($TokenEnvVar) { $args += @("-TokenEnvVar", $TokenEnvVar) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }

  $output = @(& pwsh @args 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | Out-String).Trim())
  if ($exitCode -ne 0) {
    $safe = $text -replace "(?i)authorization\s*[:=]\s*bearer\s+\S+", "authorization=[redacted]"
    $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
    throw "skybridge-status.ps1 read-only hygiene query failed: $safe"
  }
  return ($text | ConvertFrom-Json)
}

function Test-UnsafeTaskSurface {
  param($Task)
  $risk = ([string](Get-Prop -Object $Task -Name "risk" -Default "")).ToLowerInvariant()
  $taskType = ([string](Get-Prop -Object $Task -Name "task_type" -Default "")).ToLowerInvariant()
  $required = (@(Get-Prop -Object $Task -Name "required_capabilities" -Default @()) -join " ").ToLowerInvariant()
  $paths = (@(Get-Prop -Object $Task -Name "allowed_paths" -Default @()) -join " ").ToLowerInvariant()
  $combined = "$risk $taskType $required $paths"
  if ($risk -in @("high", "blocked", "production")) { return $true }
  return ($combined -match "(production|deploy|secret|credential|token|cookie|github-settings|branch-protection|server-config|server-root|openresty|authelia|1panel|/opt/skybridge-agent-hub)")
}

function New-TaskRecord {
  param($Task, [string]$Classification, [string[]]$ReasonCodes, [string]$RecommendedAction)
  $leaseDisplay = Get-Prop -Object $Task -Name "lease_display_status"
  $leaseStatus = Get-Prop -Object $Task -Name "lease_status"
  $prUrl = Get-Prop -Object $Task -Name "pr_url"
  $evidenceSummary = Get-Prop -Object $Task -Name "evidence_summary"
  $recovered = [bool](Get-Prop -Object $Task -Name "recovered" -Default $false)
  $ciStatus = Get-Prop -Object $Task -Name "ci_status"
  [pscustomobject]@{
    task_id = [string](Get-Prop -Object $Task -Name "task_id" -Default "")
    status = [string](Get-Prop -Object $Task -Name "raw_status" -Default (Get-Prop -Object $Task -Name "status" -Default "unknown"))
    hygiene_status = [string](Get-Prop -Object $Task -Name "task_hygiene_status" -Default "unknown")
    classification = $Classification
    reason_codes = @($ReasonCodes)
    risk = [string](Get-Prop -Object $Task -Name "risk" -Default "not_reported")
    task_type = [string](Get-Prop -Object $Task -Name "task_type" -Default "not_reported")
    assigned_worker_id = [string](Get-Prop -Object $Task -Name "worker_id" -Default "-")
    worker_status = Get-Prop -Object $Task -Name "worker_status"
    claim_state = [pscustomobject]@{
      assigned = ([string](Get-Prop -Object $Task -Name "worker_id" -Default "-") -ne "-")
      stale_claim = ([string](Get-Prop -Object $Task -Name "task_hygiene_status") -eq "stale_claim")
    }
    lease_state = [pscustomobject]@{
      present = -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Object $Task -Name "lease_id"))
      status = if ($leaseStatus) { [string]$leaseStatus } else { "not_reported" }
      display_status = if ($leaseDisplay) { [string]$leaseDisplay } else { "not_reported" }
      stale_or_expired = ($leaseDisplay -in @("expired", "stale", "abandoned", "inconsistent"))
    }
    related_pr = [pscustomobject]@{
      present = -not [string]::IsNullOrWhiteSpace([string]$prUrl)
      value_included = $false
    }
    evidence = [pscustomobject]@{
      present = ($null -ne $evidenceSummary)
      recovered = $recovered
      ci_status = if ($ciStatus) { [string]$ciStatus } else { "not_reported" }
      needs_repair = ([string](Get-Prop -Object $Task -Name "task_hygiene_status") -eq "pr_merged_needs_evidence")
    }
    recommended_action = $RecommendedAction
  }
}

function Get-TaskClassification {
  param($Task)
  $status = [string](Get-Prop -Object $Task -Name "raw_status" -Default (Get-Prop -Object $Task -Name "status" -Default "unknown"))
  $hygiene = [string](Get-Prop -Object $Task -Name "task_hygiene_status" -Default "unknown")
  $unsafeSurface = Test-UnsafeTaskSurface -Task $Task

  switch ($hygiene) {
    "pr_merged_needs_evidence" {
      return New-TaskRecord -Task $Task -Classification "evidence-repair-only" -ReasonCodes @("failed_task_has_related_pr", "recovered_evidence_missing") -RecommendedAction "Run a later explicit evidence-repair goal; do not requeue or create a new PR."
    }
    "failed_unrecovered" {
      return New-TaskRecord -Task $Task -Classification "unsafe-to-requeue" -ReasonCodes @("failed_unrecovered", "manual_review_required_before_any_retry") -RecommendedAction "Keep out of worker execution; classify recovery in a later explicit goal."
    }
    "blocked_historical" {
      $reason = if ($unsafeSurface) { @("blocked_status", "unsafe_or_policy_surface") } else { @("blocked_status", "historical_residue") }
      $class = if ($unsafeSurface) { "blocked-by-policy" } else { "historical-residue" }
      return New-TaskRecord -Task $Task -Classification $class -ReasonCodes $reason -RecommendedAction "Keep blocked in the report unless a later goal explicitly archives or resolves it."
    }
    { $_ -in @("stale_claim", "stale_running", "lease_missing", "lease_expired") } {
      return New-TaskRecord -Task $Task -Classification "recoverable" -ReasonCodes @($hygiene, "lease_or_claim_recovery_required") -RecommendedAction "Use a later explicit preview/apply recovery goal; this report is read-only."
    }
    default {
      if ($status -eq "failed") {
        return New-TaskRecord -Task $Task -Classification "unsafe-to-requeue" -ReasonCodes @("failed_without_safe_recovery_evidence") -RecommendedAction "Do not requeue from Goal 315."
      }
      if ($status -eq "blocked") {
        return New-TaskRecord -Task $Task -Classification "historical-residue" -ReasonCodes @("blocked_status") -RecommendedAction "Keep blocked in this report; later goal may archive after review."
      }
      return New-TaskRecord -Task $Task -Classification "not-residue" -ReasonCodes @("no_hygiene_action_required") -RecommendedAction "No Goal 315 action."
    }
  }
}

$generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$status = Invoke-StatusReport
$tasks = @((Get-Prop -Object $status -Name "tasks" -Default @()) | Where-Object { $null -ne $_ })
$classifiedTasks = @($tasks | ForEach-Object { Get-TaskClassification -Task $_ })

$failedUnrecoveredTasks = @($classifiedTasks | Where-Object { $_.reason_codes -contains "failed_unrecovered" -or ($_.status -eq "failed" -and $_.classification -eq "unsafe-to-requeue") })
$blockedTasks = @($classifiedTasks | Where-Object { $_.status -eq "blocked" -or $_.classification -in @("blocked-by-policy", "historical-residue") })
$needsEvidenceTasks = @($classifiedTasks | Where-Object { $_.classification -eq "evidence-repair-only" })
$staleLeaseTasks = @($classifiedTasks | Where-Object { $_.lease_state.stale_or_expired })
$staleClaimTasks = @($classifiedTasks | Where-Object { $_.claim_state.stale_claim })
$safeRequeueCandidates = @($classifiedTasks | Where-Object { $_.classification -eq "recoverable" -and $_.status -eq "failed" -and -not ($_.reason_codes -contains "lease_or_claim_recovery_required") })
$evidenceRepairCandidates = @($classifiedTasks | Where-Object { $_.classification -eq "evidence-repair-only" })
$archiveOrKeepBlockedCandidates = @($classifiedTasks | Where-Object { $_.classification -in @("historical-residue", "blocked-by-policy") })
$unsafeToRequeueCandidates = @($classifiedTasks | Where-Object { $_.classification -eq "unsafe-to-requeue" -or $_.classification -eq "blocked-by-policy" })

$taskSummary = Get-Prop -Object $status -Name "task_summary"
$recommended = if ($needsEvidenceTasks.Count -gt 0) {
  "Open a later Goal 316 evidence-repair-only plan; do not claim, requeue, or execute tasks."
} elseif ($failedUnrecoveredTasks.Count -gt 0 -or $blockedTasks.Count -gt 0) {
  "Keep project control paused and prepare a later explicit recovery/archive plan."
} elseif ($staleLeaseTasks.Count -gt 0 -or $staleClaimTasks.Count -gt 0) {
  "Prepare a later explicit stale lease or claim recovery preview."
} else {
  "No task hygiene residue requiring Goal 315 follow-up was found."
}

$report = [pscustomobject]@{
  schema = "skybridge.task_hygiene_report.v1"
  ok = $true
  generated_at = $generatedAt
  project_id = $ProjectId
  total_tasks = Get-Count -Object $taskSummary -Name "total"
  failed_unrecovered = $failedUnrecoveredTasks.Count
  blocked = $blockedTasks.Count
  needs_evidence = $needsEvidenceTasks.Count
  stale_leases = $staleLeaseTasks.Count
  stale_claims = $staleClaimTasks.Count
  safe_requeue_candidates = @($safeRequeueCandidates)
  evidence_repair_candidates = @($evidenceRepairCandidates)
  archive_or_keep_blocked_candidates = @($archiveOrKeepBlockedCandidates)
  unsafe_to_requeue_candidates = @($unsafeToRequeueCandidates)
  task_classifications = @($classifiedTasks)
  source = [pscustomobject]@{
    api_base = "configured"
    status_query = "skybridge-status -Hygiene -ShowLeases -ShowAll -Json"
    full_task_list_available = $true
    task_summary_available = ($null -ne $taskSummary)
  }
  recommended_next_safe_action = $recommended
  safety = [pscustomobject]@{
    read_only = $true
    tasks_mutated = $false
    tasks_claimed = $false
    tasks_requeued = $false
    tasks_cancelled = $false
    project_control_unpaused = $false
    queue_apply_called = $false
    campaign_metadata_advanced = $false
    codex_run_called = $false
    raw_logs_included = $false
    raw_prompts_included = $false
    token_printed = $false
  }
  read_only = $true
  tasks_mutated = $false
  tasks_claimed = $false
  tasks_requeued = $false
  tasks_cancelled = $false
  project_control_unpaused = $false
  queue_apply_called = $false
  campaign_metadata_advanced = $false
  codex_run_called = $false
  raw_logs_included = $false
  raw_prompts_included = $false
  token_printed = $false
}

if ($OutputFile) {
  $dir = Split-Path -Parent $OutputFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
}

if ($Json) {
  $report | ConvertTo-Json -Depth 40
} else {
  "Schema:       $($report.schema)"
  "Project:      $($report.project_id)"
  "Tasks:        total=$($report.total_tasks) failed_unrecovered=$($report.failed_unrecovered) blocked=$($report.blocked) needs_evidence=$($report.needs_evidence)"
  "Stale:        leases=$($report.stale_leases) claims=$($report.stale_claims)"
  "Candidates:   evidence_repair=$(@($report.evidence_repair_candidates).Count) keep_blocked=$(@($report.archive_or_keep_blocked_candidates).Count) unsafe_requeue=$(@($report.unsafe_to_requeue_candidates).Count)"
  "ReadOnly:     true"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
