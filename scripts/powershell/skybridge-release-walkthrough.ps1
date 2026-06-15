[CmdletBinding()]
param(
  [ValidateSet("status", "walkthrough-preview", "acceptance-v4", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\operator-acceptance"

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding utf8
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

function StatusOf($Value, [string]$Field = "status") {
  if ($null -eq $Value) { return "not_reported" }
  $prop = $Value.PSObject.Properties[$Field]
  if ($prop) { return [string]$prop.Value }
  "not_reported"
}

function New-AcceptanceV4 {
  $releaseGuard = Invoke-JsonScript "skybridge-release-workflow-guard.ps1" @("-Command", "report")
  $promotion = Invoke-JsonScript "skybridge-installer-promotion.ps1" @("-Command", "promotion-gate")
  $artifact = Invoke-JsonScript "skybridge-release-candidate-artifact.ps1" @("-Command", "report")
  $soak = Invoke-JsonScript "skybridge-long-soak.ps1" @("-Command", "report", "-CiSmoke")
  $channel = Invoke-JsonScript "skybridge-channel-manifest.ps1" @("-Command", "report")
  $hostGate = Invoke-JsonScript "skybridge-host-mutation-gate.ps1" @("-Command", "gate")
  $interlock = Invoke-JsonScript "skybridge-installer-safety-interlock.ps1" @("-Command", "gate")
  $report = [pscustomobject]@{
    schema = "skybridge.operator_acceptance_v4_report.v1"
    status = $(if ($promotion.gate -eq "passed" -and $artifact.status -eq "passed" -and $soak.status -eq "passed") { "passed" } else { "preview" })
    release_workflow_guard = $(if ($releaseGuard.gate) { $releaseGuard.gate.gate } else { StatusOf $releaseGuard })
    installer_promotion_gate = $promotion.gate
    release_artifact_manifest = $artifact.status
    long_soak = $soak.status
    update_channel_manifest = $channel.status
    offline_update_rollback_preview = "preview"
    host_mutation_gate = $hostGate.gate
    installer_safety_interlock = $interlock.status
    web_desktop_panels = "read_only_release_candidate_surfaces"
    disabled_capabilities = @("real_install", "network_update", "manual_upload", "manual_github_release", "worker_execute", "queue_apply", "task_claim")
    known_limitations = @("sandbox only", "unsigned artifact", "manual GitHub Release disabled", "host mutation disabled")
    next_safe_action = "Open PR, wait for CI, merge, run post-merge smokes, then tag only if tag safety gate passes."
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "operator-acceptance-v4-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "operator-acceptance-v4-report.md") @("# Operator Acceptance v4 Report", "", "- status: $($report.status)", "- installer_promotion_gate: $($report.installer_promotion_gate)", "- release_artifact_manifest: $($report.release_artifact_manifest)", "- long_soak: $($report.long_soak)", "- host_mutation_gate: $($report.host_mutation_gate)", "- token_printed=false")
  $report
}

function New-Walkthrough {
  $acceptance = New-AcceptanceV4
  $report = [pscustomobject]@{
    schema = "skybridge.release_walkthrough_report.v1"
    status = "preview"
    release_workflow_guard = $acceptance.release_workflow_guard
    artifact_promotion_gate = $acceptance.installer_promotion_gate
    release_artifact_manifest = $acceptance.release_artifact_manifest
    host_mutation_gate = $acceptance.host_mutation_gate
    long_soak_status = $acceptance.long_soak
    update_channel_manifest = $acceptance.update_channel_manifest
    operator_acceptance_v4 = $acceptance.status
    next_safe_action = $acceptance.next_safe_action
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "release-walkthrough-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "release-walkthrough-report.md") @("# Release Walkthrough Report", "", "- status: $($report.status)", "- artifact_promotion_gate: $($report.artifact_promotion_gate)", "- operator_acceptance_v4: $($report.operator_acceptance_v4)", "- next_safe_action: $($report.next_safe_action)", "- token_printed=false")
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.release_walkthrough_report.v1"; status = "ready"; token_printed = $false } }
  "walkthrough-preview" { New-Walkthrough }
  "acceptance-v4" { New-AcceptanceV4 }
  "safe-summary" { [pscustomobject]@{ ok = $true; release_walkthrough_preview = $true; token_printed = $false } }
  "report" { New-Walkthrough }
}

if ($Json) { $Result | ConvertTo-Json -Depth 90 } else { $Result | Format-List | Out-String }
