. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$gate = Invoke-ManagedModeRunJson "next-run-gate" -Extra @(
  "-ManagedModeRunId", "managed-mode-run-211",
  "-SequenceNumber", "4",
  "-TargetPath", "docs/managed-mode-v0-repeatability-check.md",
  "-StateDir", ".agent/tmp/managed-mode-run-211"
)
if ($gate.completed_run_ids -notcontains "managed-mode-pilot-208" -or $gate.completed_run_ids -notcontains "managed-mode-run-209" -or $gate.completed_run_ids -notcontains "managed-mode-run-210") { throw "Expected completed 208/209/210 registry." }
if ($gate.general_bounded_queue_apply_enabled -ne $false -or $gate.max_workunits -ne 1) { throw "Expected one-at-a-time bounded policy." }
$resource = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1") -Command run-allowance -RunId managed-mode-run-211 -Json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "Resource policy run allowance failed." }
if ($resource.schema -ne "skybridge.local_run_allowance.v1") { throw "Unexpected resource allowance schema." }
if ($resource.resource_gate_required -ne $true -or $resource.explicit_authorization_required -ne $true) { throw "Expected resource gate and explicit authorization requirement." }
if ($resource.token_printed -ne $false) { throw "Expected token_printed=false." }
Write-ManagedModeRunSmokeResult "managed-mode-run-211-gate-resource-required"
