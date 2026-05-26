[CmdletBinding()]
param(
  [int]$PrNumber,
  [int]$RunId = 0,
  [switch]$Apply,
  [switch]$Json,
  [string]$FixtureRunsFile,
  [string]$FixtureLogFile
)

$ErrorActionPreference = "Stop"
$rerunJson = $Json
. (Join-Path $PSScriptRoot "skybridge-ci-classifier.ps1")
$Json = $rerunJson

function Write-RerunResult($Result) {
  if ($Json) { $Result | ConvertTo-Json -Depth 20 -Compress }
  else { $Result | Format-List }
}

function Read-Runs {
  if (-not [string]::IsNullOrWhiteSpace($FixtureRunsFile)) {
    return @(Get-Content -Raw -LiteralPath $FixtureRunsFile | ConvertFrom-Json)
  }
  if ($PrNumber -le 0 -and $RunId -le 0) { throw "Provide -PrNumber or -RunId." }
  if ($RunId -gt 0) {
    $run = gh run view $RunId --json databaseId,conclusion,status,displayTitle,workflowName,url
    if ($LASTEXITCODE -ne 0) { throw "gh run view failed." }
    return @($run | ConvertFrom-Json)
  }
  $pr = gh pr view $PrNumber --json headRefName
  if ($LASTEXITCODE -ne 0) { throw "gh pr view failed." }
  $head = ($pr | ConvertFrom-Json).headRefName
  $runs = gh run list --branch $head --json databaseId,conclusion,status,displayTitle,workflowName,url --limit 20
  if ($LASTEXITCODE -ne 0) { throw "gh run list failed." }
  return @($runs | ConvertFrom-Json)
}

$runs = @(Read-Runs)
$failed = @($runs | Where-Object { $_.conclusion -in @("failure", "cancelled", "timed_out", "action_required") -or ($RunId -gt 0 -and $_.databaseId -eq $RunId) })
$logText = ""
if (-not [string]::IsNullOrWhiteSpace($FixtureLogFile)) {
  $logText = Get-Content -Raw -LiteralPath $FixtureLogFile
}
$classification = Get-SkyBridgeCiClassification -LogText $logText -CheckState ($(if ($failed.Count -gt 0) { "failure" } else { "success" }))
$rerun = @()

if ($Apply -and $failed.Count -gt 0 -and [string]::IsNullOrWhiteSpace($FixtureRunsFile)) {
  foreach ($run in $failed) {
    gh run rerun ([int]$run.databaseId) --failed | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to rerun workflow run $($run.databaseId)." }
    $rerun += [int]$run.databaseId
  }
}

Write-RerunResult ([pscustomobject]@{
  ok = $true
  dry_run = -not [bool]$Apply
  pr_number = $PrNumber
  failed_runs = @($failed | ForEach-Object { [pscustomobject]@{ run_id = $_.databaseId; workflow = $_.workflowName; status = $_.status; conclusion = $_.conclusion; url = $_.url } })
  rerun_requested = @($rerun)
  classification = $classification.classification
  one_batch_only = $true
  token_printed = $false
})
