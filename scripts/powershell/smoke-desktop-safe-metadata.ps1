$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$gitignore = Get-Content -Raw -LiteralPath (Join-Path $repoRoot ".gitignore")
$lib = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs")

if ($gitignore -notmatch [regex]::Escape(".agent/desktop-client/")) {
  throw ".agent/desktop-client/ must be gitignored."
}
foreach ($expected in @(
  'join(".agent").join("desktop-client")',
  'join("status.json")',
  'join("logs").join("desktop-client.log")'
)) {
  if ($lib -notmatch [regex]::Escape($expected)) {
    throw "Desktop metadata path is not fixed under .agent/desktop-client: $expected"
  }
}

$scanFiles = @(
  (Join-Path $repoRoot "apps\desktop\src\main.tsx"),
  (Join-Path $repoRoot "apps\desktop\src\styles.css"),
  (Join-Path $repoRoot "apps\desktop\src-tauri\src\lib.rs"),
  (Join-Path $repoRoot "docs\dev\DESKTOP_CLIENT_MVP.md")
) | Where-Object { Test-Path -LiteralPath $_ }
$scanText = ($scanFiles | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n"
if ($scanText -match "(?i)(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|authorization:\s*bearer\s+[A-Za-z0-9_.-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)") {
  throw "Desktop source or docs appear to contain secret-looking text."
}

[pscustomobject]@{ ok = $true; scenario = "desktop-safe-metadata"; token_printed = $false } | ConvertTo-Json -Compress
