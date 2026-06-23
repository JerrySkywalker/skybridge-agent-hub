$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$script:DraftSubmitServerProcess = $null
$script:DraftSubmitTempDir = $null
$script:DraftSubmitApiBase = $null

function Invoke-DraftSubmitJson {
  param(
    [string]$Method,
    [string]$Path,
    $Body = $null
  )
  $uri = "$script:DraftSubmitApiBase$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20)
}

function Wait-DraftSubmitServer {
  for ($attempt = 0; $attempt -lt 50; $attempt++) {
    try { return Invoke-DraftSubmitJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 400 }
  }
  throw "Draft submit smoke server did not become healthy."
}

function Start-DraftSubmitSmokeServer {
  param(
    [string]$ProjectId = "skybridge-agent-hub"
  )
  $script:DraftSubmitTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-draft-submit-" + [Guid]::NewGuid().ToString("n"))
  New-Item -ItemType Directory -Path $script:DraftSubmitTempDir | Out-Null
  $dbFile = Join-Path $script:DraftSubmitTempDir "skybridge.sqlite"
  $port = Get-Random -Minimum 18000 -Maximum 28000
  $script:DraftSubmitApiBase = "http://127.0.0.1:$port"
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $serverCommand)
    PassThru = $true
  }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $script:DraftSubmitServerProcess = Start-Process @startProcessParams
  Wait-DraftSubmitServer | Out-Null
  Invoke-DraftSubmitJson "POST" "/v1/projects" @{
    project_id = $ProjectId
    name = "Draft Submit Smoke Project"
  } | Out-Null
  $script:DraftSubmitApiBase
}

function Stop-DraftSubmitSmokeServer {
  if ($script:DraftSubmitServerProcess) {
    try { $script:DraftSubmitServerProcess.Kill($true) } catch { Stop-Process -Id $script:DraftSubmitServerProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  if ($script:DraftSubmitTempDir) {
    Remove-Item -LiteralPath $script:DraftSubmitTempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function New-DraftSubmitInputFile {
  param(
    [ValidateSet("sample-docs", "sample-matlab", "unsafe", "unknown-template")]
    [string]$Kind,
    [string]$ProjectId = "skybridge-agent-hub"
  )
  if (-not $script:DraftSubmitTempDir) { throw "Smoke temp dir not initialized." }
  $planner = Join-Path $PSScriptRoot "skybridge-chat-to-task-draft.ps1"
  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $planner, "-ProjectId", $ProjectId, "-Json")
  if ($Kind -eq "sample-docs") {
    $args += @("-Command", "sample-docs")
  } elseif ($Kind -eq "sample-matlab") {
    $args += @("-Command", "sample-matlab")
  } elseif ($Kind -eq "unsafe") {
    $args += @("-Command", "draft", "-InputText", "production deploy DNS Cloudflare OpenResty Authelia GitHub settings secrets")
  } else {
    $args += @("-Command", "sample-docs")
  }
  $raw = & pwsh @args
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $preview = $text | ConvertFrom-Json
  if ($Kind -eq "unknown-template") {
    $preview.draft.template_id = "unknown-template.v1"
  }
  $path = Join-Path $script:DraftSubmitTempDir "$Kind.json"
  $preview | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

function Invoke-DraftSubmitScript {
  param(
    [string]$Command,
    [string]$InputJsonFile = "",
    [switch]$Confirm,
    [string]$ConfirmationText = "",
    [string]$ProjectId = "skybridge-agent-hub"
  )
  $scriptPath = Join-Path $PSScriptRoot "skybridge-draft-submit.ps1"
  $scriptArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $scriptPath,
    "-Command",
    $Command,
    "-ApiBase",
    $script:DraftSubmitApiBase,
    "-ProjectId",
    $ProjectId,
    "-Json"
  )
  if (-not [string]::IsNullOrWhiteSpace($InputJsonFile)) {
    $scriptArgs += @("-InputJsonFile", $InputJsonFile)
  }
  if ($Confirm) {
    $scriptArgs += "-Confirm"
  }
  if (-not [string]::IsNullOrWhiteSpace($ConfirmationText)) {
    $scriptArgs += @("-ConfirmationText", $ConfirmationText)
  }
  $raw = & pwsh @scriptArgs
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Assert-DraftSubmitDisabledFlags {
  param($Value, [string]$Name)
  Assert-False $Value.claim_created "$Name claim_created"
  Assert-False $Value.execution_started "$Name execution_started"
  Assert-False $Value.codex_run_called "$Name codex_run_called"
  Assert-False $Value.matlab_run_called "$Name matlab_run_called"
  Assert-False $Value.worker_loop_started "$Name worker_loop_started"
  Assert-False $Value.arbitrary_shell_enabled "$Name arbitrary_shell_enabled"
  if ($Value.PSObject.Properties.Name -contains "project_control_unpause") {
    Assert-False $Value.project_control_unpause "$Name project_control_unpause"
  }
  Assert-False $Value.raw_prompt_persisted "$Name raw_prompt_persisted"
  Assert-False $Value.raw_response_persisted "$Name raw_response_persisted"
  Assert-TokenPrintedFalse $Value
}
