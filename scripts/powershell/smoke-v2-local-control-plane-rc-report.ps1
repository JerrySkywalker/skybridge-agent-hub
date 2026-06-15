$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-v2-local-control-plane-rc.ps1" @("-Command", "report")
if ($report.schema -ne "skybridge.v2_local_control_plane_rc_report.v1") { throw "v2 RC report schema mismatch." }
if ($report.rc_version -ne "v2.0.0-local-auth-control-plane-rc") { throw "v2 RC version mismatch." }
if ($report.threat_model_status -ne "docs_present") { throw "v2 threat model docs missing." }
if ($report.tag_safety_gate_status -ne "passed") { throw "Tag safety gate did not pass." }
if ($report.auth_session_store_status -ne "hash_only_fixture_safe") { throw "Session store status mismatch." }
if ($report.authenticated_rehearsal_status -ne "passed") { throw "Authenticated rehearsal status mismatch." }
if ($report.auth_soak_status -ne "passed") { throw "Auth soak status mismatch." }

Write-Host "[smoke-v2-local-control-plane-rc-report] ok"
