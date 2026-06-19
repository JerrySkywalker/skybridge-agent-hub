[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\hermes-exposure-readiness-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$emptyEnvFile = Join-Path $tmpRoot "empty-hermes.env.ps1"
"" | Set-Content -LiteralPath $emptyEnvFile -Encoding UTF8

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-Capture {
  param([string[]]$Arguments, [hashtable]$Env = @{})
  $old = @{}
  foreach ($key in $Env.Keys) {
    $old[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    [Environment]::SetEnvironmentVariable($key, $Env[$key], "Process")
  }
  try {
    $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
    [pscustomobject]@{ exit_code = $LASTEXITCODE; text = (($output | Out-String).Trim()) }
  } finally {
    foreach ($key in $Env.Keys) {
      [Environment]::SetEnvironmentVariable($key, $old[$key], "Process")
    }
  }
}

function ConvertFrom-ResultJson {
  param($Capture, [string]$Name)
  Assert-NoUnsafeText $Capture.text
  try { return $Capture.text | ConvertFrom-Json } catch { throw "$Name did not return JSON: $($Capture.text)" }
}

function Assert-Contains {
  param($Values, [string]$Expected, [string]$Name)
  if (@($Values) -notcontains $Expected) { throw "$Name missing expected value '$Expected'." }
}

$disabledFixture = Write-Fixture "capabilities-disabled.json" ([pscustomobject]@{
  platform = "hermes"
  model = "hermes-fixture-model"
  runtime = [pscustomobject]@{ mode = "server_agent"; tool_execution = "disabled" }
  features = [pscustomobject]@{ responses_api = $true; runs = $false }
  token_printed = $false
})
$serverToolFixture = Write-Fixture "capabilities-server-tool.json" ([pscustomobject]@{
  platform = "hermes"
  model = "hermes-fixture-model"
  runtime = [pscustomobject]@{ mode = "server_agent"; tool_execution = "server" }
  features = [pscustomobject]@{ responses_api = $true; runs = $false }
  raw_response = "SHOULD_NOT_APPEAR"
  token_printed = $false
})

$script = ".\scripts\powershell\skybridge-hermes-exposure-readiness.ps1"
$scenarios = New-Object System.Collections.Generic.List[object]

$missingBase = Invoke-Capture @("-File", $script, "-Json") @{ HERMES_ENV_FILE = $emptyEnvFile; HERMES_API_BASE = ""; HERMES_API_KEY = "fixture-key-value" }
$missingBaseJson = ConvertFrom-ResultJson $missingBase "missing base"
Assert-Contains $missingBaseJson.blockers "hermes_api_base_missing" "missing base blockers"
Assert-False $missingBaseJson.token_printed "missing base token_printed"
$scenarios.Add([pscustomobject]@{ name = "missing_hermes_api_base_safe"; ok = $true }) | Out-Null

$missingKey = Invoke-Capture @("-File", $script, "-ApiBase", "https://private.hermes.fixture", "-Json") @{ HERMES_ENV_FILE = $emptyEnvFile; HERMES_API_KEY = "" }
$missingKeyJson = ConvertFrom-ResultJson $missingKey "missing key"
Assert-Contains $missingKeyJson.blockers "hermes_api_key_missing" "missing key blockers"
Assert-False $missingKeyJson.hermes.api_key_configured "missing key configured"
$scenarios.Add([pscustomobject]@{ name = "missing_hermes_api_key_safe"; ok = $true }) | Out-Null

$http = Invoke-Capture @("-File", $script, "-ApiBase", "http://private.hermes.fixture", "-FixtureFile", $disabledFixture, "-Json") @{ HERMES_ENV_FILE = $emptyEnvFile; HERMES_API_KEY = "fixture-key-value" }
$httpJson = ConvertFrom-ResultJson $http "http"
Assert-Contains $httpJson.blockers "hermes_https_required" "http blockers"
Assert-False $httpJson.hermes.https_only "http https_only"
$scenarios.Add([pscustomobject]@{ name = "https_required"; ok = $true }) | Out-Null

$redacted = Invoke-Capture @("-File", $script, "-ApiBase", "https://private.hermes.fixture/sensitive/path?token=SHOULD_NOT_APPEAR", "-FixtureFile", $disabledFixture, "-Json") @{ HERMES_ENV_FILE = $emptyEnvFile; HERMES_API_KEY = "fixture-key-value" }
$redactedJson = ConvertFrom-ResultJson $redacted "redacted endpoint"
if ($redacted.text -match "private\.hermes\.fixture|SHOULD_NOT_APPEAR") { throw "Endpoint or marker leaked in redacted endpoint scenario." }
Assert-True $redactedJson.hermes.endpoint_redacted "endpoint redacted"
Assert-False $redactedJson.safety.credential_values_exposed "credential values exposed"
Assert-False $redactedJson.safety.raw_response_included "raw response included"
$scenarios.Add([pscustomobject]@{ name = "endpoint_redacted"; ok = $true }) | Out-Null

$serverTool = Invoke-Capture @("-File", $script, "-ApiBase", "https://private.hermes.fixture", "-FixtureFile", $serverToolFixture, "-Json") @{ HERMES_ENV_FILE = $emptyEnvFile; HERMES_API_KEY = "fixture-key-value" }
$serverToolJson = ConvertFrom-ResultJson $serverTool "server tool"
Assert-Contains $serverToolJson.warnings "hermes_server_tool_execution_enabled" "server tool warnings"
if ($serverToolJson.risk_level -ne "high") { throw "server tool execution should be high risk." }
Assert-False $serverToolJson.allow_worker_heartbeat "server tool default heartbeat"
Assert-False $serverToolJson.allow_start_one "server tool start-one"
Assert-False $serverToolJson.allow_run_until_hold "server tool run-until-hold"
if ($serverTool.text -match "SHOULD_NOT_APPEAR") { throw "Raw Hermes fixture marker leaked." }
$scenarios.Add([pscustomobject]@{ name = "server_tool_execution_high_risk"; ok = $true }) | Out-Null

$heartbeatOnly = Invoke-Capture @("-File", $script, "-ApiBase", "https://private.hermes.fixture", "-FixtureFile", $serverToolFixture, "-AllowServerToolExecution", "-Json") @{ HERMES_ENV_FILE = $emptyEnvFile; HERMES_API_KEY = "fixture-key-value" }
$heartbeatOnlyJson = ConvertFrom-ResultJson $heartbeatOnly "heartbeat only"
Assert-True $heartbeatOnlyJson.allow_worker_heartbeat "heartbeat-only allowance"
Assert-False $heartbeatOnlyJson.allow_start_one "heartbeat-only start-one"
Assert-False $heartbeatOnlyJson.allow_run_until_hold "heartbeat-only run-until-hold"
$scenarios.Add([pscustomobject]@{ name = "server_tool_execution_heartbeat_only_opt_in"; ok = $true }) | Out-Null

$secondGate = Invoke-Capture @("-File", $script, "-ApiBase", "https://private.hermes.fixture", "-FixtureFile", $serverToolFixture, "-RequireSecondGate", "-Json") @{ HERMES_ENV_FILE = $emptyEnvFile; HERMES_API_KEY = "fixture-key-value"; HERMES_SECOND_GATE_IP_ALLOWLIST_CONFIGURED = "" }
$secondGateJson = ConvertFrom-ResultJson $secondGate "second gate required"
Assert-Contains $secondGateJson.blockers "hermes_second_gate_required_for_server_tool_execution" "second gate blockers"
Assert-False $secondGateJson.allow_start_one "second gate start-one"
$scenarios.Add([pscustomobject]@{ name = "second_gate_required_for_execution"; ok = $true }) | Out-Null

$aggregate = @($missingBase.text, $missingKey.text, $http.text, $redacted.text, $serverTool.text, $heartbeatOnly.text, $secondGate.text) -join "`n"
Assert-NoUnsafeText $aggregate
foreach ($needle in @("SHOULD_NOT_APPEAR", "fixture-key-value", "private.hermes.fixture")) {
  if ($aggregate -match [regex]::Escape($needle)) { throw "Unsafe aggregate marker leaked: $needle" }
}

$summary = [pscustomobject]@{
  ok = $true
  smoke = "hermes-exposure-readiness"
  scenarios = @($scenarios.ToArray())
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "hermes-exposure-readiness"
}
