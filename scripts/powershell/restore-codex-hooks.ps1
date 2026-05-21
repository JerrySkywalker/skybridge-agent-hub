param(
  [switch]$Apply,
  [string]$CodexDirectory = (Join-Path $HOME ".codex"),
  [string]$BackupFile
)

$ErrorActionPreference = "Stop"

$targetFile = Join-Path $CodexDirectory "hooks.json"
$backupDirectory = Join-Path $CodexDirectory "skybridge-backups"
if ([string]::IsNullOrWhiteSpace($BackupFile)) {
  $BackupFile = @(Get-ChildItem -Path $backupDirectory -Filter "hooks.*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if ([string]::IsNullOrWhiteSpace($BackupFile) -or -not (Test-Path $BackupFile)) { throw "No Codex hook backup found." }

Write-Output "Restore source: $BackupFile"
Write-Output "Restore target: $targetFile"
if (-not $Apply) {
  Write-Output "Dry run only. Re-run with -Apply to restore."
  exit 0
}

New-Item -ItemType Directory -Force -Path $CodexDirectory | Out-Null
Copy-Item -LiteralPath $BackupFile -Destination $targetFile -Force
Write-Output "Restored Codex hooks from $BackupFile"
