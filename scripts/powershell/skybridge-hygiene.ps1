[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("audit", "report", "stale-leases", "stale-tasks", "proposals", "recover-lease", "reconcile-evidence", "mark-abandoned", "requeue-safe")]
  [string]$Command = "audit",
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [string]$TaskId,
  [string]$LeaseId,
  [string]$ProposalId,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputFile,
  [string]$Reason,
  [switch]$Color,
  [switch]$NoColor
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-HygieneApiConfig {
  $authMode = "none"
  if ($TokenEnvVar -or $TokenFile) { $authMode = "bearer_token" }
  [pscustomobject]@{ api_base = $ApiBase; project_id = $ProjectId; auth_mode = $authMode; token_env_var = $TokenEnvVar; token_file = $TokenFile }
}

function Invoke-HygieneApi {
  param([string]$Method, [string]$Path, $Body = $null)
  Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $ApiBase -Body $Body -Config $script:Config -TimeoutSeconds 30
}

function Get-HygieneStatus {
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-status.ps1") `
    -ApiBase $ApiBase -ProjectId $ProjectId -TokenEnvVar $TokenEnvVar -TokenFile $TokenFile -Hygiene -ShowProposals -ShowLeases -ShowLocks -ShowAll -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-status.ps1 -Hygiene failed." }
  return ($output | ConvertFrom-Json)
}

function Select-HygieneView {
  param($Status)
  [pscustomobject]@{
    ok = $true
    command = $Command
    mode = if ($Apply) { "apply" } else { "dry-run" }
    api_base = $ApiBase
    project_id = $ProjectId
    token_printed = $false
    hygiene_summary = $Status.hygiene_summary
    hygiene_findings = @($Status.hygiene_findings)
    recommended_actions = @($Status.recommended_actions)
  }
}

function Write-HygieneResult {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 60 -Compress; return }
  "Command:      $($Result.command)"
  "Mode:         $($Result.mode)"
  "Project:      $($Result.project_id)"
  if ($Result.hygiene_summary) {
    "ActiveTasks:  $($Result.hygiene_summary.active_tasks)"
    "StaleLeases:  $($Result.hygiene_summary.stale_leases)"
    "FailedOpen:   $($Result.hygiene_summary.failed_unrecovered_tasks)"
    "ApprovedOpen: $($Result.hygiene_summary.approved_unconverted_proposals)"
    "ConvertedOpen:$($Result.hygiene_summary.converted_unexecuted_proposals)"
    "DerivedExec:  $($Result.hygiene_summary.derived_executed_proposals)"
  }
  if ($Result.action) { "Action:       $($Result.action)" }
  if ($Result.task) { "Task:         $($Result.task.task_id)" }
  if ($Result.lease) { "Lease:        $($Result.lease.lease_id)" }
  if ($Result.hygiene_findings) {
    "Findings:     $(@($Result.hygiene_findings).Count)"
    foreach ($finding in @($Result.hygiene_findings | Select-Object -First 20)) {
      "  $($finding.kind) $($finding.id) $($finding.status) - $($finding.recommended_action)"
    }
  }
  "TokenPrinted: false"
}

$script:Config = New-HygieneApiConfig
if ($script:Config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $script:Config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

$effectiveDryRun = $DryRun -or -not $Apply
$status = Get-HygieneStatus
$result = Select-HygieneView -Status $status

switch ($Command) {
  "audit" {}
  "report" {}
  "stale-leases" {
    $result.hygiene_findings = @($result.hygiene_findings | Where-Object { $_.kind -eq "lease" })
  }
  "stale-tasks" {
    $result.hygiene_findings = @($result.hygiene_findings | Where-Object { $_.kind -eq "task" -and $_.status -match "stale|lease|failed|evidence" })
  }
  "proposals" {
    $result.hygiene_findings = @($result.hygiene_findings | Where-Object { $_.kind -eq "proposal" })
  }
  "recover-lease" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "recover-lease requires -TaskId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "recover-lease requires -Reason." }
    if ($effectiveDryRun) {
      $result | Add-Member -NotePropertyName action -NotePropertyValue "would_release_stale_lease" -Force
      $result | Add-Member -NotePropertyName task_id -NotePropertyValue $TaskId -Force
      $result | Add-Member -NotePropertyName lease_id -NotePropertyValue $LeaseId -Force
    } else {
      $body = @{ action = "release-stale"; reason = $Reason }
      if ($LeaseId) { $body.lease_id = $LeaseId }
      $payload = Invoke-HygieneApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/lease-recovery" -Body $body
      $result | Add-Member -NotePropertyName action -NotePropertyValue $payload.action -Force
      $result | Add-Member -NotePropertyName task -NotePropertyValue $payload.task -Force
    }
  }
  "mark-abandoned" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "mark-abandoned requires -TaskId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "mark-abandoned requires -Reason." }
    if ($effectiveDryRun) {
      $result | Add-Member -NotePropertyName action -NotePropertyValue "would_mark_abandoned" -Force
      $result | Add-Member -NotePropertyName task_id -NotePropertyValue $TaskId -Force
      $result | Add-Member -NotePropertyName lease_id -NotePropertyValue $LeaseId -Force
    } else {
      $body = @{ action = "mark-abandoned"; reason = $Reason }
      if ($LeaseId) { $body.lease_id = $LeaseId }
      $payload = Invoke-HygieneApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/lease-recovery" -Body $body
      $result | Add-Member -NotePropertyName action -NotePropertyValue $payload.action -Force
      $result | Add-Member -NotePropertyName task -NotePropertyValue $payload.task -Force
    }
  }
  "requeue-safe" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "requeue-safe requires -TaskId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "requeue-safe requires -Reason." }
    if ($effectiveDryRun) {
      $result | Add-Member -NotePropertyName action -NotePropertyValue "would_requeue_safe" -Force
      $result | Add-Member -NotePropertyName task_id -NotePropertyValue $TaskId -Force
    } else {
      $body = @{ action = "requeue-safe"; reason = $Reason }
      if ($LeaseId) { $body.lease_id = $LeaseId }
      $payload = Invoke-HygieneApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/lease-recovery" -Body $body
      $result | Add-Member -NotePropertyName action -NotePropertyValue $payload.action -Force
      $result | Add-Member -NotePropertyName task -NotePropertyValue $payload.task -Force
    }
  }
  "reconcile-evidence" {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "reconcile-evidence requires -TaskId." }
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw "reconcile-evidence requires -Reason." }
    if (-not $effectiveDryRun) { throw "reconcile-evidence apply is intentionally not automated; use the evidence repair command with explicit evidence." }
    $result | Add-Member -NotePropertyName action -NotePropertyValue "would_reconcile_evidence" -Force
    $result | Add-Member -NotePropertyName task_id -NotePropertyValue $TaskId -Force
  }
}

Write-HygieneResult -Result $result
