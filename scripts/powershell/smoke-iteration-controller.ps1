[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$tempRoot = Join-Path ".\.agent\tmp" ("iteration-smoke-" + [Guid]::NewGuid().ToString("N"))
$goalFile = Join-Path $tempRoot "001-smoke-goal.md"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
Set-Content -LiteralPath $goalFile -Encoding UTF8 -Value @"
# Smoke Goal

Dry-run only. Do not edit repository files.
"@

try {
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\skybridge-iterate.ps1" `
    -ConfigFile ".\config\iteration-controller.example.json" `
    -GoalFile $goalFile `
    -DryRun `
    -One `
    -NoAutoMerge `
    -SkyBridgeApiBase "http://127.0.0.1:1"

  if ($LASTEXITCODE -ne 0) {
    throw "skybridge-iterate.ps1 dry-run failed"
  }

  $jsonStartIndex = [Array]::FindIndex([string[]]$output, [Predicate[string]]{ param($line) $line -match "^\s*\{" })
  if ($jsonStartIndex -lt 0) {
    throw "dry-run output did not include JSON"
  }

  $parsed = (($output | Select-Object -Skip $jsonStartIndex) -join "`n") | ConvertFrom-Json
  if ($parsed.state -ne "dry_run") {
    throw "unexpected dry-run state: $($parsed.state)"
  }
  if ($parsed.auto_merge -eq $true) {
    throw "auto-merge must not be enabled by default"
  }
  if ($parsed.codex_command -notmatch "codex exec") {
    throw "codex command shape missing"
  }

  $metadataPath = Join-Path $parsed.run_dir "metadata.json"
  if (-not (Test-Path -LiteralPath $metadataPath)) {
    throw "metadata file missing: $metadataPath"
  }
  $metadataText = Get-Content -LiteralPath $metadataPath -Raw
  if ($metadataText -match "token|secret|password|cookie") {
    throw "metadata contains secret-like keys"
  }

  Write-Host "[iteration-smoke] dry-run state=$($parsed.state) branch=$($parsed.branch)"
  Write-Host "[iteration-smoke] SkyBridge offline fail-open path validated"
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
