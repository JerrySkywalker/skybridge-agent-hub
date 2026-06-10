. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$path = "docs/smoke-managed-mode-untracked-doc-$([Guid]::NewGuid().ToString('n')).md"
try {
  "temporary managed-mode untracked docs smoke" | Set-Content -LiteralPath $path -Encoding UTF8
  $result = Invoke-ManagedModePilotJson "changed-files-preview"
  if (@($result.changed_files) -notcontains ($path -replace "\\", "/")) { throw "Untracked docs file was not detected." }
  if ($result.allowed -ne $true) { throw "Untracked docs file should be allowed." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-changed-files-detects-untracked-doc"
} finally {
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

