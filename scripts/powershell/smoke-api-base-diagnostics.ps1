[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

$tmp = Join-Path $RepoRoot ".agent\tmp\api-base-diagnostics-smoke"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$commit = "177ac8140f4adbcdd3f18c7a86818eb94a1a1caa"
$imageRef = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-$commit"

function Write-FixtureJson {
  param([string]$Name, $Value)
  $path = Join-Path $tmp $Name
  $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
  return $path
}

function Invoke-PwshCapture {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
  [pscustomobject]@{
    exit_code = $LASTEXITCODE
    text = (($output | Out-String).Trim())
  }
}

function Assert-Contains {
  param([string]$Text, [string]$Needle, [string]$Name)
  if ($Text -notmatch [regex]::Escape($Needle)) { throw "$Name missing expected text: $Needle" }
}

function Assert-NotContains {
  param([string]$Text, [string]$Needle, [string]$Name)
  if ($Text -match [regex]::Escape($Needle)) { throw "$Name contained unsafe text: $Needle" }
}

function Assert-ExitCode {
  param($Result, [int]$Expected, [string]$Name)
  if ([int]$Result.exit_code -ne $Expected) { throw "$Name exit code expected $Expected but got $($Result.exit_code): $($Result.text)" }
}

function ConvertFrom-SmokeJson {
  param($Result, [string]$Name)
  try { return ($Result.text | ConvertFrom-Json) } catch { throw "$Name did not return parseable JSON: $($Result.text)" }
}

function Get-FreeSmokePort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), 0)
  $listener.Start()
  $port = $listener.LocalEndpoint.Port
  $listener.Stop()
  return $port
}

function Start-FakeSkyBridgeServer {
  param([int]$Port, [string]$Mode, [string]$CommitSha, [string]$ImageRefValue)
  $nodeCode = @'
const http = require('http');
const port = Number(process.argv[2]);
const mode = process.argv[3];
const commit = process.argv[4];
const imageRef = process.argv[5];
const server = http.createServer((req, res) => {
  let status = 200;
  let body;
  if (req.url.split('?')[0] === '/v1/version') {
    body = { schema: 'skybridge.server_version.v1', service: 'skybridge-server', commit_sha: commit, image_tag: `sha-${commit}`, image_ref: imageRef, token_printed: false };
  } else if (req.url.split('?')[0] === '/v1/manual-tasks/providers' && mode === 'parity-fail') {
    status = 404;
    body = { ok: false, token_printed: false };
  } else {
    body = { ok: true, token_printed: false };
  }
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
});
server.listen(port, '127.0.0.1');
'@
  $serverPath = Join-Path $tmp "fake-skybridge-server.cjs"
  $nodeCode | Set-Content -LiteralPath $serverPath -Encoding utf8
  $process = Start-Process -FilePath "node" -ArgumentList @($serverPath, [string]$Port, $Mode, $CommitSha, $ImageRefValue) -PassThru -WindowStyle Hidden
  $base = "http://127.0.0.1:$Port"
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try {
      Invoke-RestMethod -Method GET -Uri "$base/v1/version" -TimeoutSec 1 | Out-Null
      return [pscustomobject]@{ process = $process; api_base = $base }
    } catch {
      Start-Sleep -Milliseconds 200
    }
  } while ((Get-Date) -lt $deadline)
  Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  throw "Fake SkyBridge server did not start."
}

$versionPath = Write-FixtureJson "version.json" ([pscustomobject]@{
  schema = "skybridge.server_version.v1"
  service = "skybridge-server"
  commit_sha = $commit
  image_tag = "sha-$commit"
  image_ref = $imageRef
  token_printed = $false
})
$hermesVersionPath = Write-FixtureJson "hermes-version.json" ([pscustomobject]@{
  schema = "hermes.capabilities.v1"
  service = "hermes-api"
  capabilities = @("responses")
  token_printed = $false
})
$dockerPath = Write-FixtureJson "docker-runs.json" @([pscustomobject]@{
  databaseId = [Int64]311001
  headSha = $commit
  status = "completed"
  conclusion = "success"
  event = "push"
  createdAt = "2026-06-18T01:00:00Z"
})
$deployPath = Write-FixtureJson "deploy-runs.json" @([pscustomobject]@{
  databaseId = [Int64]311002
  headSha = $commit
  status = "completed"
  conclusion = "success"
  event = "workflow_run"
  createdAt = "2026-06-18T01:10:00Z"
})
$reportPath = Write-FixtureJson "cloud-deploy-report.json" ([pscustomobject]@{
  schema = "skybridge.cloud_deploy_report.v1"
  status = "succeeded"
  reason = "deployed"
  deploy_scope = "skybridge-server-only"
  compose_source_provided = $true
  compose_install_status = "installed"
  rollback_status = "not_used"
  token_printed = $false
  commit_sha = $commit
  image_ref = $imageRef
  runtime_metadata = [pscustomobject]@{
    image_tag = "sha-$commit"
    image_ref = $imageRef
  }
})

