[CmdletBinding()]
param(
  [switch]$SkipWhenUnavailable
)

$ErrorActionPreference = "Stop"

$playwrightCandidates = @(
  "node_modules\.bin\playwright.cmd",
  "node_modules\.bin\playwright"
)

$playwright = $playwrightCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $playwright) {
  $message = "Playwright is not installed. Browser visual QA is scaffolded but deferred; see docs/ui/BROWSER_VISUAL_QA.md."
  if ($SkipWhenUnavailable) {
    Write-Warning $message
    exit 0
  }

  throw $message
}

if (-not (Test-Path -LiteralPath "apps/web/dist/index.html")) {
  throw "Web build output is missing. Run corepack pnpm --filter @skybridge-agent-hub/web build first."
}

Write-Host "Browser visual QA scaffold is ready."
Write-Host "Next implementation step: add a Playwright spec that starts fixture-backed server/web processes, captures desktop/mobile console and compact embed screenshots, and uploads only fixture artifacts."
