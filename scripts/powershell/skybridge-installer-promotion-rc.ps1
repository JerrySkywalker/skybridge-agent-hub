[CmdletBinding()]
param(
  [ValidateSet("status", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\release-candidate"
$RcVersion = "v1.9.0-installer-promotion-rc"

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value | ConvertTo-Json -Depth 90 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  Set-Content -LiteralPath $Path -Value ($Lines -join "`n") -Encoding utf8
}

function Invoke-JsonScript {
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Script,
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ScriptArgs
  )
  $flatArgs = @()
  foreach ($arg in $ScriptArgs) {
    if ($arg -is [array]) {
      foreach ($nested in $arg) { $flatArgs += [string]$nested }
    } else {
      $flatArgs += [string]$arg
    }
  }
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @flatArgs -Json 2>$null
  if ($LASTEXITCODE -ne 0) { throw "$Script failed" }
  ($raw | Out-String).Trim() | ConvertFrom-Json
}

function New-RcReport {
  $promotion = Invoke-JsonScript "skybridge-installer-promotion.ps1" @("-Command", "report")
  $artifact = Invoke-JsonScript "skybridge-release-candidate-artifact.ps1" @("-Command", "report")
  $soak = Invoke-JsonScript "skybridge-long-soak.ps1" @("-Command", "report", "-CiSmoke")
  $channel = Invoke-JsonScript "skybridge-channel-manifest.ps1" @("-Command", "report")
  $hostGate = Invoke-JsonScript "skybridge-host-mutation-gate.ps1" @("-Command", "gate")
  $interlock = Invoke-JsonScript "skybridge-installer-safety-interlock.ps1" @("-Command", "gate")
  $acceptance = Invoke-JsonScript "skybridge-release-walkthrough.ps1" @("-Command", "acceptance-v4")
  $report = [pscustomobject]@{
    schema = "skybridge.installer_promotion_rc_report.v1"
    rc_version = $RcVersion
    commit = ((& git -C $RepoRoot rev-parse --short HEAD | Out-String).Trim())
    release_workflow_guard_status = $promotion.gate.checks.release_workflow_guard
    artifact_promotion_gate_status = $promotion.status
    release_artifact_manifest_status = $artifact.status
    long_soak_status = $soak.status
    update_channel_manifest_status = $channel.status
    offline_update_rollback_status = "preview"
    host_mutation_gate_status = $hostGate.gate
    installer_safety_interlock_status = $interlock.status
    operator_acceptance_v4_status = $acceptance.status
    disabled_capabilities = @("real_install", "network_update", "manual_upload", "manual_github_release", "registry", "startup", "scheduled_task", "service", "powercfg", "PATH", "worker_execute", "queue_apply")
    known_limitations = @("sandbox-only promotion", "unsigned artifact", "no host installer", "no network update", "tag workflows may publish existing artifacts/images")
    next_recommended_goals = @("Goal 281 real installer design review", "signed artifact plan", "host installer explicit authorization model")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "installer-promotion-rc-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "installer-promotion-rc-report.md") @("# Installer Promotion RC Report", "", "- rc_version: $RcVersion", "- artifact_promotion_gate_status: $($report.artifact_promotion_gate_status)", "- release_artifact_manifest_status: $($report.release_artifact_manifest_status)", "- long_soak_status: $($report.long_soak_status)", "- update_channel_manifest_status: $($report.update_channel_manifest_status)", "- host_mutation_gate_status: $($report.host_mutation_gate_status)", "- operator_acceptance_v4_status: $($report.operator_acceptance_v4_status)", "- token_printed=false")
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.installer_promotion_rc_report.v1"; status = "ready"; rc_version = $RcVersion; token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; rc_version = $RcVersion; host_mutation_allowed = $false; network_update_allowed = $false; token_printed = $false } }
  "report" { New-RcReport }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
