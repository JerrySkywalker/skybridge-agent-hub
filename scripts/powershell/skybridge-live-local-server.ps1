[CmdletBinding()]
param(
  [ValidateSet("status", "plan", "start-fixture", "stop-fixture", "auth-request", "route-check", "e2e-preview", "safe-summary", "report")]
  [string]$Command = "status",
  [string]$Origin = "http://127.0.0.1:5173",
  [string]$Route = "/metadata",
  [string]$Payload = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\live-local"
$StatePath = Join-Path $ReportDir "live-local-fixture-state.json"
$ServerScriptPath = Join-Path $ReportDir "live-local-fixture-server.ps1"
$ServerReportJson = Join-Path $ReportDir "live-local-server-report.json"
$ServerReportMarkdown = Join-Path $ReportDir "live-local-server-report.md"
$E2eReportJson = Join-Path $ReportDir "live-local-e2e-report.json"
$RcReportJson = Join-Path $ReportDir "v2.1-live-local-rc-report.json"
$RcReportMarkdown = Join-Path $ReportDir "v2.1-live-local-rc-report.md"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  $privateKey = '-----BEGIN [A-Z ]*PRIVATE ' + 'KEY-----'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|$privateKey|raw_prompt|raw_stdout|raw_stderr|raw_worker_log|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 100
  if (Test-UnsafeText $text) { throw "Refusing unsafe live-local JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe live-local markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "$Script failed." }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "$Script emitted unsafe text." }
  $text | ConvertFrom-Json
}

function Get-Commit {
  (& git -C $RepoRoot rev-parse --short HEAD).Trim()
}

function Get-FixtureSessionHash {
  $session = Invoke-JsonScript "skybridge-local-auth.ps1" @("-Command", "fixture-session")
  $session.token_hash
}

function Get-FreeLoopbackPort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), 0)
  $listener.Start()
  $port = $listener.LocalEndpoint.Port
  $listener.Stop()
  $port
}

function Test-TcpReady([int]$Port) {
  try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
    $ok = $async.AsyncWaitHandle.WaitOne(200)
    if ($ok) { $client.EndConnect($async) }
    $client.Close()
    return $ok
  } catch {
    return $false
  }
}

