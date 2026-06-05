[CmdletBinding()]
param(
  [switch]$SkipWhenUnavailable = $true
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$playwrightInstalled = (Test-Path -LiteralPath (Join-Path $repoRoot "node_modules\playwright")) -or (Test-Path -LiteralPath (Join-Path $repoRoot "node_modules\@playwright\test"))

if (-not $playwrightInstalled) {
  $artifactDir = Join-Path $repoRoot ".agent\tmp\queue-dashboard-visual-qa"
  New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
  @{
    schema_version = 1
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    skipped = $true
    reason = "playwright_unavailable"
    fixture_only = $true
    production_endpoint_used = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $artifactDir "manifest.json") -Encoding utf8
  if ($SkipWhenUnavailable) {
    [pscustomobject]@{
      ok = $true
      skipped = $true
      scenario = "queue-dashboard-visual-qa"
      artifact_dir = $artifactDir
      token_printed = $false
    } | ConvertTo-Json -Compress
    exit 0
  }
  throw "Playwright unavailable."
}

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "apps\web\dist\index.html"))) {
  corepack pnpm --filter @skybridge-agent-hub/web build
}

& "$PSScriptRoot\smoke-desktop-visual-qa.ps1" -SkipWhenUnavailable
& "$PSScriptRoot\smoke-browser-visual-qa.ps1" -SkipWhenUnavailable -ArtifactDir ".agent\tmp\queue-dashboard-web-visual-qa"

[pscustomobject]@{
  ok = $true
  skipped = $false
  scenario = "queue-dashboard-visual-qa"
  desktop_artifacts = ".agent\tmp\desktop-visual-qa"
  web_artifacts = ".agent\tmp\queue-dashboard-web-visual-qa"
  token_printed = $false
} | ConvertTo-Json -Compress
