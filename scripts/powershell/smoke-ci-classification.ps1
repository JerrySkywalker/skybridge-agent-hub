$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-ci-classifier.ps1")

$cases = @(
  @{ Name = "green"; Text = "All checks passed"; State = "success"; Expected = "ci_green" },
  @{ Name = "checkout403"; Text = "actions/checkout failed. error: RPC failed; HTTP 403 curl 22 The requested URL returned error: 403"; State = "failure"; Expected = "ci_blocked_checkout_403" },
  @{ Name = "suspended"; Text = "remote: Your account is suspended. Please visit https://support.github.com"; State = "failure"; Expected = "ci_blocked_account_suspended_message" },
  @{ Name = "download"; Text = "Failed to download archive https://codeload.github.com/pnpm/action-setup"; State = "failure"; Expected = "ci_transient_checkout_or_fetch_failure" },
  @{ Name = "testfail"; Text = "vitest failed with assertion error"; State = "failure"; Expected = "ci_failed_real" },
  @{ Name = "pending"; Text = ""; State = "pending"; Expected = "ci_pending" }
)

$results = foreach ($case in $cases) {
  $actual = Get-SkyBridgeCiClassification -LogText $case.Text -CheckState $case.State
  if ($actual.classification -ne $case.Expected) {
    throw "Expected $($case.Name) to classify as $($case.Expected), got $($actual.classification)."
  }
  [pscustomobject]@{ name = $case.Name; classification = $actual.classification }
}

[pscustomobject]@{
  Cases = @($results).Count
  Classifications = @($results)
  RealGitHubApiCalled = $false
} | Format-List
