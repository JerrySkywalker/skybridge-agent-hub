[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$task = [pscustomobject]@{
  task_id = "smoke-docs-capability-normalization"
  task_type = "docs"
  title = "Document capability alignment"
  required_capabilities = @("docs")
  expected_files = @("docs/dev/CAPABILITY_ALIGNMENT.md")
  allowed_paths = @("docs/dev/CAPABILITY_ALIGNMENT.md")
}

$normalized = Normalize-SkyBridgeTaskCapabilities -Task $task
if (@($normalized.original_required_capabilities) -notcontains "docs") { throw "Expected original docs capability to be preserved." }
foreach ($capability in @("codex", "git", "gh")) {
  if (@($normalized.normalized_required_capabilities) -notcontains $capability) {
    throw "Expected docs normalization to include $capability."
  }
}
if (@($normalized.normalized_required_capabilities) -contains "docs") { throw "Expected legacy docs capability to be removed from worker matching." }
if ($normalized.capability_normalization_reason -ne "docs_expected_files_use_codex_git_gh") { throw "Unexpected normalization reason." }

$summary = [pscustomobject]@{
  ok = $true
  original_required_capabilities = @($normalized.original_required_capabilities)
  normalized_required_capabilities = @($normalized.normalized_required_capabilities)
  reason = $normalized.capability_normalization_reason
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
