$ErrorActionPreference = "Stop"
$desktop = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
$tauri = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src-tauri\src\lib.rs")
foreach ($forbidden in @("run-sanitized-executor", "invoke-codex-task.ps1", "codex exec", "gh pr create", "Start All")) {
  if ($tauri -match [regex]::Escape($forbidden)) { throw "Tauri desktop exposes forbidden execution path: $forbidden" }
}
if ($desktop -notmatch "EXECUTION DISABLED") { throw "Execution disabled banner missing." }
[pscustomobject]@{ ok = $true; scenario = "desktop-worker-supervisor-no-execution"; task_executed = $false; token_printed = $false } | ConvertTo-Json -Compress
