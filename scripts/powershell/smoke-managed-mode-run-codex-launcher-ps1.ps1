. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-codex-ps1-" + [Guid]::NewGuid().ToString("n"))
$oldPath = $env:PATH
try {
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  "# fixture" | Set-Content -LiteralPath (Join-Path $tempDir "codex.ps1") -Encoding UTF8
  $filteredPath = (@($oldPath -split [System.IO.Path]::PathSeparator) | Where-Object { $_ -and $_ -notmatch '\\npm$' }) -join [System.IO.Path]::PathSeparator
  $env:PATH = "$tempDir$([System.IO.Path]::PathSeparator)$filteredPath"
  $profile = Invoke-ManagedModeRunJson "run-invocation-profile"
  $diag = Invoke-ManagedModeRunJson "run-invocation-diagnostics"
  if ($profile.selected_invocation_profile -ne "profile_workspace_write_workdir") { throw "Expected workspace-write profile." }
  if ($diag.launcher_kind -ne "ps1") { throw "Expected ps1 launcher." }
  if ($diag.host_executable_name -notin @("pwsh.exe", "pwsh", "powershell.exe")) { throw "Expected PowerShell host." }
  if ($diag.command_class -ne "codex_exec_workspace_write_workdir_stdin_discard_output") { throw "Unexpected command class." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-codex-launcher-ps1"
} finally {
  $env:PATH = $oldPath
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
