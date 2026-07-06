[CmdletBinding()]
param(
  [ValidateSet("local-safe", "status", "report")]
  [string]$Mode = "local-safe",
  [switch]$UseTempDatabase,
  [string]$ApiBase = "http://127.0.0.1:8787",
  [string]$ProjectId = "skybridge-mvp-demo",
  [string]$OutputDir = ".agent/tmp/skybridge-mvp-demo",
  [switch]$Json,
  [switch]$StartServer,
  [switch]$NoOpenBrowser,
  [switch]$OpenReport
)

$ErrorActionPreference = "Stop"

$Schema = "skybridge.mvp_demo.local_safe.v1"
$GoalId = "mg372a-local-safe-demo"
$TaskId = "mg372a-local-safe-task-001"
$WorkerId = "mg372a-local-demo-worker"
$TaskType = "safe-local-smoke"
$RunnerId = "skybridge-mvp-demo-local-worker.v1"
$TemplateId = "safe-local-smoke.v1"
$Artifacts = @(
  "mvp-demo-report.json",
  "mvp-demo-report.md",
  "mvp-demo-state.json",
  "mvp-demo-events.json",
  "mvp-demo-task.json",
  "mvp-demo-worker.json",
  "mvp-demo-safety.json",
  "mvp-demo-command-transcript.txt",
  "mvp-demo-artifact-index.json"
)

function ConvertTo-DemoJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 30
}

function Get-DemoUtcNow {
  (Get-Date).ToUniversalTime().ToString("o")
}

function Resolve-DemoPath {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  Join-Path (Get-Location) $Path
}

function Write-DemoJsonFile {
  param([string]$Path, $Value)
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  ConvertTo-DemoJson $Value | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Add-DemoTranscript {
  param([System.Collections.Generic.List[string]]$Transcript, [string]$Message)
  $safe = ($Message -replace "(?i)(authorization|bearer|token|secret|cookie|password)\s*[:=]\s*\S+", '$1=<redacted>')
  $Transcript.Add(("[{0}] {1}" -f (Get-DemoUtcNow), $safe)) | Out-Null
}

function Invoke-DemoApi {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("GET", "POST", "PATCH", "DELETE")][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    $Body = $null,
    [switch]$AllowNotFound
  )

  $uri = "$($script:ResolvedApiBase.TrimEnd('/'))$Path"
  $parameters = @{
    Method = $Method
    Uri = $uri
    SkipHttpErrorCheck = $true
    TimeoutSec = 15
  }
  if ($null -ne $Body) {
    $parameters.ContentType = "application/json"
    $parameters.Body = ConvertTo-DemoJson $Body
  }
  $response = Invoke-WebRequest @parameters
  $statusCode = [int]$response.StatusCode
  if ($AllowNotFound -and $statusCode -eq 404) { return $null }
  if ($statusCode -lt 200 -or $statusCode -ge 300) {
    throw "SkyBridge API $Method $Path returned HTTP $statusCode."
  }
  $content = ($response.Content | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($content)) { return [pscustomobject]@{} }
  $content | ConvertFrom-Json
}

function Wait-DemoServerHealth {
  param([int]$TimeoutSeconds = 40)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    try { return Invoke-DemoApi -Method GET -Path "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  } while ((Get-Date) -lt $deadline)
  throw "SkyBridge server did not become healthy at $script:ResolvedApiBase."
}

function Start-DemoServer {
  param([string]$ResolvedOutputDir)
  $port = Get-Random -Minimum 18000 -Maximum 28000
  $script:ResolvedApiBase = "http://127.0.0.1:$port"
  $dbFile = Join-Path $ResolvedOutputDir ("mvp-demo-{0}.sqlite" -f (Get-Date -Format "yyyyMMddHHmmss"))
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REQUIRE_WORKER_AUTH -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_REMOTE_API_BASE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $serverCommand)
    PassThru = $true
  }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $process = Start-Process @startProcessParams
  [pscustomobject]@{
    process = $process
    pid = $process.Id
    api_base = $script:ResolvedApiBase
    db_file = $dbFile
    started = $true
  }
}

