$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$passing = Invoke-OperatorTuiMg371b0CapabilityStaging -Scenario "capability-staging" -Reset
Assert-True $passing.allowlist.docs_only_allowlist_passed "passing docs_only_allowlist_passed"
foreach ($file in @($passing.allowlist.changed_files | ForEach-Object { [string]$_ })) {
  if ($file -notlike "docs/*") { throw "Allowed MG371B changed file is not docs-only: $file" }
}

$blocked = Invoke-OperatorTuiMg371b0CapabilityStaging -Scenario "allowlist-invalid" -Reset
Assert-False $blocked.allowlist.docs_only_allowlist_passed "blocked docs_only_allowlist_passed"
$blockedFiles = @($blocked.allowlist.blocked_files | ForEach-Object { [string]$_ })
if ($blockedFiles -notcontains "apps/operator-tui/src/main.rs") {
  throw "Expected app code to be blocked by MG371B0 allowlist."
}
Assert-False $blocked.provider.fake_provider_executed "blocked provider fake_provider_executed"
Assert-TokenPrintedFalse $blocked.report

Complete-Smoke "operator-tui-mg371b0-allowlist-enforced"
