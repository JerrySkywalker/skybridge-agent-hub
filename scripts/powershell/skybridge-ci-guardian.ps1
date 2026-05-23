[CmdletBinding()]
param(
  [int]$PR = 0,
  [switch]$CurrentBranch,
  [switch]$Watch,
  [int]$MaxRepairAttempts = 3,
  [switch]$DryRun,
  [switch]$UpdatePRBody,
  [switch]$EnableAutoMerge,
  [string]$SkyBridgeApiBase,
  [string]$CodexCommand = "codex"
)

$ErrorActionPreference = "Stop"

function Invoke-BootstrapNotification {
  param([string]$Severity, [string]$Title, [string]$Message)
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title $Title `
    -Message $Message `
    -Severity $Severity | Out-Host
}

function Send-GuardianEvent {
  param([string]$Type, [hashtable]$Payload = @{})
  if ([string]::IsNullOrWhiteSpace($SkyBridgeApiBase) -or [string]::IsNullOrWhiteSpace($script:IterationId)) { return }
  try {
    Invoke-RestMethod -Method Post -Uri "$($SkyBridgeApiBase.TrimEnd('/'))/v1/iterations/$script:IterationId/events" `
      -ContentType "application/json" `
      -TimeoutSec 3 `
      -Body (@{ type = $Type; payload = $Payload } | ConvertTo-Json -Depth 12) | Out-Null
  } catch {
    Write-Host "[ci-guardian] SkyBridge event skipped: $($_.Exception.Message)"
  }
}

function Get-CurrentPrNumber {
  if ($PR -gt 0) { return $PR }
  $json = gh pr view --json number 2>$null
  if ($LASTEXITCODE -ne 0) { return 0 }
  return [int](($json | ConvertFrom-Json).number)
}

function Save-FailedWorkflowEvidence {
  param(
    [int]$PrNumber,
    [string]$RunDir,
    [int]$Attempt
  )

  $metadataPath = Join-Path $RunDir "failed-runs-$Attempt.json"
  $logPath = Join-Path $RunDir "failed-workflow-logs-$Attempt.log"

  try {
    $runsJson = gh run list --json databaseId,displayTitle,conclusion,status,event,headBranch,createdAt,url --limit 10 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($runsJson)) {
      return @{ fetched = $false; reason = "gh_run_list_failed" }
    }

    $runsJson | Set-Content -LiteralPath $metadataPath -Encoding UTF8
    $runs = @($runsJson | ConvertFrom-Json)
    $failedRun = $runs | Where-Object { $_.conclusion -in @("failure", "cancelled", "timed_out", "action_required") } | Select-Object -First 1
    if (-not $failedRun) {
      return @{ fetched = $false; reason = "no_failed_run_found"; metadata_path = $metadataPath }
    }

    gh run view $failedRun.databaseId --log-failed *> $logPath
    if ($LASTEXITCODE -ne 0) {
      return @{ fetched = $false; reason = "gh_run_view_failed"; metadata_path = $metadataPath; log_path = $logPath }
    }

    return @{
      fetched = $true
      pr_number = $PrNumber
      run_id = $failedRun.databaseId
      metadata_path = $metadataPath
      log_path = $logPath
      raw_logs_local_only = $true
    }
  } catch {
    return @{ fetched = $false; reason = $_.Exception.Message }
  }
}

$prNumber = Get-CurrentPrNumber
if ($prNumber -le 0) {
  Invoke-BootstrapNotification -Severity "warning" -Title "SkyBridge CI Guardian" -Message "No pull request could be identified."
  @{ ok = $false; error = "pr_not_found"; dry_run = [bool]$DryRun } | ConvertTo-Json -Depth 8
  exit 1
}

$script:IterationId = "iter_pr_$prNumber"
$runDir = Join-Path ".\.agent\iterations" $script:IterationId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

Invoke-BootstrapNotification -Severity "info" -Title "SkyBridge CI Guardian started" -Message "Inspecting PR #$prNumber"
Send-GuardianEvent -Type "iteration.ci_pending" -Payload @{ pr_number = $prNumber; dry_run = [bool]$DryRun }

if ($DryRun) {
  @{ ok = $true; pr_number = $prNumber; dry_run = $true; auto_merge = [bool]$EnableAutoMerge; max_repair_attempts = $MaxRepairAttempts } | ConvertTo-Json -Depth 8
  exit 0
}

$attempt = 0
while ($attempt -le $MaxRepairAttempts) {
  $attempt += 1
  $checksOutput = gh pr checks $prNumber 2>&1
  $checksOutput | Set-Content -LiteralPath (Join-Path $runDir "checks-$attempt.log") -Encoding UTF8
  $checksText = $checksOutput -join "`n"

  if ($checksText -match "fail|cancel|timed_out|action_required") {
    Invoke-BootstrapNotification -Severity "warning" -Title "SkyBridge CI failed" -Message "PR #$prNumber failed checks; repair attempt $attempt of $MaxRepairAttempts."
    $workflowEvidence = Save-FailedWorkflowEvidence -PrNumber $prNumber -RunDir $runDir -Attempt $attempt
    Send-GuardianEvent -Type "iteration.ci_failed" -Payload @{ pr_number = $prNumber; attempt = $attempt; workflow_logs_fetched = [bool]$workflowEvidence.fetched; raw_logs_local_only = $true }
    if ($attempt -gt $MaxRepairAttempts) { break }

    $repairPrompt = @"
Repair PR #$prNumber CI failures using only safe repository edits.

Safety boundaries:
- do not touch secrets, .env, production config, /opt, server root config or Docker daemon config;
- do not remove tests just to pass;
- do not deploy;
- commit a focused repair if checks pass.

Failed check metadata is in $runDir/checks-$attempt.log. Do not upload raw logs to SkyBridge.
"@
    Send-GuardianEvent -Type "iteration.ci_repair_started" -Payload @{ pr_number = $prNumber; attempt = $attempt }
    & $CodexCommand exec --sandbox workspace-write --ask-for-approval never --json --output-last-message (Join-Path $runDir "repair-$attempt-last-message.md") $repairPrompt *> (Join-Path $runDir "repair-$attempt.jsonl")
    if ($LASTEXITCODE -ne 0) {
      Invoke-BootstrapNotification -Severity "urgent" -Title "SkyBridge CI repair failed" -Message "Codex repair failed for PR #$prNumber."
      Send-GuardianEvent -Type "iteration.failed" -Payload @{ pr_number = $prNumber; attempt = $attempt; reason = "codex_repair_failed" }
      exit $LASTEXITCODE
    }

    corepack pnpm check *> (Join-Path $runDir "local-check-$attempt.log")
    if ($LASTEXITCODE -ne 0) {
      Send-GuardianEvent -Type "iteration.local_check_failed" -Payload @{ pr_number = $prNumber; attempt = $attempt }
      continue
    }

    git add -A
    if (-not (git diff --cached --quiet)) {
      git commit -m "fix(iteration): repair CI for PR $prNumber"
      git push
    }
    Send-GuardianEvent -Type "iteration.ci_pending" -Payload @{ pr_number = $prNumber; attempt = $attempt; repaired = $true }
    if (-not $Watch) { break }
    Start-Sleep -Seconds 30
    continue
  }

  Send-GuardianEvent -Type "iteration.ci_green" -Payload @{ pr_number = $prNumber; attempt = $attempt }
  Invoke-BootstrapNotification -Severity "info" -Title "SkyBridge CI green" -Message "PR #$prNumber checks are green."
  if ($UpdatePRBody) {
    gh pr edit $prNumber --body-file (Join-Path $runDir "checks-$attempt.log") | Out-Null
  }
  if ($EnableAutoMerge) {
    gh pr merge $prNumber --auto --squash
    Send-GuardianEvent -Type "iteration.auto_merge_enabled" -Payload @{ pr_number = $prNumber }
  }
  @{ ok = $true; pr_number = $prNumber; state = "ci_green"; attempts = $attempt } | ConvertTo-Json -Depth 8
  exit 0
}

Invoke-BootstrapNotification -Severity "urgent" -Title "SkyBridge CI blocked" -Message "PR #$prNumber still fails after $MaxRepairAttempts repair attempts."
Send-GuardianEvent -Type "iteration.blocked" -Payload @{ pr_number = $prNumber; attempts = $MaxRepairAttempts; reason = "max_repair_attempts_exhausted" }
@{ ok = $false; pr_number = $prNumber; state = "blocked"; attempts = $MaxRepairAttempts } | ConvertTo-Json -Depth 8
exit 1
