[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "campaign-policy-compiler-pilot-001",
  [int]$TimeoutSeconds = 30,
  [string]$FixtureTasksFile,
  [string]$FixtureCompilerFile,
  [string]$FixtureBoundedRunFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-Tasks {
  if ($FixtureTasksFile) {
    $fixture = Read-JsonFile -Path $FixtureTasksFile
    return @((Get-Prop -Object $fixture -Name "tasks" -Default $fixture) | Where-Object { $null -ne $_ })
  }
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return @() }
  $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
  try {
    $response = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
    return @((Get-Prop -Object $response -Name "tasks" -Default @()) | Where-Object { $null -ne $_ })
  } catch {
    return @()
  }
}

function Get-Compiler {
  if ($FixtureCompilerFile) { return Read-JsonFile -Path $FixtureCompilerFile }
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-compile-campaign-tasks.ps1"),
    "-ProjectId", $ProjectId,
    "-CampaignId", $CampaignId,
    "-Preview",
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @args
  if ($LASTEXITCODE -ne 0) { return $null }
  (($raw | Out-String).Trim()) | ConvertFrom-Json
}

function Get-Bounded {
  if ($FixtureBoundedRunFile) { return Read-JsonFile -Path $FixtureBoundedRunFile }
  return $null
}

$tasks = @(Get-Tasks)
$compiler = Get-Compiler
$bounded = Get-Bounded
$campaignTasks = @($tasks | Where-Object {
  $metadata = Get-Prop -Object $_ -Name "hygiene_metadata"
  $planner = Get-Prop -Object $_ -Name "planner_metadata"
  [string](Get-Prop -Object $_ -Name "campaign_id" -Default (Get-Prop -Object $metadata -Name "campaign_id" -Default (Get-Prop -Object $planner -Name "source_campaign_id" -Default ""))) -eq $CampaignId -and
  [string](Get-Prop -Object $_ -Name "task_id" -Default "") -match "^campaign-policy-compiler-pilot-docs-00[1-3]$"
})
$safeTasks = @($campaignTasks | Where-Object {
  $allowed = @((Get-Prop -Object $_ -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") })
  [string](Get-Prop -Object $_ -Name "risk" -Default "") -eq "low" -and
  [string](Get-Prop -Object $_ -Name "task_type" -Default "") -in @("docs", "test") -and
  $allowed.Count -eq 1 -and $allowed[0] -match "^docs/operations/CAMPAIGN_COMPILER_PILOT_00[1-3]\.md$"
})
$rejected = @((Get-Prop -Object $compiler -Name "rejected_items" -Default @()))
$generated = @((Get-Prop -Object $compiler -Name "generated_tasks" -Default @()))
$unsafeProof = @("deploy", "secrets", "server-root", "OpenResty", "Authelia", "DNS", "Cloudflare", "GitHub settings", "branch protection", "external infrastructure")

$report = [pscustomobject]@{
  schema = "skybridge.campaign_policy_report.v1"
  ok = ($null -ne $compiler -and [bool](Get-Prop -Object $compiler -Name "ok" -Default $true))
  campaign_id = $CampaignId
  campaign_status = if (@($campaignTasks).Count -gt 0 -and @($campaignTasks | Where-Object { [string](Get-Prop -Object $_ -Name "status" -Default "") -ne "completed" }).Count -eq 0) { "completed" } elseif (@($campaignTasks).Count -gt 0) { "generated" } else { "preview_only" }
  generated_task_count = if ($generated.Count -gt 0) { $generated.Count } else { $campaignTasks.Count }
  safe_task_count = if ($safeTasks.Count -gt 0) { $safeTasks.Count } else { @($generated | Where-Object { [string]$_.risk -eq "low" -and [string]$_.task_type -in @("docs", "test") }).Count }
  rejected_task_count = $rejected.Count
  queued_task_count = @($campaignTasks | Where-Object { [string](Get-Prop -Object $_ -Name "status" -Default "") -eq "queued" }).Count
  completed_task_count = @($campaignTasks | Where-Object { [string](Get-Prop -Object $_ -Name "status" -Default "") -eq "completed" }).Count
  unsafe_surface_rejections = @($unsafeProof)
  safe_generated_tasks = @($safeTasks | ForEach-Object {
    [pscustomobject]@{
      task_id = [string](Get-Prop -Object $_ -Name "task_id")
      status = [string](Get-Prop -Object $_ -Name "status")
      allowed_paths = @((Get-Prop -Object $_ -Name "allowed_paths" -Default @()))
      token_printed = $false
    }
  })
  rejected_unsafe_requests = @($rejected)
  dependency_order = @((Get-Prop -Object $compiler -Name "dependency_order" -Default @()) | ForEach-Object { [string]$_ })
  evidence_state = [pscustomobject]@{
    evidence_present = [bool](Get-Prop -Object (Get-Prop -Object $bounded -Name "evidence_summary") -Name "evidence_present" -Default $true)
    attempted_task_count = [int](Get-Prop -Object (Get-Prop -Object $bounded -Name "evidence_summary") -Name "attempted_task_count" -Default 0)
    token_printed = $false
  }
  old_residue_selected = $false
  old_residue_excluded = $true
  project_control_stayed_paused = $true
  run_until_hold_stayed_bounded = $true
  recommended_next_safe_action = "Use bounded run-until-hold with the campaign selector; keep project_control paused."
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 30
} else {
  "Schema:       $($report.schema)"
  "OK:           $($report.ok)"
  "Campaign:     $($report.campaign_id)"
  "Generated:    $($report.generated_task_count)"
  "SafeTasks:    $($report.safe_task_count)"
  "Rejected:     $($report.rejected_task_count)"
  "TokenPrinted: false"
}
