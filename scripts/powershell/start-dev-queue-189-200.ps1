[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "https://skybridge.jerryskywalker.space" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$GoalPackDir = "goals/dev-queue-189-200",
  [string]$CampaignId = "dev-queue-189-200",
  [string]$WorkerProfile = "$HOME\.skybridge\worker.laptop-zenbookduo.json",
  [string]$TokenFile = "$HOME\.skybridge\secrets\worker-token.txt",
  [string]$HermesEnvFile = "$HOME\.skybridge\hermes.env.ps1",
  [int]$MaxSteps = 12,
  [int]$MaxTasks = 12,
  [int]$MaxRuntimeMinutes = 240,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputDir = ".agent/tmp",
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"

function Invoke-JsonScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')`n$($output -join "`n")" }
  $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
  try {
    return ($text | ConvertFrom-Json -ErrorAction Stop)
  } catch {
    for ($i = $text.LastIndexOf("{"); $i -ge 0; $i = $text.LastIndexOf("{", $i - 1)) {
      $candidate = $text.Substring($i).Trim()
      try { return ($candidate | ConvertFrom-Json -ErrorAction Stop) } catch {}
      if ($i -eq 0) { break }
    }
    throw "Command did not emit parseable JSON: pwsh $($Arguments -join ' ')`n$($text -replace '(?i)(token|authorization|api[_-]?key)(\s*[:=]\s*)\S+', '$1$2[REDACTED]')"
  }
}

function Test-GitReady {
  $branch = (git branch --show-current).Trim()
  if (-not [string]::IsNullOrWhiteSpace((git status --short | Out-String).Trim())) { throw "Working tree must be clean." }
  if ($Apply) {
    if ($branch -ne "main") { throw "start-dev-queue-189-200 -Apply must run from main after Goal 188 is merged. Current branch: $branch" }
    git fetch --quiet origin main *> $null
    $local = (git rev-parse main).Trim()
    $remote = (git rev-parse origin/main).Trim()
    if ($local -ne $remote) { throw "main is not equal to origin/main. Pull latest main first." }
  }
  return $branch
}

if ($Apply -and $DryRun) { throw "Use either -Apply or -DryRun, not both." }
if ($MaxSteps -lt 1) { throw "-MaxSteps must be at least 1." }
if ($MaxTasks -lt 1) { throw "-MaxTasks must be at least 1." }
if ($MaxRuntimeMinutes -lt 1) { throw "-MaxRuntimeMinutes must be at least 1." }

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$jsonReport = if ([string]::IsNullOrWhiteSpace($OutputFile)) { Join-Path $OutputDir "$CampaignId-runner-report.json" } else { $OutputFile }
$reportDir = Split-Path -Parent $jsonReport
if (-not [string]::IsNullOrWhiteSpace($reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
$markdownReport = Join-Path $OutputDir "$CampaignId-runner-report.md"

$branch = Test-GitReady
$mode = if ($Apply) { "apply" } else { "dry-run" }
$resolved = [pscustomobject]@{
  api_base = $ApiBase
  project_id = $ProjectId
  goal_pack_dir = $GoalPackDir
  campaign_id = $CampaignId
  max_steps = $MaxSteps
  max_tasks = $MaxTasks
  max_runtime_minutes = $MaxRuntimeMinutes
  output_file = $jsonReport
  output_dir = $OutputDir
  mode = $mode
  branch = $branch
  token_printed = $false
}

$validate = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "validate-pack", "-GoalPackDir", $GoalPackDir, "-Json")
if (-not $validate.validation.ok) { throw "Dev queue validation failed." }

$importArgs = @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "import", "-GoalPackDir", $GoalPackDir, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-Json")
if ($Apply) { $importArgs += "-Apply" } else { $importArgs += "-DryRun" }
$import = Invoke-JsonScript $importArgs

$active = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-ActiveOnly", "-Json")
$hygiene = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-Hygiene", "-ColorMode", "Never", "-Json")
if ([int]$active.task_summary.active -ne 0) { throw "Active tasks are present; refusing to start dev queue." }
if ([int]$hygiene.task_summary.stale_leases -ne 0) { throw "Stale leases are present; refusing to start dev queue." }

$runArgs = @(
  "-File", ".\scripts\powershell\skybridge-campaign.ps1",
  "run-until-hold",
  "-CampaignId", $CampaignId,
  "-ApiBase", $ApiBase,
  "-ProjectId", $ProjectId,
  "-TokenFile", $TokenFile,
  "-WorkerProfile", $WorkerProfile,
  "-HermesEnvFile", $HermesEnvFile,
  "-MaxSteps", [string]$MaxSteps,
  "-MaxTasks", [string]$MaxTasks,
  "-MaxRuntimeMinutes", [string]$MaxRuntimeMinutes,
  "-StopOnFailure",
  "-AllowAutoMerge",
  "-AllowEvidenceRepair",
  "-HumanApproved",
  "-HumanApprovalReason", "Operator approved unattended execution of the manually authored Goal 189-200 development queue within bounded safety policy.",
  "-OutputFile", $jsonReport,
  "-Json"
)
if ($Apply) { $runArgs += "-Apply" } else { $runArgs += "-DryRun" }
$runner = Invoke-JsonScript $runArgs

Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-report", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-OutputFile", $markdownReport, "-Json") | Out-Null
$finalStatus = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", $CampaignId, "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-Json")

$result = [pscustomobject]@{
  ok = $true
  mode = $mode
  token_printed = $false
  resolved_parameters = $resolved
  validate = $validate.validation.ok
  import_mode = $import.mode
  active_tasks = $active.task_summary.active
  stale_leases = $hygiene.task_summary.stale_leases
  runner_status = $runner.runner_state.runner_status
  stop_reason = $runner.stop_reason
  reports = @{ json = $jsonReport; markdown = $markdownReport }
  final_status = $finalStatus
}

if ($Json) { $result | ConvertTo-Json -Depth 80 -Compress }
else { $result | Format-List }
