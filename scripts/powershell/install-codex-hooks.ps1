param(
  [switch]$Apply,
  [string]$CodexDirectory = (Join-Path $HOME ".codex"),
  [string]$ApiBase = "http://127.0.0.1:8787",
  [string]$NodeId = "local-dev"
)

$ErrorActionPreference = "Stop"

function Convert-HookCommands {
  param($Value, [string]$RepositoryRoot)
  if ($Value -is [hashtable]) {
    $copy = @{}
    foreach ($key in $Value.Keys) {
      if ($key -eq "command" -and $Value[$key] -is [string]) {
        $copy[$key] = $Value[$key].Replace("./scripts/powershell", (Join-Path $RepositoryRoot "scripts\powershell"))
      } else {
        $copy[$key] = Convert-HookCommands -Value $Value[$key] -RepositoryRoot $RepositoryRoot
      }
    }
    return $copy
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    return ,@($Value | ForEach-Object { Convert-HookCommands -Value $_ -RepositoryRoot $RepositoryRoot })
  }
  return $Value
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$exampleFile = Join-Path $repositoryRoot "config\codex\hooks.example.json"
$targetFile = Join-Path $CodexDirectory "hooks.json"
$backupDirectory = Join-Path $CodexDirectory "skybridge-backups"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$config = Get-Content -Raw -Path $exampleFile | ConvertFrom-Json -AsHashtable
$config["env"]["SKYBRIDGE_API_BASE"] = $ApiBase
$config["env"]["SKYBRIDGE_NODE_ID"] = $NodeId
$generated = Convert-HookCommands -Value $config -RepositoryRoot $repositoryRoot
$json = $generated | ConvertTo-Json -Depth 80

Write-Output "Target Codex hooks file: $targetFile"
Write-Output "This installer writes user-level Codex hook config only when -Apply is provided."
Write-Output "No secrets are written. API base and node id are non-secret operator settings."

if (-not $Apply) {
  Write-Output "Dry run only. Re-run with -Apply to install."
  Write-Output $json
  exit 0
}

New-Item -ItemType Directory -Force -Path $CodexDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
if (Test-Path $targetFile) {
  Copy-Item -LiteralPath $targetFile -Destination (Join-Path $backupDirectory "hooks.$timestamp.json") -Force
}
$json | Set-Content -Path $targetFile -Encoding UTF8
Write-Output "Installed SkyBridge Codex hooks to $targetFile"
