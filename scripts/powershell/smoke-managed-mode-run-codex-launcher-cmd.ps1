. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-codex-cmd-" + [Guid]::NewGuid().ToString("n"))
$oldPath = $env:PATH
try {
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  "@echo off" | Set-Content -LiteralPath (Join-Path $tempDir "codex.cmd") -Encoding ASCII
  $filteredPath = (@($oldPath -split [System.IO.Path]::PathSeparator) | Where-Object { $_ -and $_ -notmatch '\\npm$' }) -join [System.IO.Path]::PathSeparator
  $env:PATH = "$tempDir$([System.IO.Path]::PathSeparator)$filteredPath"
  $diag = Invoke-ManagedModeRunJson "run-invocation-diagnostics"
  if ($diag.launcher_kind -ne "cmd") { throw "Expected cmd launcher." }
  if ($diag.host_executable_name -ne "cmd.exe") { throw "Expected cmd.exe host." }
  if ($diag.selected_profile_id -ne "profile_workspace_write_workdir") { throw "Expected workspace-write profile." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-codex-launcher-cmd"
} finally {
  $env:PATH = $oldPath
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
