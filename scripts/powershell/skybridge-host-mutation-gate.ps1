[CmdletBinding()]
param(
  [ValidateSet("status", "gate", "explain", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\release-candidate"

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $Path -Encoding utf8
}

function New-HostMutationGate {
  [pscustomobject]@{
    schema = "skybridge.host_mutation_gate.v1"
    permission_schema = "skybridge.host_mutation_permission.v1"
    blocker_schema = "skybridge.host_mutation_blocker.v1"
    gate = "disabled"
    host_mutation_allowed = $false
    permissions = [pscustomobject]@{
      registry_write_allowed = $false
      startup_write_allowed = $false
      scheduled_task_allowed = $false
      service_install_allowed = $false
      path_mutation_allowed = $false
      powercfg_allowed = $false
      install_to_program_files_allowed = $false
      desktop_shortcut_allowed = $false
      start_menu_shortcut_allowed = $false
      token_printed = $false
    }
    blockers = @(
      [pscustomobject]@{ schema = "skybridge.host_mutation_blocker.v1"; blocker = "future_goal_required"; token_printed = $false },
      [pscustomobject]@{ schema = "skybridge.host_mutation_blocker.v1"; blocker = "sandbox_only_current_goal"; token_printed = $false }
    )
    explanation = "Host mutation is disabled by default. Current commands only emit preview metadata under .agent/tmp."
    token_printed = $false
  }
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.host_mutation_gate.v1"; status = "ready"; host_mutation_allowed = $false; token_printed = $false } }
  "gate" { $r = New-HostMutationGate; Write-SafeJson (Join-Path $ReportDir "host-mutation-gate.json") $r; $r }
  "explain" { New-HostMutationGate }
  "safe-summary" { [pscustomobject]@{ ok = $true; gate = "disabled"; host_mutation_allowed = $false; token_printed = $false } }
  "report" { $r = New-HostMutationGate; Write-SafeJson (Join-Path $ReportDir "host-mutation-gate.json") $r; $r }
}

if ($Json) { $Result | ConvertTo-Json -Depth 70 } else { $Result | Format-List | Out-String }
