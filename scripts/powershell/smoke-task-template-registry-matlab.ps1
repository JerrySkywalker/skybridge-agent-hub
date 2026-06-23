[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$registryRaw = & (Join-Path $PSScriptRoot "skybridge-task-template-registry.ps1") -Command sample-matlab -Json
$registryText = ($registryRaw | Out-String).Trim()
Assert-NoUnsafeText $registryText
$lookup = $registryText | ConvertFrom-Json

if ([string]$lookup.schema -ne "skybridge.task_template_lookup.v1") { throw "Unexpected MATLAB lookup schema." }
if (-not [bool]$lookup.ok) { throw "MATLAB template lookup failed." }
$template = $lookup.template
if ([string]$template.template_id -ne "matlab-parameter-sweep.v1") { throw "MATLAB template id mismatch." }
if ([string]$template.draft_type -ne "campaign") { throw "MATLAB template draft type mismatch." }
if ([string]$template.risk_class -ne "medium") { throw "MATLAB template risk class mismatch." }
if ([string]$template.runner_id -ne "matlab-parameter-sweep-runner.v1") { throw "MATLAB runner mismatch." }
foreach ($capability in @("windows", "powershell", "matlab")) {
  if (@($template.required_capabilities) -notcontains $capability) {
    throw "MATLAB template missing required capability: $capability"
  }
}
foreach ($capability in @("codex", "git", "gh")) {
  if (@($template.optional_capabilities) -notcontains $capability) {
    throw "MATLAB template missing optional capability: $capability"
  }
}
foreach ($path in @("experiments/matlab/**", "results/skybridge/**", "docs/experiments/**")) {
  if (@($template.allowed_paths) -notcontains $path) {
    throw "MATLAB template missing allowed path: $path"
  }
}
foreach ($path in @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings")) {
  if (@($template.blocked_paths) -notcontains $path) {
    throw "MATLAB template missing blocked path: $path"
  }
}
foreach ($evidence in @("skybridge.matlab_sweep_evidence.v1", "run_manifest", "parameter_matrix", "result_summary", "report_path", "audit_summary")) {
  if (@($template.evidence_schema) -notcontains $evidence) {
    throw "MATLAB template missing evidence schema item: $evidence"
  }
}
Assert-False $template.execution_supported "MATLAB execution_supported"
Assert-False $template.task_creation_supported "MATLAB task_creation_supported"
Assert-False $template.campaign_creation_supported "MATLAB campaign_creation_supported"
Assert-False $template.claim_supported "MATLAB claim_supported"
Assert-False $template.codex_run_supported "MATLAB codex_run_supported"
Assert-False $template.matlab_run_supported "MATLAB matlab_run_supported"
Assert-False $template.arbitrary_shell_enabled "MATLAB arbitrary_shell_enabled"
Assert-TokenPrintedFalse $template

$draftRaw = & (Join-Path $PSScriptRoot "skybridge-chat-to-task-draft.ps1") -Command sample-matlab -Json
$draftText = ($draftRaw | Out-String).Trim()
Assert-NoUnsafeText $draftText
$draft = $draftText | ConvertFrom-Json
if ([string]$draft.template_id -ne [string]$template.template_id) { throw "MATLAB draft template not registry-backed." }
if ([string]$draft.draft.runner_id -ne [string]$template.runner_id) { throw "MATLAB draft runner not registry-backed." }
if (@($draft.draft.evidence_schema)[0] -ne @($template.evidence_schema)[0]) { throw "MATLAB draft evidence schema not registry-backed." }
foreach ($path in @("results/skybridge/**", "docs/experiments/**")) {
  if (@($draft.draft.allowed_paths) -notcontains $path) {
    throw "MATLAB draft missing expected allowed path from registry: $path"
  }
}
Assert-False $draft.execution_started "MATLAB draft execution_started"
Assert-False $draft.matlab_run_called "MATLAB draft matlab_run_called"
Assert-False $draft.codex_run_called "MATLAB draft codex_run_called"
Assert-False $draft.arbitrary_shell_enabled "MATLAB draft arbitrary_shell_enabled"
Assert-TokenPrintedFalse $draft

[pscustomobject]@{
  ok = $true
  smoke = "task-template-registry-matlab"
  template_id = $template.template_id
  runner_id = $template.runner_id
  evidence_schema_id = @($template.evidence_schema)[0]
  chat_to_task_template_known = $true
  execution_supported = $false
  matlab_run_supported = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
