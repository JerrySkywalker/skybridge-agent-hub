[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$MasterGoalId,
  [Parameter(Mandatory = $true)][string]$Title,
  [string]$Description,
  [string[]]$Constraints = @(),
  [string]$ConstraintsFile,
  [string]$ConstraintsJson,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$HermesEnvFile,
  [string]$HermesApiBase,
  [string]$OutputFile,
  [switch]$Json,
  [switch]$SummaryOnly,
  [int]$TimeoutSeconds = 600,
  [int]$MaxHermesAttempts = 3,
  [int]$RetryDelaySeconds = 10,
  [ValidateSet("compact", "full")]
  [string]$StateMode = "compact",
  [switch]$SkipHermesHealthCheck,
  [string]$SummaryOutputFile,
  [string]$PlannerFixtureFile,
  [string]$HealthFixtureFile,
  [string]$PlanScriptPath = ".\scripts\powershell\skybridge-plan.ps1"
)

$ErrorActionPreference = "Stop"

function ConvertTo-ConstraintArray {
  param($Value)
  $items = @()
  if ($null -eq $Value) { return @() }
  foreach ($item in @($Value)) {
    if ($null -eq $item) { continue }
    if ($item -is [string]) {
      if (-not [string]::IsNullOrWhiteSpace($item)) { $items += $item }
    } elseif ($item.PSObject.Properties["constraints"]) {
      $items += ConvertTo-ConstraintArray -Value $item.constraints
    } else {
      $text = [string]$item
      if (-not [string]::IsNullOrWhiteSpace($text)) { $items += $text }
    }
  }
  return @($items)
}

function Read-PreviewConstraints {
  $items = @($Constraints | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($ConstraintsFile) {
    if (-not (Test-Path -LiteralPath $ConstraintsFile -PathType Leaf)) { throw "ConstraintsFile not found: $ConstraintsFile" }
    $raw = Get-Content -Raw -LiteralPath $ConstraintsFile
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
      try { $items += ConvertTo-ConstraintArray -Value ($raw | ConvertFrom-Json) }
      catch { $items += @($raw -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
    }
  }
  if ($ConstraintsJson) {
    $items += ConvertTo-ConstraintArray -Value ($ConstraintsJson | ConvertFrom-Json)
  }
  return @($items)
}

function Invoke-JsonScript {
  param([string[]]$Arguments)
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) {
    $message = ($output | ForEach-Object { [string]$_ }) -join "`n"
    throw "Command failed: pwsh $($Arguments -join ' ')`n$message"
  }
  return ($output | ConvertFrom-Json)
}

function Test-TransientHermesError {
  param([string]$Message)
  if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
  return $Message -match "(?i)(\b502\b|\b503\b|\b504\b|gateway time-out|gateway timeout|timed?\s*out|connection reset|connection was reset|eof|unexpected end|temporarily unavailable)"
}

function Invoke-HermesPlanWithRetry {
  param([string[]]$Arguments, [int]$MaxAttempts, [int]$DelaySeconds)
  $attempts = [Math]::Max(1, $MaxAttempts)
  for ($attempt = 1; $attempt -le $attempts; $attempt++) {
    try {
      $plan = Invoke-JsonScript -Arguments $Arguments
      return [pscustomobject]@{
        plan = $plan
        attempts = $attempt
        retry_needed = ($attempt -gt 1)
        last_error = $null
      }
    } catch {
      $message = $_.Exception.Message
      $transient = Test-TransientHermesError -Message $message
      if (-not $transient -or $attempt -ge $attempts) { throw }
      Start-Sleep -Seconds $DelaySeconds
    }
  }
}

if ($HermesEnvFile) {
  if (-not (Test-Path -LiteralPath $HermesEnvFile -PathType Leaf)) { throw "Hermes env file not found: $HermesEnvFile" }
  . $HermesEnvFile
} elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "load-hermes-env.ps1") -PathType Leaf) {
  . (Join-Path $PSScriptRoot "load-hermes-env.ps1")
}
if ($HermesApiBase) { $env:HERMES_API_BASE = $HermesApiBase }

$health = $null
if (-not $SkipHermesHealthCheck) {
  $healthArgs = @("-File", ".\scripts\powershell\skybridge-hermes-health.ps1", "-Json", "-TimeoutSeconds", [string]$TimeoutSeconds)
  if ($HermesEnvFile) { $healthArgs += @("-HermesEnvFile", $HermesEnvFile) }
  if ($HermesApiBase) { $healthArgs += @("-HermesApiBase", $HermesApiBase) }
  if ($HealthFixtureFile) { $healthArgs += @("-FixtureFile", $HealthFixtureFile) }
  $health = Invoke-JsonScript -Arguments $healthArgs
}

$constraintArray = @(Read-PreviewConstraints)
$constraintJson = $constraintArray | ConvertTo-Json -Depth 8 -Compress

