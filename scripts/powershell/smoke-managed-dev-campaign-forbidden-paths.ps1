. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-managed-dev-campaign.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
foreach ($path in @(".github/workflows/deploy.yml", "deploy/docker-compose.yml", "secrets/prod.env", "apps/desktop/dist/setup.exe")) {
  $pattern = [regex]::Escape($path)
  if ($source -match "changed_files\s*=\s*@\([^)]*$pattern") {
    throw "Forbidden path appears in a fixture changed_files assignment."
  }
}

$confirm = "I_UNDERSTAND_RUN_ONE_CAMPAIGN_DRIVEN_MANAGED_DEV_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-managed-dev-campaign.ps1" @(
  "-Command", "run-fixture-e2e",
  "-Fixture",
  "-Confirm", $confirm
)
if ($result.forbidden_path_check -ne "passed") { throw "Forbidden path check should pass for fixture." }
if ($result.max_changed_files_check -ne "passed") { throw "Max changed files check should pass." }
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-campaign-forbidden-paths"
