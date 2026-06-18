[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$composePath = Join-Path $repoRoot "deploy\docker-compose.skybridge.yml"
$compose = Get-Content -Raw $composePath

foreach ($needle in @(
  "env_file:",
  'SKYBRIDGE_COMMIT_SHA: ${SKYBRIDGE_DEPLOY_COMMIT_SHA:-${SKYBRIDGE_COMMIT_SHA:-unknown}}',
  'SKYBRIDGE_IMAGE_TAG: ${SKYBRIDGE_DEPLOY_IMAGE_TAG:-${SKYBRIDGE_IMAGE_TAG:-local}}',
  'SKYBRIDGE_IMAGE_REF: ${SKYBRIDGE_DEPLOY_IMAGE_REF:-${SKYBRIDGE_IMAGE_REF:-${SKYBRIDGE_SERVER_IMAGE:-}}}'
)) {
  if ($compose -notmatch [regex]::Escape($needle)) { throw "Compose stale-env override contract missing: $needle" }
}

$dockerRendered = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
  $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-env-override-" + [Guid]::NewGuid().ToString("n"))
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  try {
    $envFile = Join-Path $tempDir "stale.env"
    @(
      "SKYBRIDGE_COMMIT_SHA=stale-local"
      "SKYBRIDGE_IMAGE_TAG=main"
      "SKYBRIDGE_IMAGE_REF=stale-ref"
    ) | Set-Content -LiteralPath $envFile -Encoding UTF8

    $oldEnv = @{
      SKYBRIDGE_ENV_FILE = $env:SKYBRIDGE_ENV_FILE
      SKYBRIDGE_DEPLOY_COMMIT_SHA = $env:SKYBRIDGE_DEPLOY_COMMIT_SHA
      SKYBRIDGE_DEPLOY_IMAGE_TAG = $env:SKYBRIDGE_DEPLOY_IMAGE_TAG
      SKYBRIDGE_DEPLOY_IMAGE_REF = $env:SKYBRIDGE_DEPLOY_IMAGE_REF
      SKYBRIDGE_SERVER_IMAGE = $env:SKYBRIDGE_SERVER_IMAGE
    }
    $env:SKYBRIDGE_ENV_FILE = $envFile
    $env:SKYBRIDGE_DEPLOY_COMMIT_SHA = "abc123"
    $env:SKYBRIDGE_DEPLOY_IMAGE_TAG = "sha-abc123"
    $env:SKYBRIDGE_DEPLOY_IMAGE_REF = "ghcr.io/example/skybridge-agent-hub-server:sha-abc123"
    $env:SKYBRIDGE_SERVER_IMAGE = "ghcr.io/example/skybridge-agent-hub-server:sha-abc123"

    $rendered = & docker compose -f $composePath config 2>$null
    if ($LASTEXITCODE -eq 0) {
      $renderedText = $rendered -join "`n"
      foreach ($needle in @(
        "SKYBRIDGE_COMMIT_SHA: abc123",
        "SKYBRIDGE_IMAGE_TAG: sha-abc123",
        "SKYBRIDGE_IMAGE_REF: ghcr.io/example/skybridge-agent-hub-server:sha-abc123"
      )) {
        if ($renderedText -notmatch [regex]::Escape($needle)) { throw "Rendered compose did not preserve immutable runtime metadata: $needle" }
      }
      if ($renderedText -match [regex]::Escape("SKYBRIDGE_IMAGE_TAG: main")) { throw "Rendered compose allowed stale env image tag to override deploy metadata." }
      $dockerRendered = $true
    }
  } finally {
    foreach ($key in $oldEnv.Keys) {
      if ($null -eq $oldEnv[$key]) { Remove-Item "Env:\$key" -ErrorAction SilentlyContinue } else { Set-Item "Env:\$key" $oldEnv[$key] }
    }
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$summary = [pscustomobject]@{
  ok = $true
  scenario = "deploy-version-env-override"
  stale_env_image_tag = "main"
  expected_image_tag = "sha-abc123"
  docker_rendered = $dockerRendered
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
