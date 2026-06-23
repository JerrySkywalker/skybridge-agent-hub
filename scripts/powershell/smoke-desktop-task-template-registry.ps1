[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$registrySource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\event-schema\src\task-template-registry.json")

foreach ($needle in @(
  "Bootstrap Alpha Task Templates",
  "BootstrapAlphaTaskTemplateRegistryPanel",
  "skybridge.task_template_registry.v1",
  "Available templates",
  "Template id",
  "Risk class",
  "Required capabilities",
  "Allowed paths",
  "Blocked paths",
  "Runner id",
  "Evidence schema",
  "execution_supported=false",
  "task_creation_supported=false; campaign_creation_supported=false; claim_supported=false",
  "codex_run_supported=false; matlab_run_supported=false; arbitrary_shell_enabled=false; token_printed=false",
  "Draft submit uses Chat-to-Task review",
  "Template execution unavailable",
  "Worker runner deferred to MG329"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop template registry panel missing text: $needle"
  }
}

foreach ($forbidden in @(
  "Run template",
  "Claim template",
  "Start worker loop",
  "Run Codex",
  "Run MATLAB",
  "arbitrary shell box"
)) {
  if ($desktopSource -match [regex]::Escape($forbidden)) {
    throw "Desktop template registry panel contains forbidden control text: $forbidden"
  }
}

foreach ($needle in @(
  "fixtureTaskTemplateRegistry",
  "fixtureTaskTemplates",
  "TaskTemplateRegistry",
  "TaskTemplate"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) {
    throw "Client fixture missing task template registry text: $needle"
  }
}

foreach ($needle in @(
  "software-docs-task.v1",
  "codex-analysis-report.v1",
  "safe-local-smoke.v1",
  "matlab-parameter-sweep.v1",
  "matlab-result-analysis.v1"
)) {
  if ($registrySource -notmatch [regex]::Escape($needle)) {
    throw "Registry fixture missing task template text: $needle"
  }
}

Assert-NoUnsafeText $registrySource
$registry = $registrySource | ConvertFrom-Json
if ([string]$registry.schema -ne "skybridge.task_template_registry.v1") { throw "Registry fixture schema mismatch." }
Assert-False $registry.execution_supported "registry execution_supported"
Assert-False $registry.task_creation_supported "registry task_creation_supported"
Assert-False $registry.campaign_creation_supported "registry campaign_creation_supported"
Assert-False $registry.claim_supported "registry claim_supported"
Assert-False $registry.codex_run_supported "registry codex_run_supported"
Assert-False $registry.matlab_run_supported "registry matlab_run_supported"
Assert-False $registry.arbitrary_shell_enabled "registry arbitrary_shell_enabled"
Assert-TokenPrintedFalse $registry

[pscustomobject]@{
  ok = $true
  smoke = "desktop-task-template-registry"
  panel_contract = "skybridge.task_template_registry.v1"
  template_count = @($registry.templates).Count
  execution_supported = $false
  task_creation_supported = $false
  campaign_creation_supported = $false
  claim_supported = $false
  codex_run_supported = $false
  matlab_run_supported = $false
  arbitrary_shell_enabled = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
