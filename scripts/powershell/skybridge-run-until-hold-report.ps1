[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [int]$TimeoutSeconds = 30,
  [string]$FixtureBoundedRunFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Get-BoolProp {
  param($Object, [string]$Name, [bool]$Default = $false)
  $value = Get-Prop -Object $Object -Name $Name -Default $Default
  if ($null -eq $value) { return $Default }
  return [bool]$value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Invoke-ChildJson {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
  $text = (($output | Out-String).Trim())
  if ($LASTEXITCODE -ne 0) { throw "Command failed: pwsh $($Arguments -join ' ')" }
  $text | ConvertFrom-Json
}

if ($FixtureBoundedRunFile) {
  $bounded = Read-JsonFile -Path $FixtureBoundedRunFile
} else {
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-run-until-hold-bounded.ps1"),
    "-ProjectId", $ProjectId,
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-Preview",
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  $bounded = Invoke-ChildJson -Arguments $args
}

$oldResidue = Get-Prop -Object $bounded -Name "old_residue_exclusion"
$projectControl = Get-Prop -Object $bounded -Name "project_control"
$forbidden = Get-Prop -Object $bounded -Name "forbidden_actions"
$evidence = Get-Prop -Object $bounded -Name "evidence_summary"

$unsafeSelectionProof = [pscustomobject]@{
  no_old_residue_eligible = Get-BoolProp -Object $oldResidue -Name "no_old_residue_eligible" -Default $true
  no_old_task_claimed = Get-BoolProp -Object $oldResidue -Name "no_old_task_claimed" -Default $true
  no_old_task_requeued = Get-BoolProp -Object $oldResidue -Name "no_old_task_requeued" -Default $true
  old_task_claimed = Get-BoolProp -Object $forbidden -Name "old_task_claimed"
  old_task_requeued = Get-BoolProp -Object $forbidden -Name "old_task_requeued"
  unsafe_candidates_selected = $false
  token_printed = $false
}

$recommended = if (-not [bool]$unsafeSelectionProof.no_old_residue_eligible -or [bool]$unsafeSelectionProof.old_task_claimed -or [bool]$unsafeSelectionProof.old_task_requeued) {
  "FAILED_CLOSED: stop and inspect unsafe old-residue selection flags."
} elseif (-not (Get-BoolProp -Object $evidence -Name "evidence_present" -Default $true)) {
  "Hold for operator review; do not retry until missing evidence is repaired."
} elseif ([string](Get-Prop -Object $bounded -Name "stop_reason" -Default "") -in @("completed_max_tasks", "no_safe_candidate")) {
  "Bounded loop stopped safely; keep project_control paused and review evidence."
} else {
  "Hold for operator review; do not run another bounded apply until reviewed."
}

$report = [pscustomobject]@{
  schema = "skybridge.run_until_hold_report.v1"
  ok = (-not (Get-BoolProp -Object $projectControl -Name "project_control_unpaused") -and -not (Get-BoolProp -Object $forbidden -Name "recursive_run_until_hold") -and -not (Get-BoolProp -Object $bounded -Name "token_printed"))
  latest_bounded_run_status = [string](Get-Prop -Object $bounded -Name "stop_reason" -Default "not_reported")
  executed_tasks = @((Get-Prop -Object $bounded -Name "executed_tasks" -Default @()) | ForEach-Object {
    [pscustomobject]@{
      task_id = [string](Get-Prop -Object $_ -Name "task_id" -Default "")
      terminal_state = [string](Get-Prop -Object $_ -Name "terminal_state" -Default "")
      evidence_written = Get-BoolProp -Object $_ -Name "evidence_written"
      token_printed = $false
    }
  })
  stop_reason = [string](Get-Prop -Object $bounded -Name "stop_reason" -Default "not_reported")
  hold_reason = Get-Prop -Object $bounded -Name "hold_reason"
  evidence_summary = $evidence
  unsafe_selection_proof = $unsafeSelectionProof
  project_control_stayed_paused = (-not (Get-BoolProp -Object $projectControl -Name "project_control_unpaused"))
  run_until_hold_stayed_bounded = (-not (Get-BoolProp -Object $forbidden -Name "daemon_implemented") -and -not (Get-BoolProp -Object $forbidden -Name "recursive_run_until_hold"))
  recommended_next_safe_action = $recommended
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20
} else {
  "Schema:       $($report.schema)"
  "OK:           $($report.ok)"
  "StopReason:   $($report.stop_reason)"
  "HoldReason:   $(if ($report.hold_reason) { $report.hold_reason } else { 'none' })"
  "Executed:     $(@($report.executed_tasks).Count)"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