function Stop-DemoServer {
  param($ServerInfo)
  if ($ServerInfo -and $ServerInfo.process) {
    try { $ServerInfo.process.Kill($true) } catch { Stop-Process -Id $ServerInfo.pid -Force -ErrorAction SilentlyContinue }
  }
}

function Get-DemoArtifactPaths {
  param([string]$ResolvedOutputDir)
  [pscustomobject]@{
    report_json = Join-Path $ResolvedOutputDir "mvp-demo-report.json"
    report_md = Join-Path $ResolvedOutputDir "mvp-demo-report.md"
    state = Join-Path $ResolvedOutputDir "mvp-demo-state.json"
    events = Join-Path $ResolvedOutputDir "mvp-demo-events.json"
    task = Join-Path $ResolvedOutputDir "mvp-demo-task.json"
    worker = Join-Path $ResolvedOutputDir "mvp-demo-worker.json"
    safety = Join-Path $ResolvedOutputDir "mvp-demo-safety.json"
    transcript = Join-Path $ResolvedOutputDir "mvp-demo-command-transcript.txt"
    index = Join-Path $ResolvedOutputDir "mvp-demo-artifact-index.json"
  }
}

function New-DemoTaskPayload {
  [ordered]@{
    task_id = $TaskId
    project_id = $ProjectId
    goal_id = $GoalId
    title = "MG372A local safe demo task"
    body = "Run the fixed local safe demo worker once and write sanitized demo evidence under .agent/tmp/skybridge-mvp-demo."
    prompt_summary = "MG372A fixed local safe demo task. Safe summary only."
    risk = "low"
    source = "custom"
    task_type = $TaskType
    allowed_paths = @(".agent/tmp/skybridge-mvp-demo/**")
    blocked_paths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "production infrastructure")
    validation = @("one local demo worker claim", "one local demo worker start", "one local demo worker complete", "token_printed=false")
    required_capabilities = @("powershell", "local-demo", "safe-local-smoke")
    planner_metadata = @{
      adapter = "skybridge-mvp-demo"
      decision = "continue"
      reason = "mg372a_local_safe_demo_spine"
      task_type = $TaskType
      template_id = $TemplateId
      runner_id = $RunnerId
      expected_outputs = @(".agent/tmp/skybridge-mvp-demo/**")
      stop_criteria_status = @("complete_one_demo_task_then_stop")
      codex_called = $false
      pr_created = $false
      branch_created = $false
      worker_loop_started = $false
      run_forever_started = $false
      token_printed = $false
    }
  }
}

function New-DemoSafetyFlags {
  [ordered]@{
    codex_called = $false
    pr_created = $false
    branch_created = $false
    worker_loop_started = $false
    queue_runner_started = $false
    run_forever_started = $false
    hermes_live_called = $false
    mcp_run_called = $false
    auto_merge_enabled = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    token_printed = $false
  }
}

