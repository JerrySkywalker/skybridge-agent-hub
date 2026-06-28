. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-actions-node-runtime-hygiene.ps1" @(
  "-Command", "audit"
)

if ($result.schema -ne "skybridge.actions_node_runtime_hygiene.v1") { throw "Unexpected actions hygiene schema." }
$dockerActions = @($result.actions_detected | Where-Object { [string]$_.action -like "docker/*" })
if ($dockerActions.Count -lt 1) { throw "Expected Docker actions to be detected." }

$currentNode20 = @($dockerActions | Where-Object { [string]$_.known_runtime -eq "node20" })
if ($currentNode20.Count -ne 0) { throw "Current Docker actions still include node20 runtime sources." }

foreach ($expected in @(
  "docker/metadata-action@v6",
  "docker/login-action@v4",
  "docker/setup-buildx-action@v4",
  "docker/build-push-action@v7"
)) {
  $found = @($result.actions_detected | Where-Object { [string]$_.uses -eq $expected })
  if ($found.Count -lt 1) { throw "Missing expected Node 24 action candidate: $expected" }
}

Assert-False $result.warning_suppressed "warning_suppressed"
Assert-False $result.ci_threshold_changed "ci_threshold_changed"
Assert-False $result.permissions_expanded "permissions_expanded"
Assert-False $result.triggers_changed "triggers_changed"
Assert-False $result.secrets_changed "secrets_changed"
Assert-TokenPrintedFalse $result

Complete-Smoke "actions-node-runtime-hygiene-audit"