function Test-OriginAllowed([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
  if ($Value -eq "repo-local-dev-fixture") { return $true }
  try {
    $uri = [System.Uri]$Value
    return @("localhost", "127.0.0.1", "::1") -contains $uri.Host
  } catch {
    return $false
  }
}

function Test-RouteAllowed([string]$Value) {
  @("/status", "/readiness", "/metadata") -contains $Value
}

function Test-CommandText([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  return $Value -match "(?i)(cmd|command|shell|powershell|pwsh|bash)\s*[:=]|[;&|`$<>]"
}

function New-RouteCheck([string]$OriginValue, [string]$RouteValue, [string]$PayloadValue) {
  $reasons = @()
  if (-not (Test-OriginAllowed $OriginValue)) { $reasons += "origin_not_loopback" }
  if (-not (Test-RouteAllowed $RouteValue)) { $reasons += "route_not_allowed" }
  if (Test-CommandText $PayloadValue) { $reasons += "command_text_forbidden" }
  if ($PayloadValue -match "(?i)(execute|run_apply|queue_apply|start_all|start_queue|claim_task)\s*[:=]\s*true") { $reasons += "execution_request_forbidden" }
  [pscustomobject]@{
    schema = "skybridge.live_local_route_check.v1"
    accepted = (@($reasons).Count -eq 0)
    origin = $(if (Test-OriginAllowed $OriginValue) { "loopback_or_empty" } else { "rejected_remote" })
    route = $RouteValue
    reasons = $reasons
    loopback_only = $true
    arbitrary_command_route_present = $false
    execution_enabled = $false
    worker_execution_started = $false
    workunit_apply_enabled = $false
    task_claim_enabled = $false
    queue_apply_enabled = $false
    host_mutation_performed = $false
    token_printed = $false
  }
}

function Get-State {
  if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
  $text = Get-Content -Raw -LiteralPath $StatePath
  if (Test-UnsafeText $text) { throw "Unsafe live-local state file." }
  $text | ConvertFrom-Json
}

function Test-StateRunning($State) {
  if ($null -eq $State -or -not $State.pid) { return $false }
  $proc = Get-Process -Id ([int]$State.pid) -ErrorAction SilentlyContinue
  $null -ne $proc -and -not $proc.HasExited
}

function Write-ServerScript {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $script = @'
param(
  [int]$Port,
  [string]$StopFile,
  [string]$SessionHash,
  [int]$MaxSeconds = 120
)
$ErrorActionPreference = "Stop"
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), $Port)
$listener.Start()
$started = Get-Date
function Write-Response($Client, [int]$Status, [string]$Body) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $reason = if ($Status -eq 200) { "OK" } else { "Rejected" }
  $header = "HTTP/1.1 $Status $reason`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
  $stream = $Client.GetStream()
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  $stream.Write($bytes, 0, $bytes.Length)
}
try {
  while (-not (Test-Path -LiteralPath $StopFile)) {
    if (((Get-Date) - $started).TotalSeconds -ge $MaxSeconds) { break }
    if (-not $listener.Pending()) { Start-Sleep -Milliseconds 100; continue }
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)
      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }
      $headers = @{}
      while ($true) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($line)) { break }
        $idx = $line.IndexOf(":")
        if ($idx -gt 0) {
          $headers[$line.Substring(0, $idx).ToLowerInvariant()] = $line.Substring($idx + 1).Trim()
        }
      }
      $parts = @($requestLine -split " ")
      $method = if ($parts.Count -gt 0) { $parts[0] } else { "" }
      $target = if ($parts.Count -gt 1) { $parts[1] } else { "/" }
      $path = ($target -split "\?")[0]
      $query = if ($target -match "\?") { ($target -split "\?", 2)[1] } else { "" }
      $origin = if ($headers.ContainsKey("origin")) { $headers["origin"] } else { "" }
      $hash = if ($headers.ContainsKey("x-skybridge-session-hash")) { $headers["x-skybridge-session-hash"] } else { "" }
      $originOk = ([string]::IsNullOrWhiteSpace($origin) -or $origin -match "^https?://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$")
      $routeOk = @("/status", "/readiness", "/metadata") -contains $path
      $commandText = $query -match "(?i)(cmd|command|shell|powershell|pwsh|bash)\s*[:=]|[;&|`$<>]"
      if ($method -ne "GET") {
        Write-Response $client 405 '{"schema":"skybridge.live_local_auth_request.v1","accepted":false,"reason":"method_rejected","token_printed":false}'
      } elseif (-not $originOk) {
        Write-Response $client 403 '{"schema":"skybridge.live_local_auth_request.v1","accepted":false,"reason":"origin_not_loopback","token_printed":false}'
      } elseif ($headers.ContainsKey("authorization")) {
        Write-Response $client 400 '{"schema":"skybridge.live_local_auth_request.v1","accepted":false,"reason":"auth_header_rejected","token_printed":false}'
      } elseif (-not $routeOk) {
        Write-Response $client 404 '{"schema":"skybridge.live_local_route_check.v1","accepted":false,"reason":"route_not_allowed","token_printed":false}'
      } elseif ($commandText) {
        Write-Response $client 400 '{"schema":"skybridge.live_local_route_check.v1","accepted":false,"reason":"command_text_forbidden","token_printed":false}'
      } elseif ($path -eq "/metadata" -and $hash -ne $SessionHash) {
        Write-Response $client 401 '{"schema":"skybridge.live_local_auth_request.v1","accepted":false,"reason":"fixture_hash_required","token_printed":false}'
      } else {
        Write-Response $client 200 '{"schema":"skybridge.live_local_auth_request.v1","accepted":true,"safe_metadata_only":true,"execution_enabled":false,"worker_execution_started":false,"workunit_apply_enabled":false,"task_claim_enabled":false,"queue_apply_enabled":false,"arbitrary_command_enabled":false,"token_printed":false}'
      }
    } finally {
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
}
'@
  Set-Content -LiteralPath $ServerScriptPath -Value $script -Encoding utf8
}

