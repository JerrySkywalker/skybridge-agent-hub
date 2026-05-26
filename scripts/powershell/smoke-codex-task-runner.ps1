[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "invoke-codex-task.ps1")

$runDir = Join-Path ".\.agent\tmp" ("codex-task-smoke-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$lastMessagePath = Join-Path $runDir "last-message.md"
$jsonlPath = Join-Path $runDir "codex-exec.jsonl"
$promptPath = Join-Path $runDir "prompt.md"
$commandShapePath = Join-Path $runDir "dry-run-command.json"

$pathConfig = [pscustomobject]@{
  repo_path = (Resolve-Path ".").Path
  codex_sandbox = "danger-full-access"
}
$codexResolution = Resolve-CodexCommand -Config $pathConfig
$execArgs = @(New-CodexExecArguments -Sandbox "danger-full-access" -LastMessagePath $lastMessagePath)
if ($codexResolution.resolution_source -ne "PATH") { throw "Expected Codex dry-run to resolve from PATH when codex_command is omitted." }
if ($execArgs[-1] -ne "-") { throw "Expected Codex dry-run to pass prompt through stdin marker '-'." }

$multiWordPrompt = New-CodexTaskPrompt -Task ([pscustomobject]@{
  task_id = "smoke-codex-prompt"
  title = "Multi word prompt smoke"
  risk = "low"
  source = "smoke"
  prompt_summary = "Verify multi-word prompt and worker-owned git packaging instructions."
  body = "Update docs/dev/EDGE_WORKER_CODEX_INVOCATION_PILOT.md only. This sentence intentionally has many words."
})
Set-Content -LiteralPath $promptPath -Value $multiWordPrompt -Encoding UTF8 -NoNewline
if (-not ((Get-Content -Raw -LiteralPath $promptPath).Contains("do not run git add, git commit, git push or gh pr create"))) {
  throw "Expected Codex prompt to reserve commit, push and PR creation for the edge worker."
}

$missingPath = Join-Path $runDir "missing-codex.cmd"
try {
  Resolve-CodexCommand -Config ([pscustomobject]@{ codex_command = $missingPath }) | Out-Null
  throw "Expected missing configured codex_command to fail."
} catch {
  if ($_.Exception.Message -notmatch "Configured codex_command was not found") { throw }
}

$commandShape = @{
  command = $codexResolution.display_command
  resolved_path = $codexResolution.resolved_path
  resolution_source = $codexResolution.resolution_source
  powershell_shim = [bool]$codexResolution.powershell_shim
  args = $execArgs
  log_path = $jsonlPath
  last_message_path = $lastMessagePath
  prompt_path = $promptPath
  raw_logs_local_only = $true
  dry_run = [bool]$DryRun
}

$commandShape | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $commandShapePath -Encoding UTF8
$text = Get-Content -Raw -LiteralPath $commandShapePath
if ($text -cmatch "sk-(proj|ant|svcacct)-[A-Za-z0-9_-]+" -or $text -match "(?i)authorization:\s*bearer|password\s*[:=]\s*[^,\s}]+|cookie\s*[:=]\s*[^,\s}]+") {
  throw "Dry-run command shape exposed a secret-like value."
}
if (-not (Test-Path -LiteralPath $runDir -PathType Container)) { throw "Expected dry-run log directory." }

if (-not $DryRun) {
  throw "Real Codex smoke execution is intentionally not enabled by default. Re-run with -DryRun."
}

[pscustomobject]@{
  DryRun = $true
  CommandShapePath = (Resolve-Path -LiteralPath $commandShapePath).Path
  CodexResolutionSource = $codexResolution.resolution_source
  CodexCommand = $codexResolution.display_command
  CodexResolvedPath = $codexResolution.resolved_path
  PromptPath = (Resolve-Path -LiteralPath $promptPath).Path
  PromptViaStdin = $true
  MissingConfiguredCommandCheck = "passed"
  WorkerOwnsGitPackagingPrompt = $true
  LogPath = $jsonlPath
  LastMessagePath = $lastMessagePath
  SecretsPrinted = $false
  CodexExecuted = $false
} | Format-List
