. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-codex-exe-" + [Guid]::NewGuid().ToString("n"))
$oldPath = $env:PATH
try {
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  Copy-Item -LiteralPath (Get-Command pwsh).Source -Destination (Join-Path $tempDir "codex.exe")
  $filteredPath = (@($oldPath -split [System.IO.Path]::PathSeparator) | Where-Object { $_ -and $_ -notmatch '\\npm$' }) -join [System.IO.Path]::PathSeparator
  $env:PATH = "$tempDir$([System.IO.Path]::PathSeparator)$filteredPath"
  $profile = Invoke-ManagedModeRunJson "run-invocation-profile"
  if ($profile.selected_invocation_profile -ne "profile_workspace_write_workdir") { throw "Expected workspace-write profile." }
  $diag = Invoke-ManagedModeRunJson "run-invocation-diagnostics"
  if ($diag.launcher_kind -ne "codex.exe") { throw "Expected exe launcher." }
  if ($diag.host_executable_name -ne "codex.exe") { throw "Expected direct exe host metadata." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-codex-launcher-exe"
} finally {
  $env:PATH = $oldPath
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