$planArgs = @(
  "-File", $PlanScriptPath,
  "-ApiBase", $ApiBase,
  "-ProjectId", $ProjectId,
  "-Title", $Title,
  "-PlannerMode", "hermes-preview",
  "-DryRun",
  "-Json",
  "-ConstraintsJson", $constraintJson,
  "-StateMode", $StateMode,
  "-TimeoutSeconds", [string]$TimeoutSeconds
)
if ($MasterGoalId) { $planArgs += @("-MasterGoalId", $MasterGoalId) }
if ($Description) { $planArgs += @("-Description", $Description) }
if ($TokenEnvVar) { $planArgs += @("-TokenEnvVar", $TokenEnvVar) }
if ($TokenFile) { $planArgs += @("-TokenFile", $TokenFile) }
if ($PlannerFixtureFile) { $planArgs += @("-FixtureFile", $PlannerFixtureFile) }

$planAttempt = Invoke-HermesPlanWithRetry -Arguments $planArgs -MaxAttempts $MaxHermesAttempts -DelaySeconds $RetryDelaySeconds
$plan = $planAttempt.plan
$proposals = @($plan.proposals)
$accepted = @($proposals | Where-Object { $_.policy_decision -eq "accepted_for_preview" -or $_.policy_decision -eq "accepted_for_execution" })
$askHuman = @($proposals | Where-Object { $_.policy_decision -eq "ask_human" })
$rejected = @($proposals | Where-Object { [string]$_.policy_decision -like "rejected*" })

$summary = [pscustomobject]@{
  ok = $true
  api_base = $ApiBase
  hermes_api_base = if ($health -and $health.api_base) { $health.api_base } elseif ($env:HERMES_API_BASE) { $env:HERMES_API_BASE } else { $null }
  direct_https = if ($health) { $health.direct_https } elseif ($env:HERMES_API_BASE) { $env:HERMES_API_BASE -match "^https://" } else { $false }
  provider = $plan.planner_adapter.provider
  hermes_model = $plan.planner_adapter.model
  model = $plan.planner_adapter.model
  runtime_mode = $plan.planner_adapter.runtime_mode
  planner_mode = $plan.planner_mode
  tool_execution_mode = $plan.planner_adapter.tool_execution_mode
  prompt_version = $plan.planner_adapter.prompt_version
  input_state_hash = $plan.planner_adapter.input_state_hash
  state_mode = $StateMode
  hermes_attempts = $planAttempt.attempts
  retry_needed = $planAttempt.retry_needed
  proposal_count = $proposals.Count
  accepted_for_preview_count = $accepted.Count
  ask_human_count = $askHuman.Count
  rejected_count = $rejected.Count
  token_printed = $false
}

$proposalTable = @($proposals | ForEach-Object {
  [pscustomobject]@{
    proposal_id = $_.proposal_id
    title = $_.title
    risk = $_.risk
    task_type = $_.task_type
    policy_decision = $_.policy_decision
    dedupe_key = $_.dedupe_key
  }
})

$report = [pscustomobject]@{
  summary = $summary
  proposals = @($proposals | ForEach-Object {
    [pscustomobject]@{
      proposal_id = $_.proposal_id
      title = $_.title
      risk = $_.risk
      task_type = $_.task_type
      original_task_type = $_.original_task_type
      original_required_capabilities = @($_.original_required_capabilities)
      normalized_required_capabilities = @($_.normalized_required_capabilities)
      policy_decision = $_.policy_decision
      policy_reasons = @($_.policy_reasons)
      expected_files = @($_.expected_files)
      dedupe_key = $_.dedupe_key
      rationale = $_.rationale
    }
  })
}

$result = [pscustomobject]@{
  ok = $true
  mode = "dry-run"
  token_printed = $false
  summary = $summary
  proposal_table = $proposalTable
  report = $report
  hermes_health = $health
  plan = $plan
  proposals = $proposals
  planning_session = $plan.planning_session
}

if ($OutputFile) {
  $dir = Split-Path -Parent $OutputFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $result | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
}
if ($SummaryOutputFile) {
  $dir = Split-Path -Parent $SummaryOutputFile
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $report | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $SummaryOutputFile -Encoding UTF8
}

if ($Json) {
  if ($SummaryOnly) { $summary | ConvertTo-Json -Depth 20 -Compress } else { $result | ConvertTo-Json -Depth 80 -Compress }
  return
}

"HermesApiBase: $($summary.hermes_api_base)"
"DirectHttps:   $($summary.direct_https)"
"PlannerMode:   $($summary.planner_mode)"
"RuntimeMode:   $($summary.runtime_mode)"
"Model:         $($summary.hermes_model)"
"Proposals:     $($summary.proposal_count)"
"Accepted:      $($summary.accepted_for_preview_count)"
"AskHuman:      $($summary.ask_human_count)"
"Rejected:      $($summary.rejected_count)"
"TokenPrinted:  false"
if (-not $SummaryOnly) {
  $proposalTable | Format-Table -AutoSize
}
