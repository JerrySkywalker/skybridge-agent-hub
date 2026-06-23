[CmdletBinding()]
param(
  [ValidateSet("status", "list", "get", "validate", "sample-matlab", "sample-docs", "safe-summary")]
  [string]$Command = "status",
  [string]$TemplateId = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\task-template-registry-data.ps1"

function New-RegistrySafety {
  [ordered]@{
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    task_created = $false
    campaign_created = $false
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    token_printed = $false
  }
}

function Select-TemplateSummary {
  param([Parameter(Mandatory = $true)]$Template)
  [pscustomobject]([ordered]@{
    schema = $Template.schema
    template_id = $Template.template_id
    version = $Template.version
    title = $Template.title
    description = $Template.description
    category = $Template.category
    draft_type = $Template.draft_type
    risk_class = $Template.risk_class
    required_capabilities = @($Template.required_capabilities)
    optional_capabilities = @($Template.optional_capabilities)
    input_schema_summary = @($Template.input_schema_summary)
    allowed_paths = @($Template.allowed_paths)
    blocked_paths = @($Template.blocked_paths)
    validation_rules = @($Template.validation_rules)
    runner_id = $Template.runner_id
    evidence_schema = @($Template.evidence_schema)
    output_paths = @($Template.output_paths)
    default_project_id_hint = $Template.default_project_id_hint
    execution_supported = $false
    draft_only = $true
    task_creation_supported = $false
    campaign_creation_supported = $false
    claim_supported = $false
    codex_run_supported = $false
    matlab_run_supported = $false
    arbitrary_shell_enabled = $false
    token_printed = $false
  })
}

function New-RegistryList {
  $registry = Get-TaskTemplateRegistry
  $safety = New-RegistrySafety
  [pscustomobject]([ordered]@{
    schema = $registry.schema
    ok = $true
    registry_id = $registry.registry_id
    version = $registry.version
    title = $registry.title
    description = $registry.description
    template_count = @($registry.templates).Count
    templates = @($registry.templates | ForEach-Object { Select-TemplateSummary $_ })
    evidence_schemas = @($registry.evidence_schemas)
    execution_supported = $false
    draft_only = $true
    task_creation_supported = $false
    campaign_creation_supported = $false
    claim_supported = $false
    codex_run_supported = $false
    matlab_run_supported = $false
  } + $safety)
}

function New-RegistryStatus {
  $registry = Get-TaskTemplateRegistry
  $validation = Test-TaskTemplateRegistry
  $safety = New-RegistrySafety
  [pscustomobject]([ordered]@{
    schema = "skybridge.task_template_registry_status.v1"
    ok = [bool]$validation.ok
    registry_schema = $registry.schema
    registry_id = $registry.registry_id
    version = $registry.version
    template_count = @($registry.templates).Count
    template_ids = @($registry.templates | ForEach-Object { [string]$_.template_id })
    validation_errors = @($validation.errors)
    execution_supported = $false
    draft_only = $true
    task_creation_supported = $false
    campaign_creation_supported = $false
    claim_supported = $false
    codex_run_supported = $false
    matlab_run_supported = $false
  } + $safety)
}

function New-RegistryGet {
  param([Parameter(Mandatory = $true)][string]$Id)
  $template = Get-TaskTemplate -TemplateId $Id
  $safety = New-RegistrySafety
  if (-not $template) {
    return [pscustomobject]([ordered]@{
      schema = "skybridge.task_template_lookup.v1"
      ok = $false
      status = "not_found"
      template_id = $Id
      blockers = @("unknown_template_id")
      execution_supported = $false
      task_creation_supported = $false
      campaign_creation_supported = $false
      claim_supported = $false
      codex_run_supported = $false
      matlab_run_supported = $false
    } + $safety)
  }
  [pscustomobject]([ordered]@{
    schema = "skybridge.task_template_lookup.v1"
    ok = $true
    status = "found"
    template = (Select-TemplateSummary $template)
    blockers = @()
    execution_supported = $false
    task_creation_supported = $false
    campaign_creation_supported = $false
    claim_supported = $false
    codex_run_supported = $false
    matlab_run_supported = $false
  } + $safety)
}

function New-RegistrySafeSummary {
  $registry = Get-TaskTemplateRegistry
  $safety = New-RegistrySafety
  [pscustomobject]([ordered]@{
    schema = "skybridge.task_template_registry_safe_summary.v1"
    ok = $true
    registry_id = $registry.registry_id
    version = $registry.version
    template_count = @($registry.templates).Count
    templates = @($registry.templates | ForEach-Object {
      [pscustomobject]@{
        template_id = $_.template_id
        category = $_.category
        draft_type = $_.draft_type
        risk_class = $_.risk_class
        runner_id = $_.runner_id
        evidence_schema = @($_.evidence_schema)
        execution_supported = $false
        task_creation_supported = $false
        campaign_creation_supported = $false
        claim_supported = $false
        token_printed = $false
      }
    })
    execution_supported = $false
    draft_only = $true
    task_creation_supported = $false
    campaign_creation_supported = $false
    claim_supported = $false
    codex_run_supported = $false
    matlab_run_supported = $false
  } + $safety)
}

switch ($Command) {
  "status" {
    $result = New-RegistryStatus
  }
  "list" {
    $result = New-RegistryList
  }
  "get" {
    $id = if ([string]::IsNullOrWhiteSpace($TemplateId)) { "software-docs-task.v1" } else { $TemplateId }
    $result = New-RegistryGet -Id $id
  }
  "validate" {
    $result = Test-TaskTemplateRegistry
  }
  "sample-matlab" {
    $result = New-RegistryGet -Id "matlab-parameter-sweep.v1"
  }
  "sample-docs" {
    $result = New-RegistryGet -Id "software-docs-task.v1"
  }
  "safe-summary" {
    $result = New-RegistrySafeSummary
  }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 16
} else {
  $result | Format-List
}

if ($result.PSObject.Properties.Name -contains "ok" -and $result.ok -ne $true) {
  exit 1
}
