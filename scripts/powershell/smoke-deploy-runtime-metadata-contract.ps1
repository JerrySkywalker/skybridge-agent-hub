[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$compose = Get-Content -Raw (Join-Path $repoRoot "deploy\docker-compose.skybridge.yml")
$script = Get-Content -Raw (Join-Path $repoRoot "scripts\deploy\deploy-skybridge-server.sh")

foreach ($needle in @(
  'SKYBRIDGE_COMMIT_SHA: ${SKYBRIDGE_DEPLOY_COMMIT_SHA:-${SKYBRIDGE_COMMIT_SHA:-unknown}}',
  'SKYBRIDGE_IMAGE_TAG: ${SKYBRIDGE_DEPLOY_IMAGE_TAG:-${SKYBRIDGE_IMAGE_TAG:-local}}',
  'SKYBRIDGE_IMAGE_REF: ${SKYBRIDGE_DEPLOY_IMAGE_REF:-${SKYBRIDGE_IMAGE_REF:-${SKYBRIDGE_SERVER_IMAGE:-}}}',
  'skybridge-agent-hub-server:${SKYBRIDGE_DEPLOY_IMAGE_TAG:-${SKYBRIDGE_IMAGE_TAG:-latest}}'
)) {
  if ($compose -notmatch [regex]::Escape($needle)) { throw "Compose runtime metadata contract missing: $needle" }
}

foreach ($needle in @(
  'export SKYBRIDGE_SERVER_IMAGE="$IMAGE_REF"',
  'export SKYBRIDGE_DEPLOY_IMAGE_REF="$IMAGE_REF"',
  'export SKYBRIDGE_DEPLOY_COMMIT_SHA="$COMMIT_SHA"',
  'export SKYBRIDGE_DEPLOY_IMAGE_TAG="$EXPECTED_TAG"',
  '"runtime_metadata": {'
)) {
  if ($script -notmatch [regex]::Escape($needle)) { throw "Deploy script runtime metadata contract missing: $needle" }
}

if ($script -match [regex]::Escape('export SKYBRIDGE_IMAGE_TAG="$EXPECTED_TAG"')) {
  throw "Deploy script must use deploy-only interpolation variables instead of exporting SKYBRIDGE_IMAGE_TAG directly."
}

$summary = [pscustomobject]@{
  ok = $true
  scenario = "deploy-runtime-metadata-contract"
  deploy_scope = "skybridge-server-only"
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
