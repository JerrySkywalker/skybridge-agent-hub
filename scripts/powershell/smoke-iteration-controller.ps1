[CmdletBinding()]
param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$goalFile = ".\goals\backlog\030-controller-dry-run-validation.md"
if (-not (Test-Path -LiteralPath $goalFile)) {
  throw "missing controller dry-run validation goal: $goalFile"
}
$parsed = $null

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
  if ($parsed.skybridge_fail_open -ne $true) {
    throw "SkyBridge offline fail-open flag missing"
  }
  if ($parsed.notification_dry_run_path -ne $true) {
    throw "notification dry-run path flag missing"
  }
  if ($parsed.codex_command -notmatch "codex exec") {
    throw "codex command shape missing"
  }
  if ($parsed.branch -ne "ai/030-controller-dry-run-validation") {
    throw "unexpected branch calculation: $($parsed.branch)"
  }

  $metadataPath = Join-Path $parsed.run_dir "metadata.json"
  if (-not (Test-Path -LiteralPath $metadataPath)) {
    throw "metadata file missing: $metadataPath"
  }
  $metadataText = Get-Content -LiteralPath $metadataPath -Raw
  if ($metadataText -match "token|secret|password|cookie") {
    throw "metadata contains secret-like keys"
  }
  $metadata = $metadataText | ConvertFrom-Json
  if ($metadata.auto_merge -ne $false) {
    throw "metadata auto-merge must be disabled"
  }
  $promptPreview = Join-Path $parsed.run_dir "prompt-preview.md"
  if (-not (Test-Path -LiteralPath $promptPreview)) {
    throw "prompt preview missing: $promptPreview"
  }

  Write-Host "[iteration-smoke] dry-run state=$($parsed.state) branch=$($parsed.branch)"
  Write-Host "[iteration-smoke] SkyBridge offline fail-open path validated"
} finally {
  if ($parsed -and $parsed.run_dir -and (Test-Path -LiteralPath $parsed.run_dir)) {
    Remove-Item -LiteralPath $parsed.run_dir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
