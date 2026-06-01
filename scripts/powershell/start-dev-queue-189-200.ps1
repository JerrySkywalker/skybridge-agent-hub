[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "https://skybridge.jerryskywalker.space" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$WorkerProfile = "$HOME\.skybridge\worker.laptop-zenbookduo.json",
  [string]$TokenFile = "$HOME\.skybridge\secrets\worker-token.txt",
  [string]$HermesEnvFile = "$HOME\.skybridge\hermes.env.ps1",
  [int]$MaxRuntimeMinutes = 240,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputDir = ".agent/tmp"
)

$ErrorActionPreference = "Stop"

function Invoke-JsonScript {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')`n$($output -join "`n")" }
  return ($output | ConvertFrom-Json)
}

function Test-GitCleanMain {
  $branch = (git branch --show-current).Trim()
  if ($branch -ne "main") { throw "start-dev-queue-189-200 must run from main after Goal 188 is merged. Current branch: $branch" }
  git fetch origin main | Out-Null
  $local = (git rev-parse main).Trim()
  $remote = (git rev-parse origin/main).Trim()
  if ($local -ne $remote) { throw "main is not equal to origin/main. Pull latest main first." }
  if (-not [string]::IsNullOrWhiteSpace((git status --short | Out-String).Trim())) { throw "Working tree must be clean." }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$jsonReport = Join-Path $OutputDir "dev-queue-189-200-runner-report.json"
$markdownReport = Join-Path $OutputDir "dev-queue-189-200-runner-report.md"

Test-GitCleanMain

$validate = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "validate-pack", "-GoalPackDir", "goals\dev-queue-189-200", "-Json")
if (-not $validate.validation.ok) { throw "Dev queue validation failed." }

$importArgs = @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "import", "-GoalPackDir", "goals\dev-queue-189-200", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-Json")
if ($Apply) { $importArgs += "-Apply" } else { $importArgs += "-DryRun" }
$import = Invoke-JsonScript $importArgs

$active = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-ActiveOnly", "-Json")
$hygiene = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-status.ps1", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-Hygiene", "-ColorMode", "Never", "-Json")
if ([int]$active.task_summary.active -ne 0) { throw "Active tasks are present; refusing to start dev queue." }
if ([int]$hygiene.task_summary.stale_leases -ne 0) { throw "Stale leases are present; refusing to start dev queue." }

$runArgs = @(
  "-File", ".\scripts\powershell\skybridge-campaign.ps1",
  "run-until-hold",
  "-CampaignId", "dev-queue-189-200",
  "-ApiBase", $ApiBase,
  "-ProjectId", $ProjectId,
  "-TokenFile", $TokenFile,
  "-WorkerProfile", $WorkerProfile,
  "-HermesEnvFile", $HermesEnvFile,
  "-MaxSteps", "12",
  "-MaxTasks", "12",
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

Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-report", "-CampaignId", "dev-queue-189-200", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-OutputFile", $markdownReport, "-Json") | Out-Null
$finalStatus = Invoke-JsonScript @("-File", ".\scripts\powershell\skybridge-campaign.ps1", "runner-status", "-CampaignId", "dev-queue-189-200", "-ApiBase", $ApiBase, "-ProjectId", $ProjectId, "-TokenFile", $TokenFile, "-Json")

$result = [pscustomobject]@{
  ok = $true
  mode = if ($Apply) { "apply" } else { "dry-run" }
  token_printed = $false
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
