. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$path = "docs/smoke-managed-mode-dedupe-$([Guid]::NewGuid().ToString('n')).md"
try {
  "temporary managed-mode dedupe smoke 1" | Set-Content -LiteralPath $path -Encoding UTF8
  git add -- $path *> $null
  if ($LASTEXITCODE -ne 0) { throw "git add failed for dedupe smoke." }
  "temporary managed-mode dedupe smoke 2" | Set-Content -LiteralPath $path -Encoding UTF8
  $result = Invoke-ManagedModePilotJson "changed-files-preview"
  $matches = @($result.changed_files | Where-Object { $_ -eq $path })
  if ($matches.Count -ne 1) { throw "Expected one de-duplicated changed path, got $($matches.Count)." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-changed-files-deduplicates"
} finally {
  git restore --staged -- $path *> $null
  Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

