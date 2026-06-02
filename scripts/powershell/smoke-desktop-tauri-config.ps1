$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$configPath = Join-Path $repoRoot "apps\desktop\src-tauri\tauri.conf.json"
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.identifier -ne "space.jerryskywalker.skybridge.desktop") { throw "Unexpected Tauri identifier." }
if ($config.productName -ne "SkyBridge Desktop") { throw "Unexpected productName." }
if (-not $config.app.trayIcon.iconPath) { throw "Missing tray icon path." }
if ($config.app.trayIcon.iconPath -ne "icons/icon.png") { throw "Unexpected tray icon path." }
if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $configPath) "icons\icon.png"))) { throw "Missing tray png icon." }
if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $configPath) "icons\icon.ico"))) { throw "Missing Windows ico icon." }
$cargo = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\Cargo.toml")
if ($cargo -notmatch 'tauri = \{ version = "2"') { throw "Expected Tauri v2 dependency." }
if ($cargo -notmatch 'tray-icon') { throw "Expected tray-icon feature." }
[pscustomobject]@{ ok = $true; scenario = "desktop-tauri-config"; token_printed = $false } | ConvertTo-Json -Compress
