. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$dir = ".agent/tmp/managed-mode-pilot-208"
$path = Join-Path $dir "smoke-ignored-$([Guid]::NewGuid().ToString('n')).txt"
try {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  "temporary ignored managed-mode smoke" | Set-Content -LiteralPath $path -Encoding UTF8
  $result = Invoke-ManagedModePilotJson "changed-files-preview"
  $normalized = ($path -replace "\\", "/")
  if (@($result.changed_files) -contains $normalized) { throw ".agent/tmp ignored file was reported as a repo change." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-changed-files-ignores-agent-tmp"
} finally {
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