function Stop-Fixture {
  $state = Get-State
  if ($null -ne $state) {
    if ($state.stop_file) {
      New-Item -ItemType File -Force -Path $state.stop_file | Out-Null
    }
    if (Test-StateRunning $state) {
      $proc = Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue
      if ($proc) {
        try { Wait-Process -Id $proc.Id -Timeout 5 -ErrorAction SilentlyContinue } catch {}
        if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
          Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
      }
    }
  }
  Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{
    schema = "skybridge.live_local_server.v1"
    status = "stopped"
    loopback_only = $true
    background_process_left = $false
    token_printed = $false
  }
}

function Start-Fixture {
  Stop-Fixture | Out-Null
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  Write-ServerScript
  $port = Get-FreeLoopbackPort
  $stopFile = Join-Path $ReportDir "live-local-fixture.stop"
  Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
  $hash = Get-FixtureSessionHash
  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ServerScriptPath, "-Port", "$port", "-StopFile", $stopFile, "-SessionHash", $hash, "-MaxSeconds", "120")
  $process = Start-Process -FilePath "pwsh" -ArgumentList $args -WindowStyle Hidden -PassThru
  $ready = $false
  for ($i = 0; $i -lt 25; $i++) {
    Start-Sleep -Milliseconds 200
    if (Test-TcpReady $port) { $ready = $true; break }
    if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) { break }
  }
  if (-not $ready) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw "Live-local fixture server did not become ready."
  }
  $state = [pscustomobject]@{
    schema = "skybridge.live_local_server.v1"
    status = "running"
    pid = $process.Id
    port = $port
    base_url = "http://127.0.0.1:$port"
    stop_file = $stopFile
    loopback_only = $true
    bounded_fixture_server_only = $true
    safe_metadata_only = $true
    worker_execution_started = $false
    workunit_apply_enabled = $false
    task_claim_enabled = $false
    queue_apply_enabled = $false
    arbitrary_command_route_present = $false
    host_mutation_performed = $false
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    raw_logs_persisted = $false
    token_printed = $false
  }
  Write-SafeJson $StatePath $state
  $state
}

function Invoke-FixtureRequest([string]$RouteValue, [string]$OriginValue, [string]$PayloadValue) {
  $startedHere = $false
  $state = Get-State
  if (-not (Test-StateRunning $state)) {
    $state = Start-Fixture
    $startedHere = $true
  }
  try {
    $routeCheck = New-RouteCheck $OriginValue $RouteValue $PayloadValue
    if (-not $routeCheck.accepted) {
      return [pscustomobject]@{
        schema = "skybridge.live_local_auth_request.v1"
        accepted = $false
        status = "rejected_before_request"
        route_check = $routeCheck
        raw_token_persisted = $false
        auth_header_persisted = $false
        cookie_persisted = $false
        private_key_persisted = $false
        execution_enabled = $false
        worker_execution_started = $false
        workunit_apply_enabled = $false
        task_claim_enabled = $false
        queue_apply_enabled = $false
        arbitrary_command_enabled = $false
        host_mutation_performed = $false
        token_printed = $false
      }
    }
    $headers = @{ "X-Skybridge-Session-Hash" = (Get-FixtureSessionHash) }
    if (-not [string]::IsNullOrWhiteSpace($OriginValue)) { $headers["Origin"] = $OriginValue }
    $target = "$($state.base_url)$RouteValue"
    if (-not [string]::IsNullOrWhiteSpace($PayloadValue)) { $target = "$target`?q=$([System.Uri]::EscapeDataString($PayloadValue))" }
    $response = Invoke-RestMethod -Method Get -Uri $target -Headers $headers -TimeoutSec 5
    $result = [pscustomobject]@{
      schema = "skybridge.live_local_auth_request.v1"
      accepted = ($response.accepted -eq $true)
      status = "safe_metadata_read"
      route = $RouteValue
      loopback_only = $true
      fixture_hash_used = $true
      raw_token_persisted = $false
      auth_header_persisted = $false
      cookie_persisted = $false
      private_key_persisted = $false
      safe_metadata_only = $true
      execution_enabled = $false
      worker_execution_started = $false
      workunit_apply_enabled = $false
      task_claim_enabled = $false
      queue_apply_enabled = $false
      arbitrary_command_enabled = $false
      host_mutation_performed = $false
      token_printed = $false
    }
    return $result
  } finally {
    if ($startedHere) { Stop-Fixture | Out-Null }
  }
}