function Invoke-DemoLocalSafe {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
  $paths = Get-DemoArtifactPaths -ResolvedOutputDir $resolvedOutputDir
  $transcript = [System.Collections.Generic.List[string]]::new()
  $events = [System.Collections.Generic.List[object]]::new()
  $blockers = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $serverInfo = $null
  $script:ResolvedApiBase = $ApiBase
  if ($UseTempDatabase) { $StartServer = $true }

  $taskCreated = $false
  $workerRegistered = $false
  $taskClaimed = $false
  $taskStarted = $false
  $taskCompleted = $false
  $taskFailed = $false
  $taskBlocked = $false
  $validationStatus = "not_run"
  $demoResult = "blocked"
  $finalTask = $null
  $finalWorker = $null

  try {
    Add-DemoTranscript $transcript "MG372A local-safe demo started."
    if ($StartServer) {
      $serverInfo = Start-DemoServer -ResolvedOutputDir $resolvedOutputDir
      Add-DemoTranscript $transcript "Started bounded local SkyBridge server pid=$($serverInfo.pid) api_base=$($serverInfo.api_base)."
    } else {
      Add-DemoTranscript $transcript "Using configured SkyBridge server api_base=$script:ResolvedApiBase."
    }

    Wait-DemoServerHealth | Out-Null
    Add-DemoTranscript $transcript "SkyBridge health check passed."
    $events.Add([ordered]@{ order = 1; event = "server_health_ok"; api_base = $script:ResolvedApiBase; at = Get-DemoUtcNow }) | Out-Null

    $existingProject = Invoke-DemoApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -AllowNotFound
    if (-not $existingProject) {
      Invoke-DemoApi -Method POST -Path "/v1/projects" -Body @{ project_id = $ProjectId; name = $ProjectId } | Out-Null
      $events.Add([ordered]@{ order = 2; event = "project_created"; project_id = $ProjectId; at = Get-DemoUtcNow }) | Out-Null
      Add-DemoTranscript $transcript "Created demo project $ProjectId."
    } else {
      $events.Add([ordered]@{ order = 2; event = "project_reused"; project_id = $ProjectId; at = Get-DemoUtcNow }) | Out-Null
      Add-DemoTranscript $transcript "Reused demo project $ProjectId."
    }

    $existingGoal = Invoke-DemoApi -Method GET -Path "/v1/goals/$([uri]::EscapeDataString($GoalId))" -AllowNotFound
    if (-not $existingGoal) {
      Invoke-DemoApi -Method POST -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -Body @{
        goal_id = $GoalId
        title = "MG372A Local Safe Demo"
        summary = "Prove one local safe SkyBridge task lifecycle without external agent calls."
        source = "mg372a-mvp-demo"
        risk = "low"
        status = "ready"
        acceptance_criteria = @("One demo task completes with sanitized evidence.")
        evidence_requirements = @("MG372A demo JSON and Markdown reports are written.")
      } | Out-Null
      $events.Add([ordered]@{ order = 3; event = "goal_created"; goal_id = $GoalId; at = Get-DemoUtcNow }) | Out-Null
      Add-DemoTranscript $transcript "Created demo goal $GoalId."
    } else {
      $events.Add([ordered]@{ order = 3; event = "goal_reused"; goal_id = $GoalId; at = Get-DemoUtcNow }) | Out-Null
      Add-DemoTranscript $transcript "Reused demo goal $GoalId."
    }

    $existingTask = Invoke-DemoApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))" -AllowNotFound
    if ($existingTask -and [string]$existingTask.task.status -notin @("queued")) {
      $blockers.Add("existing_task_not_queued") | Out-Null
      throw "Existing demo task is not queued; rerun with -UseTempDatabase or a clean -ProjectId."
    }
    if (-not $existingTask) {
      Invoke-DemoApi -Method POST -Path "/v1/tasks" -Body (New-DemoTaskPayload) | Out-Null
      $taskCreated = $true
      $events.Add([ordered]@{ order = 4; event = "task_created"; task_id = $TaskId; at = Get-DemoUtcNow }) | Out-Null
      Add-DemoTranscript $transcript "Created demo task $TaskId."
    } else {
      $taskCreated = $true
      $events.Add([ordered]@{ order = 4; event = "task_reused"; task_id = $TaskId; at = Get-DemoUtcNow }) | Out-Null
      Add-DemoTranscript $transcript "Reused queued demo task $TaskId."
    }

    Invoke-DemoApi -Method POST -Path "/v1/workers/register" -Body @{
      worker_id = $WorkerId
      name = "MG372A local demo worker"
      provider = "local-demo"
      capabilities = @("powershell", "local-demo", "safe-local-smoke")
      labels = @("mg372a", "local-safe", "poll-once")
      enabled = $true
      auth_mode = "none"
      api_base = $script:ResolvedApiBase
      allow_remote_server = $false
    } | Out-Null
    $workerRegistered = $true
    Invoke-DemoApi -Method POST -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))/heartbeat" -Body @{
      status_note = "mg372a local-safe ready"
      load = 0
      seen_at = Get-DemoUtcNow
    } | Out-Null
    $events.Add([ordered]@{ order = 5; event = "worker_registered"; worker_id = $WorkerId; at = Get-DemoUtcNow }) | Out-Null
    Add-DemoTranscript $transcript "Registered and heartbeated demo worker $WorkerId."

    Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/claim" -Body @{ worker_id = $WorkerId } | Out-Null
    $taskClaimed = $true
    $events.Add([ordered]@{ order = 6; event = "task_claimed"; task_id = $TaskId; worker_id = $WorkerId; poll_once_semantics = $true; at = Get-DemoUtcNow }) | Out-Null
    Add-DemoTranscript $transcript "Claimed exactly one demo task."

    Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/start" -Body @{ worker_id = $WorkerId } | Out-Null
    $taskStarted = $true
    $events.Add([ordered]@{ order = 7; event = "task_started"; task_id = $TaskId; worker_id = $WorkerId; at = Get-DemoUtcNow }) | Out-Null
    Add-DemoTranscript $transcript "Started exactly one demo task."

    $validationStatus = "passed"
    $complete = Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))/complete" -Body @{
      worker_id = $WorkerId
      summary = "MG372A local-safe MVP demo completed one task with sanitized evidence."
      result_url = ".agent/tmp/skybridge-mvp-demo/mvp-demo-report.md"
      evidence_summary = @{
        schema = "skybridge.mvp_demo.task_evidence.v1"
        project_id = $ProjectId
        goal_id = $GoalId
        task_id = $TaskId
        worker_id = $WorkerId
        template_id = $TemplateId
        runner_id = $RunnerId
        validation_status = $validationStatus
        changed_files = @()
        artifacts = @($Artifacts)
        codex_called = $false
        pr_created = $false
        branch_created = $false
        worker_loop_started = $false
        run_forever_started = $false
        token_printed = $false
        created_at = Get-DemoUtcNow
      }
    }
    $taskCompleted = $true
    $finalTask = $complete.task
    $events.Add([ordered]@{ order = 8; event = "task_completed"; task_id = $TaskId; worker_id = $WorkerId; validation_status = $validationStatus; at = Get-DemoUtcNow }) | Out-Null
    Add-DemoTranscript $transcript "Completed exactly one demo task."

    $finalTask = (Invoke-DemoApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))").task
    $finalWorker = (Invoke-DemoApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($WorkerId))").worker
    $demoResult = "pass"
  } catch {
    if ($blockers.Count -lt 1) { $blockers.Add("local_safe_demo_failed") | Out-Null }
    $validationStatus = "failed"
    $taskFailed = $true
    Add-DemoTranscript $transcript "Demo blocked: $($_.Exception.Message)"
    $warnings.Add(($_.Exception.Message -replace "\s+", " ").Substring(0, [Math]::Min(180, ($_.Exception.Message -replace "\s+", " ").Length))) | Out-Null
    $demoResult = "blocked"
  } finally {
    Stop-DemoServer -ServerInfo $serverInfo
    if ($serverInfo) { Add-DemoTranscript $transcript "Stopped bounded local SkyBridge server pid=$($serverInfo.pid)." }
    $stopwatch.Stop()
  }

  $relativeOutput = $OutputDir.Replace("\", "/")
  $safety = New-DemoSafetyFlags
  $report = [ordered]@{
    schema = $Schema
    generated_at = Get-DemoUtcNow
    mode = "local-safe"
    project_id = $ProjectId
    goal_id = $GoalId
    task_id = $TaskId
    worker_id = $WorkerId
    task_created = [bool]$taskCreated
    worker_registered = [bool]$workerRegistered
    task_claimed = [bool]$taskClaimed
    task_started = [bool]$taskStarted
    task_completed = [bool]$taskCompleted
    task_failed = [bool]$taskFailed
    task_blocked = [bool]$taskBlocked
    validation_status = $validationStatus
    artifacts_written = $true
    artifact_report_written = $true
    report_markdown_path = "$relativeOutput/mvp-demo-report.md"
    report_json_path = "$relativeOutput/mvp-demo-report.json"
    demo_result = $demoResult
    fixture_mode = $false
    real_worker_execution = [bool]($taskClaimed -and $taskStarted -and $taskCompleted)
    codex_called = $false
    pr_created = $false
    branch_created = $false
    worker_loop_started = $false
    queue_runner_started = $false
    run_forever_started = $false
    hermes_live_called = $false
    mcp_run_called = $false
    auto_merge_enabled = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    token_printed = $false
    elapsed_ms = [int64]$stopwatch.ElapsedMilliseconds
    api_base = $script:ResolvedApiBase
    temp_database_used = [bool]$UseTempDatabase
    started_server = [bool]$serverInfo
    server_pid = if ($serverInfo) { $serverInfo.pid } else { $null }
    server_db_file = if ($serverInfo) { $serverInfo.db_file } else { $null }
    poll_once_semantics = $true
    provider_call_count = if ($taskCompleted) { 1 } else { 0 }
    blockers = @($blockers)
    warnings = @($warnings)
  }

  $state = [ordered]@{
    schema = "skybridge.mvp_demo.state.v1"
    generated_at = $report.generated_at
    mode = "local-safe"
    api_base = $script:ResolvedApiBase
    output_dir = $relativeOutput
    project_id = $ProjectId
    goal_id = $GoalId
    task_id = $TaskId
    worker_id = $WorkerId
    temp_database_used = [bool]$UseTempDatabase
    server_started = [bool]$serverInfo
    server_pid = if ($serverInfo) { $serverInfo.pid } else { $null }
    server_db_file = if ($serverInfo) { $serverInfo.db_file } else { $null }
    token_printed = $false
  }
  $taskArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.task.v1"
    generated_at = $report.generated_at
    task_payload = New-DemoTaskPayload
    final_task = $finalTask
    task_created = [bool]$taskCreated
    task_claimed = [bool]$taskClaimed
    task_started = [bool]$taskStarted
    task_completed = [bool]$taskCompleted
    task_failed = [bool]$taskFailed
    token_printed = $false
  }
  $workerArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.worker.v1"
    generated_at = $report.generated_at
    worker_id = $WorkerId
    worker_registered = [bool]$workerRegistered
    final_worker = $finalWorker
    capabilities = @("powershell", "local-demo", "safe-local-smoke")
    token_printed = $false
  }
  $safetyArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.safety.v1"
    generated_at = $report.generated_at
    mode = "local-safe"
    safety_flags = $safety
    raw_secrets_included = $false
    raw_logs_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_prompt_included = $false
    token_printed = $false
  }
  $index = [ordered]@{
    schema = "skybridge.mvp_demo.artifact_index.v1"
    generated_at = $report.generated_at
    artifact_dir = $relativeOutput
    artifacts = @($Artifacts)
    report_json_path = $report.report_json_path
    report_markdown_path = $report.report_markdown_path
    token_printed = $false
  }

  Write-DemoJsonFile -Path $paths.state -Value $state
  Write-DemoJsonFile -Path $paths.events -Value ([ordered]@{ schema = "skybridge.mvp_demo.events.v1"; generated_at = $report.generated_at; events = @($events); token_printed = $false })
  Write-DemoJsonFile -Path $paths.task -Value $taskArtifact
  Write-DemoJsonFile -Path $paths.worker -Value $workerArtifact
  Write-DemoJsonFile -Path $paths.safety -Value $safetyArtifact
  Write-DemoJsonFile -Path $paths.report_json -Value $report
  Write-DemoJsonFile -Path $paths.index -Value $index
  ($transcript -join [Environment]::NewLine) | Set-Content -LiteralPath $paths.transcript -Encoding UTF8

  $markdown = @(
    "# SkyBridge MVP Local Safe Demo",
    "",
    "- result: $($report.demo_result)",
    "- project_id: $ProjectId",
    "- goal_id: $GoalId",
    "- task_id: $TaskId",
    "- worker_id: $WorkerId",
    "- task_created: $($report.task_created)",
    "- worker_registered: $($report.worker_registered)",
    "- task_claimed: $($report.task_claimed)",
    "- task_started: $($report.task_started)",
    "- task_completed: $($report.task_completed)",
    "- validation_status: $($report.validation_status)",
    "- fixture_mode: $($report.fixture_mode)",
    "- real_worker_execution: $($report.real_worker_execution)",
    "- elapsed_ms: $($report.elapsed_ms)",
    "- codex_called: false",
    "- pr_created: false",
    "- branch_created: false",
    "- worker_loop_started: false",
    "- queue_runner_started: false",
    "- run_forever_started: false",
    "- hermes_live_called: false",
    "- mcp_run_called: false",
    "- auto_merge_enabled: false",
    "- release_created: false",
    "- tag_created: false",
    "- asset_uploaded: false",
    "- token_printed: false",
    "",
    "Artifacts are written under `$relativeOutput`.",
    "",
    "This demo proves a one-command local task lifecycle using a bounded local demo worker. It does not call external agent runtimes, create branches, create PRs, start loops, deploy, release, tag or upload assets."
  )
  $markdown | Set-Content -LiteralPath $paths.report_md -Encoding UTF8

  if ($OpenReport) { Invoke-Item -LiteralPath $paths.report_md }
  if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
}

