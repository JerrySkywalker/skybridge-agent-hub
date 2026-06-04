$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$desktopFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot "apps\desktop") -Recurse -File |
  Where-Object {
    $_.FullName -notmatch "\\node_modules\\" -and
    $_.FullName -notmatch "\\dist\\" -and
    $_.FullName -notmatch "\\src-tauri\\target\\" -and
    $_.FullName -notmatch "\\src-tauri\\gen\\"
  }
$text = ($desktopFiles | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
foreach ($forbidden in @(
  "start-one",
  "start-all",
  "execute-step",
  "claim",
  "run-until-complete",
  "run-until-hold",
  "skybridge-edge-worker.ps1",
  "worker loop",
  "create PR",
  "campaign-step task creation"
)) {
  if ($text -match [regex]::Escape($forbidden)) { throw "Desktop MVP contains forbidden task execution text: $forbidden" }
}
if ($text -match "(?i)(sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|private key|authorization:\s*bearer\s+[A-Za-z0-9_.-]{12,})") { throw "Desktop MVP appears to contain secret material." }
[pscustomobject]@{ ok = $true; scenario = "desktop-no-task-execution"; token_printed = $false } | ConvertTo-Json -Compress