$scenarios = New-Object System.Collections.Generic.List[object]

$placeholder = Invoke-PwshCapture @("-File", ".\scripts\powershell\skybridge-cloud-parity-check.ps1", "-ApiBase", "https://skybridge.example.com", "-Json")
Assert-ExitCode $placeholder 1 "placeholder ApiBase"
Assert-Contains $placeholder.text "SkyBridge ApiBase is a placeholder or invalid." "placeholder ApiBase"
Assert-Contains $placeholder.text "SKYBRIDGE_API_BASE" "placeholder ApiBase"
$scenarios.Add([pscustomobject]@{ name = "placeholder_fails_early"; ok = $true }) | Out-Null

$invalid = Invoke-PwshCapture @("-File", ".\scripts\powershell\skybridge-cloud-parity-check.ps1", "-ApiBase", "not a uri", "-Json")
Assert-ExitCode $invalid 1 "invalid ApiBase"
Assert-Contains $invalid.text "SkyBridge ApiBase is a placeholder or invalid." "invalid ApiBase"
Assert-Contains $invalid.text "SKYBRIDGE_API_BASE" "invalid ApiBase"
$scenarios.Add([pscustomobject]@{ name = "invalid_uri_fails_early"; ok = $true }) | Out-Null

$oldEnv = $env:SKYBRIDGE_API_BASE
try {
  $env:SKYBRIDGE_API_BASE = "https://skybridge.example.com"
  $override = Invoke-PwshCapture @("-File", ".\scripts\powershell\skybridge-cloud-parity-check.ps1", "-ApiBase", "http://127.0.0.1:1", "-FixtureHealthy", "-Json")
  Assert-ExitCode $override 0 "explicit ApiBase override"
  $overrideJson = ConvertFrom-SmokeJson $override "explicit ApiBase override"
  if ($overrideJson.ok -ne $true -or $overrideJson.api_base -ne "configured") { throw "explicit ApiBase override did not pass safely." }
  $scenarios.Add([pscustomobject]@{ name = "explicit_api_base_overrides_placeholder_env"; ok = $true }) | Out-Null

  $env:SKYBRIDGE_API_BASE = "http://127.0.0.1:1"
  $envResult = Invoke-PwshCapture @("-File", ".\scripts\powershell\skybridge-cloud-parity-check.ps1", "-FixtureHealthy", "-Json")
  Assert-ExitCode $envResult 0 "env ApiBase"
  $envJson = ConvertFrom-SmokeJson $envResult "env ApiBase"
  if ($envJson.ok -ne $true -or $envJson.api_base -ne "configured") { throw "env ApiBase did not pass safely." }
  $scenarios.Add([pscustomobject]@{ name = "skybridge_api_base_env_used"; ok = $true }) | Out-Null
} finally {
  $env:SKYBRIDGE_API_BASE = $oldEnv
}

$wrongService = Invoke-PwshCapture @("-File", ".\scripts\powershell\skybridge-cloud-parity-check.ps1", "-ApiBase", "http://127.0.0.1:1", "-FixtureHealthy", "-FixtureVersionFile", $hermesVersionPath, "-Json")
Assert-ExitCode $wrongService 1 "wrong service"
Assert-Contains $wrongService.text "SKYBRIDGE_API_BASE appears to point to Hermes API." "wrong service"
Assert-Contains $wrongService.text "API base" "wrong service"
$scenarios.Add([pscustomobject]@{ name = "wrong_service_hermes_detected"; ok = $true }) | Out-Null

$verifierArgs = @(
  "-File", ".\scripts\powershell\skybridge-verify-cloud-autodeploy.ps1",
  "-Repo", "JerrySkywalker/skybridge-agent-hub",
  "-Commit", $commit,
  "-FixtureDockerRunsFile", $dockerPath,
  "-FixtureDeployRunsFile", $deployPath,
  "-FixtureDeployReportFile", $reportPath,
  "-FixtureVersionFile", $versionPath,
  "-FixtureParityOk"
)
$textVerifier = Invoke-PwshCapture $verifierArgs
Assert-ExitCode $textVerifier 0 "verifier text"
foreach ($stage in @(
  "[1/8] resolve repo and commit",
  "[2/8] resolve SkyBridge ApiBase",
  "[3/8] wait Docker Images push workflow",
  "[4/8] wait Deploy Cloud workflow_run",
  "[5/8] download cloud-deploy-report artifact",
  "[6/8] validate deploy report",
  "[7/8] run cloud route parity",
  "[8/8] validate /v1/version",
  "PASS summary"
)) {
  Assert-Contains $textVerifier.text $stage "verifier text stages"
}
$scenarios.Add([pscustomobject]@{ name = "verifier_text_output_includes_stages"; ok = $true }) | Out-Null

