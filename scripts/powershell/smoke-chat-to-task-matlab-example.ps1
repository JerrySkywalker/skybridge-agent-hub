[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$inputText = "帮我用 MATLAB 跑第四章参数扫描实验，eta=2..10，h=500/700km，P=6/8/10，输出 summary 和报告。"
$raw = & (Join-Path $PSScriptRoot "skybridge-chat-to-task-draft.ps1") -Command draft -InputText $inputText -ProjectId "skybridge-agent-hub" -Json
$text = ($raw | Out-String).Trim()
Assert-NoUnsafeText $text
$preview = $text | ConvertFrom-Json

if ([string]$preview.schema -ne "skybridge.task_draft_preview.v1") { throw "Unexpected preview schema." }
if ([string]$preview.status -ne "preview") { throw "MATLAB sample should be a preview." }
if ([string]$preview.draft_type -ne "campaign") { throw "MATLAB sample should produce a campaign draft." }
if ([string]$preview.template_id -ne "matlab-parameter-sweep.v1") { throw "MATLAB template mismatch." }
if ([string]$preview.draft.schema -ne "skybridge.campaign_draft.v1") { throw "MATLAB draft schema mismatch." }
if ([string]$preview.draft.runner_id -ne "matlab-parameter-sweep-runner.v1") { throw "MATLAB runner mismatch." }

foreach ($capability in @("windows", "powershell", "matlab", "codex")) {
  if (@($preview.draft.required_capabilities) -notcontains $capability) {
    throw "MATLAB draft missing capability: $capability"
  }
}
foreach ($path in @("results/skybridge/**", "docs/experiments/**")) {
  if (@($preview.draft.allowed_paths) -notcontains $path) {
    throw "MATLAB draft missing allowed path: $path"
  }
}
foreach ($path in @(".env", "secrets/**", "deploy/**", ".git/**")) {
  if (@($preview.draft.blocked_paths) -notcontains $path) {
    throw "MATLAB draft missing blocked path: $path"
  }
}
foreach ($evidence in @("run_manifest", "parameter_matrix", "result_summary", "report_path", "audit_summary")) {
  if (@($preview.draft.evidence_schema) -notcontains $evidence) {
    throw "MATLAB draft missing evidence field: $evidence"
  }
}
if (@($preview.draft.inputs.eta_range)[0] -ne 2 -or @($preview.draft.inputs.eta_range)[1] -ne 10) { throw "eta range mismatch." }
if (@($preview.draft.inputs.h_km) -notcontains 500 -or @($preview.draft.inputs.h_km) -notcontains 700) { throw "h km values mismatch." }
foreach ($p in @(6, 8, 10)) {
  if (@($preview.draft.inputs.p_values) -notcontains $p) { throw "P values mismatch." }
}
if (@($preview.draft.inputs.outputs) -notcontains "report") { throw "Report output missing." }

Assert-False $preview.raw_prompt_persisted "raw_prompt_persisted"
Assert-False $preview.raw_response_persisted "raw_response_persisted"
Assert-False $preview.task_created "task_created"
Assert-False $preview.campaign_created "campaign_created"
Assert-False $preview.claim_created "claim_created"
Assert-False $preview.execution_started "execution_started"
Assert-False $preview.codex_run_called "codex_run_called"
Assert-False $preview.matlab_run_called "matlab_run_called"
Assert-False $preview.arbitrary_shell_enabled "arbitrary_shell_enabled"
Assert-TokenPrintedFalse $preview

[pscustomobject]@{
  ok = $true
  smoke = "chat-to-task-matlab-example"
  draft_type = $preview.draft_type
  template_id = $preview.template_id
  runner_id = $preview.draft.runner_id
  execution_started = $false
  matlab_run_called = $false
  codex_run_called = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
