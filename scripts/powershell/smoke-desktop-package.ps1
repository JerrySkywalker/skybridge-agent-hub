$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pkgPath = Join-Path $repoRoot "apps\desktop\package.json"
if (-not (Test-Path -LiteralPath $pkgPath -PathType Leaf)) { throw "Missing apps/desktop/package.json." }
$pkg = Get-Content -Raw -LiteralPath $pkgPath | ConvertFrom-Json
if ($pkg.name -ne "@skybridge/desktop") { throw "Unexpected desktop package name: $($pkg.name)" }
foreach ($script in @("dev", "build", "lint", "typecheck", "test")) {
  if (-not $pkg.scripts.$script) { throw "Missing desktop script: $script" }
}
if (-not $pkg.dependencies."@tauri-apps/api") { throw "Missing @tauri-apps/api dependency." }
if (-not $pkg.devDependencies."@tauri-apps/cli") { throw "Missing @tauri-apps/cli dev dependency." }
foreach ($path in @("apps\desktop\src", "apps\desktop\src-tauri", "apps\desktop\src-tauri\Cargo.toml")) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $path))) { throw "Missing desktop scaffold path: $path" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-package"; token_printed = $false } | ConvertTo-Json -Compress
