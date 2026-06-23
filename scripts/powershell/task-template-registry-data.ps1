$ErrorActionPreference = "Stop"

function Get-TaskTemplateRegistryPath {
  $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
  Join-Path $repoRoot "packages/event-schema/src/task-template-registry.json"
}

function Get-TaskTemplateRegistry {
  $path = Get-TaskTemplateRegistryPath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Task template registry file is missing."
  }
  Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Get-TaskTemplate {
  param([Parameter(Mandatory = $true)][string]$TemplateId)
  $registry = Get-TaskTemplateRegistry
  @($registry.templates) | Where-Object { [string]$_.template_id -eq $TemplateId } | Select-Object -First 1
}

function Get-TaskTemplateValidationSummary {
  param([Parameter(Mandatory = $true)]$Template)
  @($Template.validation_rules) | ForEach-Object { [string]$_.summary }
}

function Test-TaskTemplateRegistry {
  $registry = Get-TaskTemplateRegistry
  $errors = @()

  if ([string]$registry.schema -ne "skybridge.task_template_registry.v1") {
    $errors += "registry_schema_mismatch"
  }
  foreach ($flag in @(
    "execution_supported",
    "task_creation_supported",
    "campaign_creation_supported",
    "claim_supported",
    "codex_run_supported",
    "matlab_run_supported",
    "arbitrary_shell_enabled",
    "token_printed"
  )) {
    if ($registry.$flag -ne $false) {
      $errors += "registry_$($flag)_not_false"
    }
  }
  if ($registry.draft_only -ne $true) {
    $errors += "registry_draft_only_not_true"
  }

  $requiredIds = @(
    "software-docs-task.v1",
    "codex-analysis-report.v1",
    "safe-local-smoke.v1",
    "matlab-parameter-sweep.v1",
    "matlab-result-analysis.v1"
  )
  $ids = @($registry.templates | ForEach-Object { [string]$_.template_id })
  foreach ($id in $requiredIds) {
    if ($ids -notcontains $id) {
      $errors += "missing_template:$id"
    }
  }
  $duplicates = @($ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  foreach ($duplicate in $duplicates) {
    $errors += "duplicate_template:$duplicate"
  }

  foreach ($template in @($registry.templates)) {
    $templateId = [string]$template.template_id
    foreach ($field in @(
      "template_id",
      "risk_class",
      "required_capabilities",
      "allowed_paths",
      "blocked_paths",
      "runner_id",
      "evidence_schema"
    )) {
      if (-not ($template.PSObject.Properties.Name -contains $field)) {
        $errors += "template_${templateId}_missing_$field"
      }
    }
    if (@($template.required_capabilities).Count -eq 0) {
      $errors += "template_${templateId}_missing_required_capabilities"
    }
    if (@($template.allowed_paths).Count -eq 0) {
      $errors += "template_${templateId}_missing_allowed_paths"
    }
    if (@($template.blocked_paths).Count -eq 0) {
      $errors += "template_${templateId}_missing_blocked_paths"
    }
    if (@($template.validation_rules).Count -eq 0) {
      $errors += "template_${templateId}_missing_validation_rules"
    }
    if (@($template.evidence_schema).Count -eq 0) {
      $errors += "template_${templateId}_missing_evidence_schema"
    }
    foreach ($flag in @(
      "execution_supported",
      "task_creation_supported",
      "campaign_creation_supported",
      "claim_supported",
      "codex_run_supported",
      "matlab_run_supported",
      "arbitrary_shell_enabled",
      "token_printed"
    )) {
      if ($template.$flag -ne $false) {
        $errors += "template_${templateId}_$($flag)_not_false"
      }
    }
    if ($template.draft_only -ne $true) {
      $errors += "template_${templateId}_draft_only_not_true"
    }
  }

  [pscustomobject]@{
    ok = ($errors.Count -eq 0)
    schema = "skybridge.task_template_registry_validation.v1"
    template_count = @($registry.templates).Count
    required_template_ids = $requiredIds
    errors = $errors
    execution_supported = $false
    task_creation_supported = $false
    campaign_creation_supported = $false
    claim_supported = $false
    codex_run_supported = $false
    matlab_run_supported = $false
    arbitrary_shell_enabled = $false
    token_printed = $false
  }
}
