[CmdletBinding()]
param(
  [switch]$SkipWhenUnavailable,
  [string]$ArtifactDir,
  [int]$ApiPort = 0,
  [int]$WebPort = 0
)

$ErrorActionPreference = "Stop"

function Wait-HttpOk([string]$Url, [string]$Name) {
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    try {
      $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
      if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
        return
      }
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }

  throw "$Name did not become ready at $Url."
}

function Start-HiddenPowerShell([string]$Command) {
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $Command)
    PassThru = $true
  }
  if ($IsWindows) {
    $startProcessParams.WindowStyle = "Hidden"
  }

  return Start-Process @startProcessParams
}

$playwrightInstalled = (Test-Path -LiteralPath "node_modules\playwright") -or (Test-Path -LiteralPath "node_modules\@playwright\test")

if (-not $playwrightInstalled) {
  $message = "Playwright is not installed. Browser visual QA optional runner skipped; see docs/ui/BROWSER_VISUAL_QA.md."
  if (-not $ArtifactDir) {
    $ArtifactDir = Join-Path (Get-Location) ".agent\tmp\browser-visual-qa"
  }
  New-Item -ItemType Directory -Path $ArtifactDir -Force | Out-Null
  @{
    schema_version = 1
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    skipped = $true
    reason = "playwright_unavailable"
    fixture_only = $true
    production_endpoint_used = $false
    expected_routes = @("#/overview", "#/pr-ci", "#/hermes", "#/notifications", "#/embed/compact")
  } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $ArtifactDir "manifest.json") -Encoding utf8
  if ($SkipWhenUnavailable) {
    Write-Warning $message
    exit 0
  }

  throw $message
}

if (-not (Test-Path -LiteralPath "apps/web/dist/index.html")) {
  throw "Web build output is missing. Run corepack pnpm --filter @skybridge-agent-hub/web build first."
}

$serverProcess = $null
$webProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-browser-qa-" + [Guid]::NewGuid().ToString("n"))

try {
  New-Item -ItemType Directory -Path $tempDir | Out-Null
  $dbFile = Join-Path $tempDir "skybridge-browser-qa.sqlite"

  if ($ApiPort -le 0) {
    $ApiPort = Get-Random -Minimum 18100 -Maximum 28100
  }
  if ($WebPort -le 0) {
    $WebPort = Get-Random -Minimum 28101 -Maximum 38100
  }

  $apiBase = "http://127.0.0.1:$ApiPort"
  $webBase = "http://127.0.0.1:$WebPort"

  if (-not $ArtifactDir) {
    $ArtifactDir = Join-Path (Get-Location) ".agent\tmp\browser-visual-qa"
  }
  New-Item -ItemType Directory -Path $ArtifactDir -Force | Out-Null

  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$ApiPort'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $serverProcess = Start-HiddenPowerShell $serverCommand
  Wait-HttpOk "$apiBase/v1/health" "SkyBridge API"

  & "$PSScriptRoot\seed-demo-events.ps1" -ApiBase $apiBase | Out-Null

  $webCommand = "`$env:VITE_SKYBRIDGE_API_BASE = '$apiBase'; corepack pnpm --filter @skybridge-agent-hub/web exec vite preview --host 127.0.0.1 --port $WebPort"
  $webProcess = Start-HiddenPowerShell $webCommand
  Wait-HttpOk $webBase "SkyBridge web preview"

  $env:SKYBRIDGE_VISUAL_QA_WEB_BASE = $webBase
  $env:SKYBRIDGE_VISUAL_QA_ARTIFACT_DIR = (Resolve-Path -LiteralPath $ArtifactDir).Path
  node .\scripts\browser-visual-qa.mjs

  Write-Host "Browser visual QA passed."
  Write-Host "Artifacts: $((Resolve-Path -LiteralPath $ArtifactDir).Path)"
} finally {
  if ($serverProcess) {
    try {
      $serverProcess.Kill($true)
    } catch {
      Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
  }
  if ($webProcess) {
    try {
      $webProcess.Kill($true)
    } catch {
      Stop-Process -Id $webProcess.Id -Force -ErrorAction SilentlyContinue
    }
  }
}
