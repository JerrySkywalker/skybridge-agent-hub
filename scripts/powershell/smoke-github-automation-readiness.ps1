[CmdletBinding()]
param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\check-github-automation-readiness.ps1" -Json
if ($LASTEXITCODE -ne 0) {
  throw "check-github-automation-readiness.ps1 failed"
}

$parsed = ($output -join "`n") | ConvertFrom-Json
if ($parsed.modified_remote_settings -ne $false) {
  throw "readiness checker must not mutate remote settings"
}
if ($parsed.branch_protection_mutated -ne $false) {
  throw "readiness checker must not mutate branch protection"
}
if (-not $parsed.findings -or $parsed.findings.Count -lt 1) {
  throw "readiness checker returned no findings"
}
$allowed = @("ready", "warning", "blocker", "manual_setup_required")
foreach ($finding in @($parsed.findings)) {
  if ($finding.status -notin $allowed) {
    throw "unexpected readiness status: $($finding.status)"
  }
}

@{
  ok = $true
  dry_run = $true
  overall = $parsed.overall
  blocker_count = $parsed.blocker_count
  warning_count = $parsed.warning_count
  manual_setup_required_count = $parsed.manual_setup_required_count
  branch_protection_mutated = $parsed.branch_protection_mutated
  modified_remote_settings = $parsed.modified_remote_settings
} | ConvertTo-Json -Depth 8
