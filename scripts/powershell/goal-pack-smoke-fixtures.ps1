$ErrorActionPreference = "Stop"

function Get-GoalPackSmokeRepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function New-GoalPackSmokeFixture {
  param([Parameter(Mandatory = $true)][string]$Name)
  $repoRoot = Get-GoalPackSmokeRepoRoot
  $source = Join-Path $repoRoot "goals\dev-queue-189-200"
  $root = Join-Path $repoRoot ".agent\tmp\goal-pack-smokes"
  $target = Join-Path $root $Name
  if (-not $target.StartsWith((Join-Path $repoRoot ".agent\tmp"))) {
    throw "Fixture target escaped .agent/tmp."
  }
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Copy-Item -Path (Join-Path $source "*") -Destination $target -Recurse -Force
  return $target
}

function Invoke-GoalPackHelper {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $repoRoot = Get-GoalPackSmokeRepoRoot
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-goal-pack.ps1") @Arguments -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-goal-pack.ps1 failed: $raw" }
  $result = $raw | ConvertFrom-Json
  if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }
  return $result
}

function Assert-NoExecutionResult {
  param([Parameter(Mandatory = $true)]$Result)
  $noExecution = $Result.no_execution
  if ($noExecution) {
    if ($noExecution.task_created -ne $false) { throw "task_created must be false." }
    if ($noExecution.worker_loop_started -ne $false) { throw "worker_loop_started must be false." }
    if ($noExecution.queue_execution_enabled -ne $false) { throw "queue_execution_enabled must be false." }
    if ($noExecution.live_campaign_mutated -ne $false) { throw "live_campaign_mutated must be false." }
  }
  if ($Result.task_created -eq $true) { throw "task_created must not be true." }
  if ($Result.worker_loop_started -eq $true) { throw "worker_loop_started must not be true." }
  if ($Result.queue_execution_enabled -eq $true) { throw "queue_execution_enabled must not be true." }
}

function Assert-SafeToPaste {
  param([Parameter(Mandatory = $true)][string]$Text)
  $secretPattern = "(?i)(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|-----BEGIN (RSA |OPENSSH |PRIVATE )?PRIVATE KEY-----|cookie\s*[:=]\s*\S+)"
  if ($Text -match $secretPattern) { throw "Output contains secret-looking text." }
  if ($Text -notmatch '"token_printed":false') { throw "Output missing token_printed=false." }
}

function Get-GitShortStatusText {
  $repoRoot = Get-GoalPackSmokeRepoRoot
  return (git -C $repoRoot status --short | Out-String).Trim()
}
