. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$preview = Invoke-ManagedModeRunJson "run-replacement-preview"
if ($preview.no_mutation -ne $true) { throw "Replacement preview must not mutate." }
if ($preview.prompt_contract.target_path -ne "docs/managed-mode-repeatability-orientation.md") { throw "Unexpected prompt target." }
if ($preview.prompt_contract.git_or_gh_allowed -ne $false) { throw "Prompt contract should forbid git/gh." }
Assert-ManagedModeRunSafeJson $preview
Write-ManagedModeRunSmokeResult "managed-mode-run-replacement-preview-no-mutation"
