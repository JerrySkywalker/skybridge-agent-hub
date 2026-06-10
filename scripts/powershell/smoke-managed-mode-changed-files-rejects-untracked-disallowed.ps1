. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$path = "smoke-managed-mode-untracked-disallowed-$([Guid]::NewGuid().ToString('n')).txt"
try {
  "temporary managed-mode disallowed smoke" | Set-Content -LiteralPath $path -Encoding UTF8
  $result = Invoke-ManagedModePilotJson "changed-files-preview"
  if (@($result.changed_files) -notcontains $path) { throw "Untracked disallowed file was not detected." }
  if ($result.allowed -ne $false) { throw "Untracked disallowed file should fail closed." }
  if (@($result.disallowed_files) -notcontains $path) { throw "Disallowed file was not reported." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-changed-files-rejects-untracked-disallowed"
} finally {
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

