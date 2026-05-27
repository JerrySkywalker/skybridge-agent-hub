[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("list", "show", "accept", "reject", "convert")]
  [string]$Command,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$MasterGoalId,
  [string]$ProposalId,
  [string]$TaskId,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$AllowHighRisk,
  [switch]$Json,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-ProposalApiConfig {
  $authMode = "none"
  if ($TokenEnvVar -or $TokenFile) { $authMode = "bearer_token" }
  [pscustomobject]@{ api_base = $ApiBase; project_id = $ProjectId; auth_mode = $authMode; token_env_var = $TokenEnvVar; token_file = $TokenFile }
}

function Invoke-ProposalApi {
  param([string]$Method, [string]$Path, $Body = $null)
  Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $ApiBase -Body $Body -Config $script:Config -TimeoutSeconds 20
}

function Write-ProposalResult {
  param($Result)
  if ($OutputFile) {
    $dir = Split-Path -Parent $OutputFile
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Result | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) { $Result | ConvertTo-Json -Depth 50 -Compress; return }
  "Command:      $($Result.command)"
  "Mode:         $($Result.mode)"
  "Project:      $($Result.project_id)"
  if ($Result.proposal) {
    "Proposal:     $($Result.proposal.proposal_id)"
    "Status:       $($Result.proposal.status)"
    "Risk:         $($Result.proposal.risk)"
    "Title:        $($Result.proposal.title)"
    "Files:        $(@($Result.proposal.expected_files) -join ', ')"
  }
  if ($Result.task) { "Task:         $($Result.task.task_id)" }
  if ($Result.proposals) { "Proposals:    $(@($Result.proposals).Count)" }
  "TokenPrinted: false"
}

$script:Config = New-ProposalApiConfig
if ($script:Config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $script:Config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}
$effectiveDryRun = $DryRun -or -not $Apply
$result = $null

switch ($Command) {
  "list" {
    $path = "/v1/task-proposals?project_id=$([uri]::EscapeDataString($ProjectId))"
    if ($MasterGoalId) { $path += "&master_goal_id=$([uri]::EscapeDataString($MasterGoalId))" }
    $payload = Invoke-ProposalApi -Method GET -Path $path
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; proposals = @($payload.proposals) }
  }
  "show" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal show requires -ProposalId." }
    $payload = Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))"
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; project_id = $ProjectId; token_printed = $false; proposal = $payload.proposal }
  }
  "accept" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal accept requires -ProposalId." }
    $current = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    $proposal = if ($effectiveDryRun) { $current } else { (Invoke-ProposalApi -Method PATCH -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))" -Body @{ status = "accepted" }).proposal }
    if ($effectiveDryRun) { $proposal.status = "would_accept" }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }; project_id = $ProjectId; token_printed = $false; proposal = $proposal }
  }
  "reject" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal reject requires -ProposalId." }
    $current = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    $proposal = if ($effectiveDryRun) { $current } else { (Invoke-ProposalApi -Method PATCH -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))" -Body @{ status = "rejected" }).proposal }
    if ($effectiveDryRun) { $proposal.status = "would_reject" }
    $result = [pscustomobject]@{ ok = $true; command = $Command; mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }; project_id = $ProjectId; token_printed = $false; proposal = $proposal }
  }
  "convert" {
    if ([string]::IsNullOrWhiteSpace($ProposalId)) { throw "proposal convert requires -ProposalId." }
    $proposal = (Invoke-ProposalApi -Method GET -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))").proposal
    if ($proposal.risk -eq "high" -and -not $AllowHighRisk) { throw "High-risk proposals require -AllowHighRisk before conversion." }
    if ($effectiveDryRun) {
      $task = [pscustomobject]@{
        task_id = if ($TaskId) { $TaskId } else { "task_$ProposalId" }
        project_id = $proposal.project_id
        title = $proposal.title
        body = $proposal.body
        prompt_summary = $proposal.prompt_summary
        risk = $proposal.risk
        source = "planner"
        task_type = $proposal.task_type
        allowed_paths = @($proposal.expected_files)
        validation = @($proposal.evidence_requirements)
        required_capabilities = @($proposal.required_capabilities)
      }
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "dry-run"; project_id = $ProjectId; token_printed = $false; proposal = $proposal; task = $task }
    } else {
      $body = @{ allow_high_risk = [bool]$AllowHighRisk }
      if ($TaskId) { $body.task_id = $TaskId }
      $payload = Invoke-ProposalApi -Method POST -Path "/v1/task-proposals/$([uri]::EscapeDataString($ProposalId))/convert" -Body $body
      $result = [pscustomobject]@{ ok = $true; command = $Command; mode = "apply"; project_id = $ProjectId; token_printed = $false; proposal = $payload.proposal; task = $payload.task }
    }
  }
}

Write-ProposalResult -Result $result
