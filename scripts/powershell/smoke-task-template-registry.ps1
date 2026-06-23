[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

function Invoke-Registry {
  param(
    [string]$RegistryCommand,
    [string]$TemplateId = ""
  )
  $scriptPath = Join-Path $PSScriptRoot "skybridge-task-template-registry.ps1"
  $scriptArgs = @{
    Command = $RegistryCommand
    Json = $true
  }
  if (-not [string]::IsNullOrWhiteSpace($TemplateId)) {
    $scriptArgs.TemplateId = $TemplateId
  }
  $raw = & $scriptPath @scriptArgs
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Assert-TemplateSafety {
  param($Template)
  foreach ($field in @("template_id", "risk_class", "required_capabilities", "allowed_paths", "blocked_paths", "runner_id", "evidence_schema")) {
    if (-not ($Template.PSObject.Properties.Name -contains $field)) {
      throw "Template missing field $field"
    }
  }
  if (@($Template.required_capabilities).Count -eq 0) { throw "Template missing required capabilities." }
  if (@($Template.allowed_paths).Count -eq 0) { throw "Template missing allowed paths." }
  if (@($Template.blocked_paths).Count -eq 0) { throw "Template missing blocked paths." }
  if (@($Template.evidence_schema).Count -eq 0) { throw "Template missing evidence schema." }
  Assert-False $Template.execution_supported "$($Template.template_id) execution_supported"
  Assert-False $Template.task_creation_supported "$($Template.template_id) task_creation_supported"
  Assert-False $Template.campaign_creation_supported "$($Template.template_id) campaign_creation_supported"
  Assert-False $Template.claim_supported "$($Template.template_id) claim_supported"
  Assert-False $Template.codex_run_supported "$($Template.template_id) codex_run_supported"
  Assert-False $Template.matlab_run_supported "$($Template.template_id) matlab_run_supported"
  Assert-False $Template.arbitrary_shell_enabled "$($Template.template_id) arbitrary_shell_enabled"
  Assert-TokenPrintedFalse $Template
}

$status = Invoke-Registry -RegistryCommand "status"
if ([string]$status.schema -ne "skybridge.task_template_registry_status.v1") { throw "Unexpected registry status schema." }
Assert-False $status.execution_supported "status execution_supported"
Assert-False $status.task_creation_supported "status task_creation_supported"
Assert-False $status.campaign_creation_supported "status campaign_creation_supported"
Assert-False $status.claim_supported "status claim_supported"
Assert-False $status.codex_run_supported "status codex_run_supported"
Assert-False $status.matlab_run_supported "status matlab_run_supported"
Assert-False $status.arbitrary_shell_enabled "status arbitrary_shell_enabled"
Assert-TokenPrintedFalse $status

$list = Invoke-Registry -RegistryCommand "list"
if ([string]$list.schema -ne "skybridge.task_template_registry.v1") { throw "Unexpected registry list schema." }
$requiredIds = @(
  "software-docs-task.v1",
  "codex-analysis-report.v1",
  "safe-local-smoke.v1",
  "matlab-parameter-sweep.v1",
  "matlab-result-analysis.v1"
)
$ids = @($list.templates | ForEach-Object { [string]$_.template_id })
foreach ($id in $requiredIds) {
  if ($ids -notcontains $id) { throw "Missing required template: $id" }
}
foreach ($template in @($list.templates)) {
  Assert-TemplateSafety $template
}

$docs = Invoke-Registry -RegistryCommand "get" -TemplateId "software-docs-task.v1"
if ([string]$docs.schema -ne "skybridge.task_template_lookup.v1") { throw "Unexpected get schema." }
if ([string]$docs.template.template_id -ne "software-docs-task.v1") { throw "Docs template lookup mismatch." }
foreach ($path in @("docs/**", "README.md")) {
  if (@($docs.template.allowed_paths) -notcontains $path) { throw "Docs template missing allowed path: $path" }
}
foreach ($blocked in @(".env", "secrets/**", "deploy/**", ".git/**", "GitHub settings")) {
  if (@($docs.template.blocked_paths) -notcontains $blocked) { throw "Docs template missing blocked path: $blocked" }
}

$chatDocs = & (Join-Path $PSScriptRoot "skybridge-chat-to-task-draft.ps1") -Command sample-docs -Json
$chatDocsText = ($chatDocs | Out-String).Trim()
Assert-NoUnsafeText $chatDocsText
$chatDocsPreview = $chatDocsText | ConvertFrom-Json
if ($ids -notcontains [string]$chatDocsPreview.template_id) { throw "Chat-to-Task docs template is not registry-backed." }
if ([string]$chatDocsPreview.draft.runner_id -ne [string]$docs.template.runner_id) { throw "Chat-to-Task docs runner does not come from registry." }
if (@($chatDocsPreview.draft.evidence_schema)[0] -ne @($docs.template.evidence_schema)[0]) { throw "Chat-to-Task docs evidence schema does not come from registry." }

[pscustomobject]@{
  ok = $true
  smoke = "task-template-registry"
  schema = $list.schema
  template_count = @($list.templates).Count
  required_templates_present = $true
  chat_to_task_docs_template_known = $true
  execution_supported = $false
  task_creation_supported = $false
  campaign_creation_supported = $false
  claim_supported = $false
  codex_run_supported = $false
  matlab_run_supported = $false
  arbitrary_shell_enabled = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