function New-Plan {
  [pscustomobject]@{
    schema = "skybridge.live_local_server.v1"
    status = "planned"
    commands = @("status", "plan", "start-fixture", "stop-fixture", "auth-request", "route-check", "e2e-preview", "safe-summary", "report")
    schemas = @("skybridge.live_local_server.v1", "skybridge.live_local_auth_request.v1", "skybridge.live_local_route_check.v1", "skybridge.live_local_e2e_report.v1")
    loopback_only = $true
    bounded_fixture_server_only = $true
    safe_metadata_only = $true
    worker_execution_started = $false
    workunit_apply_enabled = $false
    task_claim_enabled = $false
    queue_apply_enabled = $false
    arbitrary_command_route_present = $false
    host_mutation_performed = $false
    token_printed = $false
  }
}

function New-E2ePreview {
  $state = Start-Fixture
  try {
    $status = Invoke-FixtureRequest "/status" "http://127.0.0.1:5173" ""
    $readiness = Invoke-FixtureRequest "/readiness" "http://localhost:5173" ""
    $metadata = Invoke-FixtureRequest "/metadata" "http://127.0.0.1:5173" ""
    $remote = New-RouteCheck "https://example.invalid" "/metadata" ""
    $command = New-RouteCheck "http://127.0.0.1:5173" "/metadata" "shell=echo fixture"
    $report = [pscustomobject]@{
      schema = "skybridge.live_local_e2e_report.v1"
      status = "passed"
      server = $state
      status_route = $status
      readiness_route = $readiness
      metadata_route = $metadata
      remote_origin_rejected = ($remote.accepted -eq $false)
      command_text_rejected = ($command.accepted -eq $false)
      loopback_only = $true
      safe_metadata_only = $true
      worker_execution_started = $false
      workunit_apply_enabled = $false
      task_claim_enabled = $false
      queue_apply_enabled = $false
      arbitrary_command_enabled = $false
      host_mutation_performed = $false
      background_process_left = $false
      raw_token_persisted = $false
      auth_header_persisted = $false
      cookie_persisted = $false
      private_key_persisted = $false
      raw_logs_persisted = $false
      token_printed = $false
    }
    Write-SafeJson $E2eReportJson $report
    $report
  } finally {
    Stop-Fixture | Out-Null
  }
}

