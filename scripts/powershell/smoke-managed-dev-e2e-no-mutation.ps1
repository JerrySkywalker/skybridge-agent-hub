. "$PSScriptRoot\smoke-productization-common.ps1"

$before = (git -C $RepoRoot status --porcelain=v1 | Out-String).Trim()

$result = Invoke-JsonScript "skybridge-managed-dev-e2e-handoff.ps1" @(
  "-Command", "safe-summary"
)

$after = (git -C $RepoRoot status --porcelain=v1 | Out-String).Trim()
if ($before -ne $after) {
  throw "Read-only handoff audit changed git status."
}

Assert-False $result.token_printed "token_printed"
if (@($result.blockers).Count -ne 0) { throw "Safe summary reported blockers." }

Complete-Smoke "managed-dev-e2e-no-mutation"
