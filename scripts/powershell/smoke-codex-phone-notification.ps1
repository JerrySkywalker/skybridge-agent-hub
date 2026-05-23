[CmdletBinding(DefaultParameterSetName="DryRun")]
param(
  [Parameter(ParameterSetName="DryRun")]
  [switch]$DryRun,

  [Parameter(ParameterSetName="Send")]
  [switch]$Send,

  [ValidateSet("info", "warning", "urgent")]
  [string]$Severity = "info",

  [string]$CodexCommand = "codex",

  [string]$OutputDir
)

$ErrorActionPreference = "Stop"

function New-SmokeTimestamp {
  return (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
}

function Test-TextPattern {
  param(
    [string]$Text,
    [string]$Pattern
  )
  return [bool]([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
}

$repoRoot = (Resolve-Path ".").Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $repoRoot (Join-Path ".agent\codex-phone-smoke" (New-SmokeTimestamp))
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$codexJsonl = Join-Path $OutputDir "codex.jsonl"
$lastMessage = Join-Path $OutputDir "last-message.md"
$summaryFile = Join-Path $OutputDir "summary.json"
$mode = if ($Send) { "send" } else { "dry-run" }
$notifyFlag = if ($Send) { "-Send" } else { "-DryRun" }
$jsonFlag = if ($Send) { "" } else { " -Json" }
$expectedOutcome = if ($Send) { "ntfy status sent" } else { "dry_run true and ntfy status configured" }

$prompt = @"
You are running a SkyBridge Agent Hub notification smoke test.

Task:
1. Do not read, print, summarize, or expose environment variable values or secrets.
2. Do not edit files, commit, push, deploy, or change configuration.
3. From the repository root, run exactly this PowerShell notifier command:

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 -Title "SkyBridge Codex phone smoke" -Message "Codex exec invoked notify-bootstrap.ps1 for a $mode smoke test." -Severity $Severity $notifyFlag$jsonFlag

4. Report only whether the command ran, its exit status, and whether the notifier output showed $expectedOutcome.

The notifier is responsible for loading the local bootstrap notification env file from the user's home directory. Do not include any real topic, token, password, webhook URL, or environment variable value in your response.
"@

Write-Host "[codex-phone-smoke] mode: $mode"
Write-Host "[codex-phone-smoke] severity: $Severity"
Write-Host "[codex-phone-smoke] output_dir: $OutputDir"
Write-Host "[codex-phone-smoke] jsonl: $codexJsonl"
Write-Host "[codex-phone-smoke] last_message: $lastMessage"

& $CodexCommand exec `
  --sandbox danger-full-access `
  -C $repoRoot `
  --json `
  --output-last-message $lastMessage `
  $prompt 2>&1 | Tee-Object -FilePath $codexJsonl | ForEach-Object { Write-Host $_ }
$codexExit = $LASTEXITCODE

$jsonlText = if (Test-Path -LiteralPath $codexJsonl -PathType Leaf) { Get-Content -LiteralPath $codexJsonl -Raw } else { "" }
$lastText = if (Test-Path -LiteralPath $lastMessage -PathType Leaf) { Get-Content -LiteralPath $lastMessage -Raw } else { "" }
$combinedText = "$jsonlText`n$lastText"
$searchText = $combinedText.Replace('\"', '"')

$appearedToRunNotify = Test-TextPattern -Text $searchText -Pattern "notify-bootstrap\.ps1"
$includedDryRunConfigured = (Test-TextPattern -Text $searchText -Pattern '"dry_run"\s*:\s*true') -and
  (Test-TextPattern -Text $searchText -Pattern '"provider"\s*:\s*"ntfy"') -and
  (Test-TextPattern -Text $searchText -Pattern '"status"\s*:\s*"configured"')
$includedNtfySent = ((Test-TextPattern -Text $searchText -Pattern '"provider"\s*:\s*"ntfy"') -and
  (Test-TextPattern -Text $searchText -Pattern '"status"\s*:\s*"sent"')) -or
  (Test-TextPattern -Text $searchText -Pattern "ntfy\s+sent")

$summary = @{
  ok = ($codexExit -eq 0) -and $appearedToRunNotify -and ($(if ($Send) { $includedNtfySent } else { $includedDryRunConfigured }))
  mode = $mode
  dry_run = -not [bool]$Send
  send_requested = [bool]$Send
  severity = $Severity
  codex_exit_code = $codexExit
  appeared_to_run_notify_bootstrap = $appearedToRunNotify
  output_included_ntfy_sent = $includedNtfySent
  output_included_dry_run_configured = $includedDryRunConfigured
  output_dir = $OutputDir
  codex_jsonl = $codexJsonl
  last_message = $lastMessage
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryFile -Encoding UTF8

Write-Host "[codex-phone-smoke] appeared_to_run_notify_bootstrap=$appearedToRunNotify"
Write-Host "[codex-phone-smoke] output_included_ntfy_sent=$includedNtfySent"
Write-Host "[codex-phone-smoke] output_included_dry_run_configured=$includedDryRunConfigured"
Write-Host "[codex-phone-smoke] summary: $summaryFile"

if (-not $summary.ok) {
  exit 1
}