$jsonVerifier = Invoke-PwshCapture ($verifierArgs + @("-Json"))
Assert-ExitCode $jsonVerifier 0 "verifier JSON"
$jsonVerifierParsed = ConvertFrom-SmokeJson $jsonVerifier "verifier JSON"
if ($jsonVerifierParsed.ok -ne $true -or $jsonVerifierParsed.token_printed -ne $false) { throw "verifier JSON contract mismatch." }
$scenarios.Add([pscustomobject]@{ name = "verifier_json_parseable"; ok = $true }) | Out-Null

$fakeGhDir = Join-Path $tmp "fake-gh"
New-Item -ItemType Directory -Force -Path $fakeGhDir | Out-Null
$fakeGhPath = Join-Path $fakeGhDir "gh.cmd"
@"
@echo off
echo fatal token=secret-value bearer abcdefghijklmnopqrstuvwxyz https://private.example.invalid 1>&2
exit /b 1
"@ | Set-Content -LiteralPath $fakeGhPath -Encoding ASCII
$oldPath = $env:PATH
try {
  $env:PATH = "$fakeGhDir;$oldPath"
  $ghFailure = Invoke-PwshCapture @(
    "-File", ".\scripts\powershell\skybridge-verify-cloud-autodeploy.ps1",
    "-Repo", "JerrySkywalker/skybridge-agent-hub",
    "-Commit", $commit,
    "-ApiBase", "http://127.0.0.1:1",
    "-FixtureVersionFile", $versionPath,
    "-Json"
  )
} finally {
  $env:PATH = $oldPath
}
Assert-ExitCode $ghFailure 1 "gh failure"
$ghJson = ConvertFrom-SmokeJson $ghFailure "gh failure"
Assert-Contains $ghJson.error_summary "gh run list failed" "gh failure"
Assert-Contains $ghJson.error_summary "[redacted-url]" "gh failure redaction"
Assert-NotContains $ghJson.error_summary "secret-value" "gh failure redaction"
Assert-NotContains $ghJson.error_summary "abcdefghijklmnopqrstuvwxyz" "gh failure redaction"
if ($ghJson.token_printed -ne $false) { throw "gh failure token_printed was not false." }
$scenarios.Add([pscustomobject]@{ name = "gh_failure_sanitized_diagnostic"; ok = $true }) | Out-Null

$server = Start-FakeSkyBridgeServer -Port (Get-FreeSmokePort) -Mode "parity-fail" -CommitSha $commit -ImageRefValue $imageRef
try {
  $parityFailure = Invoke-PwshCapture @(
    "-File", ".\scripts\powershell\skybridge-verify-cloud-autodeploy.ps1",
    "-Repo", "JerrySkywalker/skybridge-agent-hub",
    "-Commit", $commit,
    "-ApiBase", $server.api_base,
    "-FixtureDockerRunsFile", $dockerPath,
    "-FixtureDeployRunsFile", $deployPath,
    "-FixtureDeployReportFile", $reportPath,
    "-Json"
  )
} finally {
  Stop-Process -Id $server.process.Id -Force -ErrorAction SilentlyContinue
}
Assert-ExitCode $parityFailure 1 "parity failure"
$parityJson = ConvertFrom-SmokeJson $parityFailure "parity failure"
Assert-Contains $parityJson.stage "[7/8] run cloud route parity" "parity failure stage"
Assert-Contains $parityJson.error_summary "skybridge-cloud-parity-check.ps1 failed" "parity failure diagnostic"
if ($parityJson.token_printed -ne $false) { throw "parity failure token_printed was not false." }
$scenarios.Add([pscustomobject]@{ name = "parity_failure_sanitized_diagnostic"; ok = $true }) | Out-Null

$allText = @($placeholder.text, $invalid.text, $wrongService.text, $textVerifier.text, $jsonVerifier.text, $ghFailure.text, $parityFailure.text) -join "`n"
foreach ($unsafe in @("secret-value", "abcdefghijklmnopqrstuvwxyz", "private.example.invalid")) {
  Assert-NotContains $allText $unsafe "aggregate output redaction"
}
Assert-Contains $allText "token_printed" "token_printed=false aggregate"

$result = [pscustomobject]@{
  ok = $true
  schema = "skybridge.api_base_diagnostics_smoke.v1"
  scenario_count = $scenarios.Count
  scenarios = @($scenarios.ToArray())
  token_printed = $false
}

if ($Json) {
  $result | ConvertTo-Json -Depth 8 -Compress
} else {
  "PASS api-base diagnostics smoke"
  "scenario_count=$($result.scenario_count)"
  "token_printed=false"
}
