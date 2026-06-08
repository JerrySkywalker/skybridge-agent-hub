[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Push-Location $repoRoot
try {
  $before = (git status --short | Out-String).Trim()
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1") -Command heartbeat -Apply -Json | Out-Null
  $after = (git status --short | Out-String).Trim()
  $changed = @($after -split "(`r`n|`n|`r)" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $before -notmatch [regex]::Escape($_) })
  $unignoredWorkerArtifacts = @($changed | Where-Object { $_ -match "\.agent" -and $_ -notmatch "\.agent[\\/]+tmp[\\/]+worker-service" })
  if ($unignoredWorkerArtifacts.Count -gt 0) { throw "Worker service wrote unignored artifacts: $($unignoredWorkerArtifacts -join '; ')" }
  git check-ignore -q ".agent/tmp/worker-service/worker-service-state.json"
  if ($LASTEXITCODE -ne 0) { throw ".agent/tmp/worker-service is not ignored." }
  [pscustomobject]@{
    ok = $true
    smoke = "worker-service-clean-worktree"
    clean_tree_preserved = ($before -eq $after)
    ignored_artifact_path = ".agent/tmp/worker-service/"
    token_printed = $false
  } | ConvertTo-Json -Depth 10 -Compress
} finally {
  Pop-Location
}