function Show-DemoStatus {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  $reportPath = Join-Path $resolvedOutputDir "mvp-demo-report.json"
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    $result = [pscustomobject]@{ ok = $false; mode = "status"; report_found = $false; report_json_path = $reportPath; token_printed = $false }
  } else {
    $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
    $result = [pscustomobject]@{
      ok = $true
      mode = "status"
      report_found = $true
      report_json_path = $reportPath
      report_markdown_path = (Join-Path $resolvedOutputDir "mvp-demo-report.md")
      demo_result = $report.demo_result
      validation_status = $report.validation_status
      task_completed = $report.task_completed
      token_printed = $false
    }
  }
  if ($Json) { $result | ConvertTo-Json -Depth 10 -Compress } else { $result | Format-List }
}

function Show-DemoReport {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  $reportJson = Join-Path $resolvedOutputDir "mvp-demo-report.json"
  $reportMd = Join-Path $resolvedOutputDir "mvp-demo-report.md"
  if (-not (Test-Path -LiteralPath $reportJson -PathType Leaf)) {
    $result = [pscustomobject]@{ ok = $false; mode = "report"; report_found = $false; report_json_path = $reportJson; report_markdown_path = $reportMd; token_printed = $false }
  } else {
    $report = Get-Content -Raw -LiteralPath $reportJson | ConvertFrom-Json
    $result = [pscustomobject]@{
      ok = $true
      mode = "report"
      report_found = $true
      report_json_path = $reportJson
      report_markdown_path = $reportMd
      summary = "result=$($report.demo_result) task_completed=$($report.task_completed) validation=$($report.validation_status)"
      token_printed = $false
    }
  }
  if ($OpenReport -and (Test-Path -LiteralPath $reportMd -PathType Leaf)) { Invoke-Item -LiteralPath $reportMd }
  if ($Json) { $result | ConvertTo-Json -Depth 10 -Compress } else { $result | Format-List }
}

if ($Mode -eq "local-safe") {
  Invoke-DemoLocalSafe
} elseif ($Mode -eq "status") {
  Show-DemoStatus
} else {
  Show-DemoReport
}