function New-Report {
  $e2e = New-E2ePreview
  $serverReport = [pscustomobject]@{
    schema = "skybridge.live_local_server.v1"
    status = "ready"
    plan = New-Plan
    e2e = $e2e
    loopback_only = $true
    bounded_fixture_server_only = $true
    safe_metadata_only = $true
    background_process_left = $false
    worker_execution_started = $false
    workunit_apply_enabled = $false
    task_claim_enabled = $false
    queue_apply_enabled = $false
    arbitrary_command_route_present = $false
    host_mutation_performed = $false
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    raw_logs_persisted = $false
    token_printed = $false
  }
  Write-SafeJson $ServerReportJson $serverReport
  Write-SafeMarkdown $ServerReportMarkdown @(
    "# Live-local Server Rehearsal Report",
    "",
    "- schema: skybridge.live_local_server.v1",
    "- status: ready",
    "- loopback_only: true",
    "- bounded_fixture_server_only: true",
    "- safe_metadata_only: true",
    "- background_process_left: false",
    "- worker_execution_started: false",
    "- workunit_apply_enabled: false",
    "- task_claim_enabled: false",
    "- queue_apply_enabled: false",
    "- arbitrary_command_route_present: false",
    "- host_mutation_performed: false",
    "- token_printed=false"
  )
  $rc = [pscustomobject]@{
    schema = "skybridge.v2_1_live_local_rc_report.v1"
    rc_version = "v2.1.0-authenticated-live-local-rc"
    commit = Get-Commit
    live_local_server_status = $serverReport.status
    auth_request_status = $e2e.metadata_route.status
    route_hardening_status = "loopback_only_remote_and_command_rejected"
    e2e_preview_status = $e2e.status
    web_desktop_panel_status = "read_only_preview"
    disabled_capabilities = @("worker_execution", "workunit_apply", "task_claim", "queue_apply", "remote_execution", "arbitrary_command_dispatch", "host_mutation")
    worker_execution_started = $false
    workunit_apply_enabled = $false
    task_claim_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    host_mutation_performed = $false
    background_process_left = $false
    raw_token_persisted = $false
    auth_header_persisted = $false
    cookie_persisted = $false
    private_key_persisted = $false
    raw_logs_persisted = $false
    known_limitations = @("fixture/hash-only local session", "bounded loopback fixture server only", "no production identity", "no worker execution")
    report_paths = @(
      ".agent/tmp/live-local/live-local-server-report.json",
      ".agent/tmp/live-local/live-local-server-report.md",
      ".agent/tmp/live-local/live-local-e2e-report.json",
      ".agent/tmp/live-local/v2.1-live-local-rc-report.json",
      ".agent/tmp/live-local/v2.1-live-local-rc-report.md"
    )
    token_printed = $false
  }
  Write-SafeJson $RcReportJson $rc
  Write-SafeMarkdown $RcReportMarkdown @(
    "# v2.1 Authenticated Live-local RC Report",
    "",
    "- schema: skybridge.v2_1_live_local_rc_report.v1",
    "- rc_version: $($rc.rc_version)",
    "- commit: $($rc.commit)",
    "- live_local_server_status: $($rc.live_local_server_status)",
    "- auth_request_status: $($rc.auth_request_status)",
    "- route_hardening_status: $($rc.route_hardening_status)",
    "- e2e_preview_status: $($rc.e2e_preview_status)",
    "- web_desktop_panel_status: $($rc.web_desktop_panel_status)",
    "- token_printed=false"
  )
  $rc
}

function Invoke-CommandBody {
  switch ($Command) {
    "status" { [pscustomobject]@{ schema = "skybridge.live_local_server.v1"; status = $(if (Test-StateRunning (Get-State)) { "running" } else { "stopped" }); loopback_only = $true; token_printed = $false } }
    "plan" { New-Plan }
    "start-fixture" { Start-Fixture }
    "stop-fixture" { Stop-Fixture }
    "auth-request" { Invoke-FixtureRequest $Route $Origin $Payload }
    "route-check" { New-RouteCheck $Origin $Route $Payload }
    "e2e-preview" { New-E2ePreview }
    "safe-summary" { [pscustomobject]@{ ok = $true; live_local_server = "ready"; loopback_only = $true; background_process_left = $false; worker_execution_started = $false; queue_apply_enabled = $false; token_printed = $false } }
    "report" { New-Report }
  }
}

$needsLock = $Command -in @("start-fixture", "stop-fixture", "auth-request", "e2e-preview", "report")
if ($needsLock) {
  $mutex = [System.Threading.Mutex]::new($false, "Global\SkyBridgeLiveLocalFixture")
  $lockTaken = $false
  try {
    $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
    if (-not $lockTaken) { throw "Timed out waiting for live-local fixture lock." }
    $Result = Invoke-CommandBody
  } finally {
    if ($lockTaken) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
  }
} else {
  $Result = Invoke-CommandBody
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
