$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pkgPath = Join-Path $repoRoot "apps\desktop\package.json"
$configPath = Join-Path $repoRoot "apps\desktop\src-tauri\tauri.conf.json"

if (-not (Test-Path -LiteralPath $pkgPath -PathType Leaf)) {
  throw "Missing apps/desktop/package.json."
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
  throw "Missing apps/desktop/src-tauri/tauri.conf.json."
}

$pkg = Get-Content -Raw -LiteralPath $pkgPath | ConvertFrom-Json
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json

$dev = [string]$pkg.scripts.dev
if ([string]::IsNullOrWhiteSpace($dev)) { throw "Missing scripts.dev." }
if ($dev -notmatch "\bvite\b") { throw "scripts.dev must start Vite." }
if ($dev -notmatch "1420") { throw "scripts.dev must bind port 1420." }
if ($dev -match "tauri\s+dev") { throw "scripts.dev must not call tauri dev." }

$tauri = [string]$pkg.scripts.tauri
if ($tauri -ne "tauri") { throw "scripts.tauri must equal 'tauri'." }

$tauriDev = [string]$pkg.scripts."tauri:dev"
if ($tauriDev -ne "tauri dev") { throw "scripts.tauri:dev must equal 'tauri dev'." }

if ([string]$config.build.beforeDevCommand -ne "corepack pnpm dev") {
  throw "Tauri beforeDevCommand must equal 'corepack pnpm dev'."
}
if ([string]$config.build.devUrl -ne "http://localhost:1420") {
  throw "Tauri devUrl must equal 'http://localhost:1420'."
}

[pscustomobject]@{
  ok = $true
  scenario = "desktop-dev-command-no-recursion"
  token_printed = $false
} | ConvertTo-Json -Compress
