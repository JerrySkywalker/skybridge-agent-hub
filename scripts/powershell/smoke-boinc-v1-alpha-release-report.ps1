$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command v1-alpha-release-report -Json | Out-String).Trim()
if ($json -match 'token_printed"\s*:\s*true|raw_prompt|raw_stdout|raw_stderr|raw_worker_log|raw_codex_transcript|raw_ci_log|Authorization\s*[:=]\s*Bearer') { throw "unsafe release report output" }
$obj = $json | ConvertFrom-Json
if ($obj.alpha_id -ne "boinc-v1-alpha-215" -or $obj.two_workunit_alpha_completed -ne $true -or $obj.ready_for_goal_217 -ne $true) { throw "release report contract mismatch" }
if ($obj.apply_boundary.general_bounded_queue_apply_enabled -ne $false -or $obj.apply_boundary.no_next_execution_authorized -ne $true) { throw "release report apply boundary mismatch" }
foreach ($path in @(".agent/tmp/boinc-v1-alpha-215/v1-alpha-release-report.json", ".agent/tmp/boinc-v1-alpha-215/v1-alpha-release-report.md", "docs/dev/BOINC_V1_ALPHA_RELEASE_CANDIDATE.md")) {
  if (-not (Test-Path -LiteralPath (Join-Path ((Resolve-Path (Join-Path $PSScriptRoot "../..")).Path) $path) -PathType Leaf)) { throw "missing release report path: $path" }
}
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-release-report"; token_printed = $false } | ConvertTo-Json -Compress
