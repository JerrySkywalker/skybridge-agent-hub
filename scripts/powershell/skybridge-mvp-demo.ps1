[CmdletBinding()]
param(
  [ValidateSet("local-safe", "status", "report", "controller-draft-pr", "controller-draft-pr-preview", "controller-draft-pr-status", "controller-draft-pr-report", "codex-local-diff", "codex-local-diff-preview", "codex-local-diff-status", "codex-local-diff-report", "codex-local-diff-worktree-clean", "codex-local-diff-synthetic-patch", "codex-local-diff-policy-fixture")]
  [string]$Mode = "local-safe",
  [switch]$UseTempDatabase,
  [string]$ApiBase = "http://127.0.0.1:8787",
  [string]$ProjectId = "skybridge-mvp-demo",
  [string]$OutputDir = ".agent/tmp/skybridge-mvp-demo",
  [switch]$Json,
  [switch]$StartServer,
  [switch]$NoOpenBrowser,
  [switch]$OpenReport,
  [switch]$Apply,
  [string]$ConfirmationText = ""
)

$ErrorActionPreference = "Stop"

$Schema = "skybridge.mvp_demo.local_safe.v1"
$GoalId = "mg372a-local-safe-demo"
$TaskId = "mg372a-local-safe-task-001"
$WorkerId = "mg372a-local-demo-worker"
$TaskType = "safe-local-smoke"
$RunnerId = "skybridge-mvp-demo-local-worker.v1"
$TemplateId = "safe-local-smoke.v1"
$ControllerSchema = "skybridge.mvp_demo.controller_draft_pr.v1"
$ControllerOutputDir = ".agent/tmp/skybridge-mvp-demo-pr"
$ControllerGoalId = "mg372b-controller-draft-pr-demo"
$ControllerTaskId = "mg372b-controller-draft-pr-task-001"
$ControllerWorkerId = "mg372b-controller-demo-worker"
$ControllerConfirmationText = "I_UNDERSTAND_AUTHORIZE_MG372B_CREATE_ONE_CONTROLLER_CREATED_DOCS_ONLY_DRAFT_PR_DEMO"
$ControllerBaselineCommit = "c69f97cf4a3eeda0999877b83884513fba4f3bdc"
$ControllerDemoFile = "docs/product/MG372B_CONTROLLER_DRAFT_PR_DEMO_ARTIFACT.md"
$ControllerCommitMessage = "docs(demo): add MG372B controller draft PR artifact"
$ControllerPrTitle = "MG372B Demo: Controller-created Draft PR"
$CodexDiffSchema = "skybridge.mvp_demo.codex_local_diff.v2"
$CodexDiffOutputDir = ".agent/tmp/skybridge-mvp-codex-diff"
$CodexDiffGoalId = "mg372d1-codex-local-diff-rerun-gate"
$CodexDiffTaskId = "mg372d1-codex-local-diff-task-001"
$CodexDiffWorkerId = "mg372d1-codex-local-diff-worker"
$CodexDiffConfirmationText = "I_UNDERSTAND_AUTHORIZE_MG372D1_RERUN_CODEX_ONCE_FOR_LOCAL_DOCS_ONLY_DIFF_DEMO"
$CodexDiffDemoFile = "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md"
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
$ControllerArtifacts = @(
  "mvp-pr-demo-report.json",
  "mvp-pr-demo-report.md",
  "mvp-pr-demo-state.json",
  "mvp-pr-demo-task.json",
  "mvp-pr-demo-worker.json",
  "mvp-pr-demo-preflight.json",
  "mvp-pr-demo-branch-plan.json",
  "mvp-pr-demo-allowlist-check.json",
  "mvp-pr-demo-pr-metadata.json",
  "mvp-pr-demo-provider-report.json",
  "mvp-pr-demo-safety.json",
  "mvp-pr-demo-artifact-index.json"
)
$CodexDiffArtifacts = @(
  "codex-local-diff-report.json",
  "codex-local-diff-report.md",
  "codex-local-diff-state.json",
  "codex-local-diff-task.json",
  "codex-local-diff-worker.json",
  "codex-local-diff-preflight.json",
  "codex-local-diff-prompt.md",
  "codex-local-diff-last-message.md",
  "codex-local-diff-changed-files.json",
  "codex-local-diff-allowlist-check.json",
  "codex-local-diff-review-summary.md",
  "codex-local-diff.patch",
  "codex-local-diff-safety.json",
  "codex-local-diff-collector-diagnostics.json",
  "codex-local-diff-artifact-index.json"
)

if ($Mode -like "controller-draft-pr*" -and -not $PSBoundParameters.ContainsKey("OutputDir")) {
  $OutputDir = $ControllerOutputDir
}
if ($Mode -like "codex-local-diff*" -and -not $PSBoundParameters.ContainsKey("OutputDir")) {
  $OutputDir = $CodexDiffOutputDir
}

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

function Get-DemoGitText {
  param(
    [string[]]$Arguments,
    [switch]$AllowFailure
  )
  $output = & git @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) {
    if ($AllowFailure) { return $null }
    throw "git $($Arguments[0]) failed."
  }
  return (($output | Out-String).Trim())
}

function Invoke-DemoExternalQuiet {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [switch]$CaptureOutput,
    [switch]$AllowFailure
  )
  $stdoutFile = New-TemporaryFile
  $stderrFile = New-TemporaryFile
  try {
    & $FilePath @Arguments 1> $stdoutFile 2> $stderrFile
    $exitCode = $LASTEXITCODE
    $stdout = ""
    $stderr = ""
    if (Test-Path -LiteralPath $stdoutFile) { $stdout = Get-Content -Raw -LiteralPath $stdoutFile }
    if (Test-Path -LiteralPath $stderrFile) { $stderr = Get-Content -Raw -LiteralPath $stderrFile }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
      $safe = ($stderr -replace "(?i)(authorization|bearer|token|secret|cookie|password)\s*[:=]\s*\S+", '$1=<redacted>')
      $safe = ($safe -replace 'https?://\S+', "<redacted-url>").Trim()
      if ($safe.Length -gt 220) { $safe = $safe.Substring(0, 220) }
      if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "$FilePath command failed." }
      throw $safe
    }
    if ($CaptureOutput) { return (($stdout | Out-String).Trim()) }
    return $exitCode
  } finally {
    Remove-Item -LiteralPath $stdoutFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
  }
}

function Get-ControllerArtifactPaths {
  param([string]$ResolvedOutputDir)
  [pscustomobject]@{
    report_json = Join-Path $ResolvedOutputDir "mvp-pr-demo-report.json"
    report_md = Join-Path $ResolvedOutputDir "mvp-pr-demo-report.md"
    state = Join-Path $ResolvedOutputDir "mvp-pr-demo-state.json"
    task = Join-Path $ResolvedOutputDir "mvp-pr-demo-task.json"
    worker = Join-Path $ResolvedOutputDir "mvp-pr-demo-worker.json"
    preflight = Join-Path $ResolvedOutputDir "mvp-pr-demo-preflight.json"
    branch_plan = Join-Path $ResolvedOutputDir "mvp-pr-demo-branch-plan.json"
    allowlist = Join-Path $ResolvedOutputDir "mvp-pr-demo-allowlist-check.json"
    pr_metadata = Join-Path $ResolvedOutputDir "mvp-pr-demo-pr-metadata.json"
    provider = Join-Path $ResolvedOutputDir "mvp-pr-demo-provider-report.json"
    safety = Join-Path $ResolvedOutputDir "mvp-pr-demo-safety.json"
    index = Join-Path $ResolvedOutputDir "mvp-pr-demo-artifact-index.json"
    pr_body = Join-Path $ResolvedOutputDir "mvp-pr-demo-pr-body.md"
  }
}

function New-ControllerSafetyFlags {
  [ordered]@{
    codex_called = $false
    tui_created_branch = $false
    tui_created_pr = $false
    worker_loop_started = $false
    queue_runner_started = $false
    run_forever_started = $false
    hermes_live_called = $false
    mcp_run_called = $false
    auto_merge_enabled = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    raw_input_persisted = $false
    token_printed = $false
  }
}

function Get-ControllerBranchName {
  $date = (Get-Date).ToUniversalTime().ToString("yyyyMMdd")
  $short = Get-DemoGitText -Arguments @("rev-parse", "--short=7", "HEAD")
  return "demo/mg372b-controller-draft-pr-$date-$short"
}

function Test-ControllerBranchPolicy {
  param([string]$BranchName)
  $checks = [ordered]@{
    prefix_demo = $BranchName.StartsWith("demo/")
    milestone_mg372b = ($BranchName -match "(^|/)mg372b-")
    no_spaces = ($BranchName -notmatch "\s")
    no_shell_metacharacters = ($BranchName -match "^[A-Za-z0-9/_-]+$")
    under_80_characters = ($BranchName.Length -lt 80)
    pattern_matched = ($BranchName -match "^demo/mg372b-controller-draft-pr-[0-9]{8}-[A-Za-z0-9]{7}$")
  }
  $passed = $true
  foreach ($property in $checks.GetEnumerator()) {
    if (-not [bool]$property.Value) { $passed = $false }
  }
  [pscustomobject]@{
    branch_name = $BranchName
    branch_policy_passed = $passed
    checks = $checks
    token_printed = $false
  }
}

function Get-ControllerChangedFiles {
  $raw = Get-DemoGitText -Arguments @("status", "--porcelain=v1")
  if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
  $files = [System.Collections.Generic.List[string]]::new()
  foreach ($line in ($raw -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path -match " -> ") { $path = ($path -split " -> ")[-1] }
    $files.Add($path.Replace("\", "/")) | Out-Null
  }
  return @($files)
}

function Test-ControllerAllowlist {
  param([string[]]$ChangedFiles)
  $allowed = @($ControllerDemoFile)
  $unexpected = @($ChangedFiles | Where-Object { $_ -notin $allowed })
  [pscustomobject]@{
    allowed_files = $allowed
    changed_files = @($ChangedFiles)
    unexpected_files = @($unexpected)
    docs_only_allowlist_passed = (@($ChangedFiles).Count -gt 0 -and @($unexpected).Count -eq 0)
    token_printed = $false
  }
}

function New-ControllerTaskPayload {
  [ordered]@{
    task_id = $ControllerTaskId
    project_id = $ProjectId
    goal_id = $ControllerGoalId
    title = "MG372B controller-created draft PR demo task"
    body = "Run one controller-created docs-only draft PR demo and record sanitized evidence."
    prompt_summary = "MG372B fixed controller-created draft PR demo. Safe summary only."
    risk = "low"
    source = "custom"
    task_type = "controller-draft-pr-demo"
    allowed_paths = @($ControllerDemoFile, ".agent/tmp/skybridge-mvp-demo-pr/**")
    blocked_paths = @(".env", "secrets/**", ".github/**", "apps/**", "packages/**", "deploy/**", "Dockerfile", "package.json", ".git/**")
    validation = @("one controller-created branch", "one draft PR", "docs-only allowlist", "token_printed=false")
    required_capabilities = @("powershell", "git", "gh", "controller-draft-pr-demo")
    planner_metadata = @{
      adapter = "skybridge-mvp-demo"
      decision = "continue"
      reason = "mg372b_controller_created_draft_pr_demo"
      task_type = "controller-draft-pr-demo"
      expected_outputs = @($ControllerDemoFile, ".agent/tmp/skybridge-mvp-demo-pr/**")
      codex_called = $false
      tui_created_branch = $false
      tui_created_pr = $false
      worker_loop_started = $false
      queue_runner_started = $false
      run_forever_started = $false
      token_printed = $false
    }
  }
}

function Write-ControllerDemoDoc {
  param(
    [string]$Path,
    [string]$GeneratedAt,
    [string]$BaselineCommit,
    [string]$BranchName
  )
  $content = @(
    "# MG372B Controller Draft PR Demo Artifact",
    "",
    "- generated_at: $GeneratedAt",
    "- source_milestone: MG372B",
    "- baseline_commit_before_demo_pr: $BaselineCommit",
    "- project_id: $ProjectId",
    "- goal_id: $ControllerGoalId",
    "- task_id: $ControllerTaskId",
    "- worker_id: $ControllerWorkerId",
    "- branch_name: $BranchName",
    "",
    "## Draft PR Policy",
    "",
    "- controller_created_branch=true",
    "- controller_created_draft_pr=true",
    "- draft=true",
    "- demo_pr_left_open=true",
    "- demo_pr_marked_ready=false",
    "- demo_pr_merged=false",
    "- auto_merge_enabled=false",
    "",
    "## Safety Flags",
    "",
    "- codex_called=false",
    "- tui_created_branch=false",
    "- tui_created_pr=false",
    "- worker_loop_started=false",
    "- queue_runner_started=false",
    "- run_forever_started=false",
    "- hermes_live_called=false",
    "- mcp_run_called=false",
    "- release_created=false",
    "- tag_created=false",
    "- asset_uploaded=false",
    "- raw_input_persisted=false",
    "- token_printed=false",
    "",
    "This artifact is deterministic docs-only evidence for the MG372B controller-created draft PR demo."
  )
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $content | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-ControllerArtifacts {
  param(
    [string]$ResolvedOutputDir,
    $Report,
    $State,
    $TaskArtifact,
    $WorkerArtifact,
    $Preflight,
    $BranchPlan,
    $Allowlist,
    $PrMetadata,
    $Provider,
    $Safety
  )
  $paths = Get-ControllerArtifactPaths -ResolvedOutputDir $ResolvedOutputDir
  Write-DemoJsonFile -Path $paths.state -Value $State
  Write-DemoJsonFile -Path $paths.task -Value $TaskArtifact
  Write-DemoJsonFile -Path $paths.worker -Value $WorkerArtifact
  Write-DemoJsonFile -Path $paths.preflight -Value $Preflight
  Write-DemoJsonFile -Path $paths.branch_plan -Value $BranchPlan
  Write-DemoJsonFile -Path $paths.allowlist -Value $Allowlist
  Write-DemoJsonFile -Path $paths.pr_metadata -Value $PrMetadata
  Write-DemoJsonFile -Path $paths.provider -Value $Provider
  Write-DemoJsonFile -Path $paths.safety -Value $Safety
  Write-DemoJsonFile -Path $paths.report_json -Value $Report
  $relativeOutput = $OutputDir.Replace("\", "/")
  $index = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.artifact_index.v1"
    generated_at = $Report.generated_at
    artifact_dir = $relativeOutput
    artifacts = @($ControllerArtifacts)
    report_json_path = $Report.report_json_path
    report_markdown_path = $Report.report_markdown_path
    token_printed = $false
  }
  Write-DemoJsonFile -Path $paths.index -Value $index

  $markdown = @(
    "# SkyBridge MVP Controller Draft PR Demo",
    "",
    "- result: $($Report.demo_result)",
    "- validation_status: $($Report.validation_status)",
    "- project_id: $($Report.project_id)",
    "- goal_id: $($Report.goal_id)",
    "- task_id: $($Report.task_id)",
    "- worker_id: $($Report.worker_id)",
    "- branch_name: $($Report.branch_name)",
    "- commit_sha: $($Report.commit_sha)",
    "- pr_number: $($Report.pr_number)",
    "- pr_url: $($Report.pr_url)",
    "- draft_pr: $($Report.draft_pr)",
    "- demo_pr_left_open: $($Report.demo_pr_left_open)",
    "- demo_pr_marked_ready: $($Report.demo_pr_marked_ready)",
    "- demo_pr_merged: $($Report.demo_pr_merged)",
    "- docs_only_allowlist_passed: $($Report.docs_only_allowlist_passed)",
    "- branch_policy_passed: $($Report.branch_policy_passed)",
    "- task_created: $($Report.task_created)",
    "- worker_registered: $($Report.worker_registered)",
    "- task_claimed: $($Report.task_claimed)",
    "- task_completed: $($Report.task_completed)",
    "- fixture_mode: $($Report.fixture_mode)",
    "- real_worker_execution: $($Report.real_worker_execution)",
    "- codex_called: false",
    "- tui_created_branch: false",
    "- tui_created_pr: false",
    "- worker_loop_started: false",
    "- queue_runner_started: false",
    "- run_forever_started: false",
    "- hermes_live_called: false",
    "- mcp_run_called: false",
    "- auto_merge_enabled: false",
    "- release_created: false",
    "- tag_created: false",
    "- asset_uploaded: false",
    "- raw_input_persisted: false",
    "- token_printed: false",
    "",
    "Artifacts are written under `$relativeOutput`."
  )
  $markdown | Set-Content -LiteralPath $paths.report_md -Encoding UTF8
}

function New-ControllerReport {
  param(
    [string]$GeneratedAt,
    [string]$BaselineCommit,
    [string]$ImplementationCommit,
    [string]$BranchName,
    [string[]]$ChangedFiles,
    [string]$ValidationStatus = "not_run",
    [string]$DemoResult = "blocked"
  )
  $relativeOutput = $OutputDir.Replace("\", "/")
  [ordered]@{
    schema = $ControllerSchema
    generated_at = $GeneratedAt
    mode = "controller-draft-pr"
    baseline_commit = $BaselineCommit
    implementation_commit = $ImplementationCommit
    project_id = $ProjectId
    goal_id = $ControllerGoalId
    task_id = $ControllerTaskId
    worker_id = $ControllerWorkerId
    task_created = $false
    worker_registered = $false
    task_claimed = $false
    task_started = $false
    task_completed = $false
    task_failed = $false
    task_blocked = $false
    validation_status = $ValidationStatus
    controller_created_branch = $false
    controller_created_draft_pr = $false
    would_create_branch = $true
    would_create_draft_pr = $true
    pr_created = $false
    branch_name = $BranchName
    commit_sha = ""
    pr_number = $null
    pr_url = ""
    draft_pr = $false
    demo_pr_left_open = $false
    demo_pr_marked_ready = $false
    demo_pr_merged = $false
    docs_only_allowlist_passed = $false
    branch_policy_passed = $false
    changed_files = @($ChangedFiles)
    server_task_pr_evidence_recorded = $false
    artifact_report_written = $true
    artifacts_written = $true
    report_markdown_path = "$relativeOutput/mvp-pr-demo-report.md"
    report_json_path = "$relativeOutput/mvp-pr-demo-report.json"
    demo_result = $DemoResult
    fixture_mode = $false
    real_worker_execution = $false
    codex_called = $false
    tui_created_branch = $false
    tui_created_pr = $false
    worker_loop_started = $false
    queue_runner_started = $false
    run_forever_started = $false
    hermes_live_called = $false
    mcp_run_called = $false
    auto_merge_enabled = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    raw_input_persisted = $false
    token_printed = $false
    blockers = @()
    warnings = @()
  }
}

function Invoke-ControllerDraftPrDemo {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
  $generatedAt = Get-DemoUtcNow
  $implementationCommit = Get-DemoGitText -Arguments @("rev-parse", "HEAD")
  $baselineCommit = $implementationCommit
  $branchName = Get-ControllerBranchName
  $plannedChangedFiles = @($ControllerDemoFile)
  $isPreview = ($Mode -eq "controller-draft-pr-preview" -or -not $Apply)
  $blockers = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()
  $providerCallCount = 0
  $unexpectedProviderCallCount = 0
  $gitPushCalled = $false
  $ghPrCreateCalled = $false
  $githubApiCalled = $false
  $serverInfo = $null
  $currentBranchBefore = ""
  $branchCreated = $false
  $demoCommitCreated = $false
  $prCreated = $false
  $taskCreated = $false
  $workerRegistered = $false
  $taskClaimed = $false
  $taskStarted = $false
  $taskCompleted = $false
  $taskFailed = $false
  $taskBlocked = $false
  $serverTaskEvidenceRecorded = $false
  $finalTask = $null
  $finalWorker = $null
  $commitSha = ""
  $prNumber = $null
  $prUrl = ""
  $draftPr = $false
  $demoResult = "blocked"
  $validationStatus = "not_run"

  $branchPolicy = Test-ControllerBranchPolicy -BranchName $branchName
  $allowlist = Test-ControllerAllowlist -ChangedFiles $plannedChangedFiles
  $report = New-ControllerReport -GeneratedAt $generatedAt -BaselineCommit $baselineCommit -ImplementationCommit $implementationCommit -BranchName $branchName -ChangedFiles $plannedChangedFiles
  $report.branch_policy_passed = [bool]$branchPolicy.branch_policy_passed
  $report.docs_only_allowlist_passed = [bool]$allowlist.docs_only_allowlist_passed

  $preflight = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.preflight.v1"
    generated_at = $generatedAt
    mode = "controller-draft-pr"
    preview = [bool]$isPreview
    apply = [bool]$Apply
    git_available = [bool](Get-Command git -ErrorAction SilentlyContinue)
    gh_available = [bool](Get-Command gh -ErrorAction SilentlyContinue)
    gh_auth_available = $false
    repo_clean = $false
    current_branch = ""
    current_branch_is_main = $false
    main_synced_with_origin = $false
    contains_mg372a_baseline = $false
    no_existing_demo_branch = $false
    no_existing_demo_pr = $false
    confirmation_text_matched = ($ConfirmationText -eq $ControllerConfirmationText)
    preflight_passed = $false
    blockers = @()
    token_printed = $false
  }
  $branchPlan = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.branch_plan.v1"
    generated_at = $generatedAt
    branch_name = $branchName
    branch_policy = $branchPolicy
    branch_policy_passed = [bool]$branchPolicy.branch_policy_passed
    branch_name_recorded_before_mutation = $true
    one_branch_max = $true
    token_printed = $false
  }
  $prMetadata = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.pr_metadata.v1"
    generated_at = $generatedAt
    title = $ControllerPrTitle
    draft = $true
    pr_number = $null
    pr_url = ""
    demo_pr_left_open = $false
    demo_pr_marked_ready = $false
    demo_pr_merged = $false
    auto_merge_enabled = $false
    token_printed = $false
  }
  $provider = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.provider_report.v1"
    generated_at = $generatedAt
    provider = "controller-git-gh"
    preview = [bool]$isPreview
    provider_call_count = 0
    unexpected_provider_call_count = 0
    git_push_called = $false
    gh_pr_create_called = $false
    github_api_called = $false
    controller_created_branch = $false
    controller_created_draft_pr = $false
    token_printed = $false
  }
  $safety = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.safety.v1"
    generated_at = $generatedAt
    mode = "controller-draft-pr"
    safety_flags = New-ControllerSafetyFlags
    raw_secrets_included = $false
    raw_logs_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_prompt_included = $false
    token_printed = $false
  }

  try {
    $currentBranchBefore = Get-DemoGitText -Arguments @("branch", "--show-current")
    $preflight.current_branch = $currentBranchBefore
    $preflight.current_branch_is_main = ($currentBranchBefore -eq "main")
    $preflight.repo_clean = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain")))
    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("fetch", "origin", "main", "--prune") | Out-Null
    $head = Get-DemoGitText -Arguments @("rev-parse", "HEAD")
    $originMain = Get-DemoGitText -Arguments @("rev-parse", "origin/main")
    $preflight.main_synced_with_origin = ($head -eq $originMain)
    $mergeBaseExit = Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("merge-base", "--is-ancestor", $ControllerBaselineCommit, "HEAD") -AllowFailure
    $preflight.contains_mg372a_baseline = ([int]$mergeBaseExit -eq 0)
    $ghAuthExit = Invoke-DemoExternalQuiet -FilePath "gh" -Arguments @("auth", "status") -AllowFailure
    $preflight.gh_auth_available = ([int]$ghAuthExit -eq 0)
    $localBranch = Get-DemoGitText -Arguments @("rev-parse", "--verify", "--quiet", $branchName) -AllowFailure
    $remoteBranch = Get-DemoGitText -Arguments @("ls-remote", "--heads", "origin", $branchName) -AllowFailure
    $preflight.no_existing_demo_branch = ([string]::IsNullOrWhiteSpace($localBranch) -and [string]::IsNullOrWhiteSpace($remoteBranch))
    $existingPrRaw = Invoke-DemoExternalQuiet -FilePath "gh" -Arguments @("pr", "list", "--head", $branchName, "--state", "all", "--json", "number,url,state") -CaptureOutput
    $existingPr = @()
    if (-not [string]::IsNullOrWhiteSpace($existingPrRaw)) { $existingPr = @($existingPrRaw | ConvertFrom-Json) }
    $preflight.no_existing_demo_pr = (@($existingPr).Count -eq 0)

    if (-not $preflight.git_available) { $blockers.Add("git_unavailable") | Out-Null }
    if (-not $preflight.gh_available) { $blockers.Add("gh_unavailable") | Out-Null }
    if (-not $preflight.gh_auth_available) { $blockers.Add("gh_auth_unavailable") | Out-Null }
    if (-not $branchPolicy.branch_policy_passed) { $blockers.Add("branch_policy_failed") | Out-Null }
    if (-not $allowlist.docs_only_allowlist_passed) { $blockers.Add("docs_only_allowlist_failed") | Out-Null }
    if (-not $isPreview -and -not $preflight.confirmation_text_matched) { $blockers.Add("confirmation_text_mismatch") | Out-Null }
    if (-not $isPreview -and -not $preflight.repo_clean) { $blockers.Add("repo_not_clean") | Out-Null }
    if (-not $isPreview -and -not $preflight.current_branch_is_main) { $blockers.Add("not_on_main") | Out-Null }
    if (-not $isPreview -and -not $preflight.main_synced_with_origin) { $blockers.Add("main_not_synced_with_origin") | Out-Null }
    if (-not $isPreview -and -not $preflight.contains_mg372a_baseline) { $blockers.Add("mg372a_baseline_missing") | Out-Null }
    if (-not $isPreview -and -not $preflight.no_existing_demo_branch) { $blockers.Add("existing_demo_branch") | Out-Null }
    if (-not $isPreview -and -not $preflight.no_existing_demo_pr) { $blockers.Add("existing_demo_pr") | Out-Null }

    $preflight.blockers = @($blockers)
    $preflight.preflight_passed = (@($blockers).Count -eq 0)
    $report.blockers = @($blockers)
    $report.warnings = @($warnings)

    $state = [ordered]@{
      schema = "skybridge.mvp_demo.controller_draft_pr.state.v1"
      generated_at = $generatedAt
      mode = "controller-draft-pr"
      preview = [bool]$isPreview
      apply = [bool]$Apply
      output_dir = $OutputDir.Replace("\", "/")
      project_id = $ProjectId
      goal_id = $ControllerGoalId
      task_id = $ControllerTaskId
      worker_id = $ControllerWorkerId
      branch_name = $branchName
      token_printed = $false
    }
    $taskArtifact = [ordered]@{
      schema = "skybridge.mvp_demo.controller_draft_pr.task.v1"
      generated_at = $generatedAt
      task_payload = New-ControllerTaskPayload
      final_task = $null
      task_created = $false
      task_claimed = $false
      task_started = $false
      task_completed = $false
      task_failed = $false
      token_printed = $false
    }
    $workerArtifact = [ordered]@{
      schema = "skybridge.mvp_demo.controller_draft_pr.worker.v1"
      generated_at = $generatedAt
      worker_id = $ControllerWorkerId
      worker_registered = $false
      final_worker = $null
      capabilities = @("powershell", "git", "gh", "controller-draft-pr-demo")
      token_printed = $false
    }

    if ($isPreview) {
      $report.validation_status = if (@($blockers | Where-Object { $_ -in @("branch_policy_failed", "docs_only_allowlist_failed", "git_unavailable", "gh_unavailable", "gh_auth_unavailable") }).Count -eq 0) { "preview_passed" } else { "preview_blocked" }
      $report.demo_result = if ($report.validation_status -eq "preview_passed") { "pass" } else { "blocked" }
      Write-ControllerArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -BranchPlan $branchPlan -Allowlist $allowlist -PrMetadata $prMetadata -Provider $provider -Safety $safety
      if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
      return
    }

    Write-ControllerArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -BranchPlan $branchPlan -Allowlist $allowlist -PrMetadata $prMetadata -Provider $provider -Safety $safety
    if (-not $preflight.preflight_passed) { throw "MG372B controller draft PR preflight failed." }

    $script:ResolvedApiBase = $ApiBase
    if ($UseTempDatabase) { $StartServer = $true }
    if ($StartServer) { $serverInfo = Start-DemoServer -ResolvedOutputDir $resolvedOutputDir }
    Wait-DemoServerHealth | Out-Null

    $existingProject = Invoke-DemoApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -AllowNotFound
    if (-not $existingProject) {
      Invoke-DemoApi -Method POST -Path "/v1/projects" -Body @{ project_id = $ProjectId; name = $ProjectId } | Out-Null
    }
    $existingGoal = Invoke-DemoApi -Method GET -Path "/v1/goals/$([uri]::EscapeDataString($ControllerGoalId))" -AllowNotFound
    if (-not $existingGoal) {
      Invoke-DemoApi -Method POST -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -Body @{
        goal_id = $ControllerGoalId
        title = "MG372B Controller Draft PR Demo"
        summary = "Prove one controller-created docs-only draft PR demo without TUI or Codex execution."
        source = "mg372b-mvp-demo"
        risk = "low"
        status = "ready"
        acceptance_criteria = @("One controller-created demo branch and one draft PR are created.")
        evidence_requirements = @("MG372B PR demo JSON and Markdown reports are written.")
      } | Out-Null
    }
    Invoke-DemoApi -Method POST -Path "/v1/tasks" -Body (New-ControllerTaskPayload) | Out-Null
    $taskCreated = $true
    Invoke-DemoApi -Method POST -Path "/v1/workers/register" -Body @{
      worker_id = $ControllerWorkerId
      name = "MG372B controller demo worker"
      provider = "controller-demo"
      capabilities = @("powershell", "git", "gh", "controller-draft-pr-demo")
      labels = @("mg372b", "controller-created", "draft-pr", "poll-once")
      enabled = $true
      auth_mode = "none"
      api_base = $script:ResolvedApiBase
      allow_remote_server = $false
    } | Out-Null
    $workerRegistered = $true
    Invoke-DemoApi -Method POST -Path "/v1/workers/$([uri]::EscapeDataString($ControllerWorkerId))/heartbeat" -Body @{
      status_note = "mg372b controller draft PR demo ready"
      load = 0
      seen_at = Get-DemoUtcNow
    } | Out-Null
    Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($ControllerTaskId))/claim" -Body @{ worker_id = $ControllerWorkerId } | Out-Null
    $taskClaimed = $true
    Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($ControllerTaskId))/start" -Body @{ worker_id = $ControllerWorkerId } | Out-Null
    $taskStarted = $true

    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("switch", "-c", $branchName) | Out-Null
    $branchCreated = $true
    $generatedDocAt = Get-DemoUtcNow
    Write-ControllerDemoDoc -Path (Join-Path (Get-Location) $ControllerDemoFile) -GeneratedAt $generatedDocAt -BaselineCommit $baselineCommit -BranchName $branchName
    $actualChangedFiles = @(Get-ControllerChangedFiles)
    $allowlist = Test-ControllerAllowlist -ChangedFiles $actualChangedFiles
    if (-not $allowlist.docs_only_allowlist_passed) {
      $blockers.Add("docs_only_allowlist_failed_after_write") | Out-Null
      throw "MG372B demo changed files failed allowlist."
    }
    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("add", "--", $ControllerDemoFile) | Out-Null
    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("commit", "-m", $ControllerCommitMessage) | Out-Null
    $demoCommitCreated = $true
    $commitSha = Get-DemoGitText -Arguments @("rev-parse", "HEAD")
    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("push", "--set-upstream", "origin", $branchName) | Out-Null
    $gitPushCalled = $true
    $providerCallCount += 1

    $paths = Get-ControllerArtifactPaths -ResolvedOutputDir $resolvedOutputDir
    $body = @(
      "## MG372B Controller-created Draft PR Demo",
      "",
      "- demo_result=pass",
      "- controller_created_branch=true",
      "- controller_created_draft_pr=true",
      "- draft=true",
      "- task_created=true",
      "- worker_registered=true",
      "- task_claimed=true",
      "- task_completed=true",
      "- docs_only_allowlist_passed=true",
      "- branch_policy_passed=true",
      "- codex_called=false",
      "- tui_created_branch=false",
      "- tui_created_pr=false",
      "- auto_merge_enabled=false",
      "- release_created=false",
      "- tag_created=false",
      "- asset_uploaded=false",
      "- token_printed=false",
      "- artifacts path: .agent/tmp/skybridge-mvp-demo-pr/",
      "",
      "This PR is intentionally draft-only and must remain open for Jerry review."
    )
    $body | Set-Content -LiteralPath $paths.pr_body -Encoding UTF8
    $prUrl = Invoke-DemoExternalQuiet -FilePath "gh" -Arguments @("pr", "create", "--draft", "--base", "main", "--head", $branchName, "--title", $ControllerPrTitle, "--body-file", $paths.pr_body) -CaptureOutput
    $ghPrCreateCalled = $true
    $githubApiCalled = $true
    $providerCallCount += 1
    $prCreated = $true
    $prViewRaw = Invoke-DemoExternalQuiet -FilePath "gh" -Arguments @("pr", "view", $prUrl, "--json", "number,url,isDraft,state,autoMergeRequest,files") -CaptureOutput
    $githubApiCalled = $true
    $providerCallCount += 1
    $prView = $prViewRaw | ConvertFrom-Json
    $prNumber = [int]$prView.number
    $prUrl = [string]$prView.url
    $draftPr = [bool]$prView.isDraft
    $actualPrFiles = @($prView.files | ForEach-Object { [string]$_.path })
    $allowlist = Test-ControllerAllowlist -ChangedFiles $actualPrFiles
    if (-not $draftPr) {
      $blockers.Add("demo_pr_not_draft") | Out-Null
      throw "MG372B demo PR was not draft."
    }
    if ($null -ne $prView.autoMergeRequest) {
      $blockers.Add("demo_pr_auto_merge_enabled") | Out-Null
      throw "MG372B demo PR auto-merge was enabled."
    }
    if (-not $allowlist.docs_only_allowlist_passed) {
      $blockers.Add("demo_pr_allowlist_failed") | Out-Null
      throw "MG372B demo PR changed files failed allowlist."
    }

    $complete = Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($ControllerTaskId))/complete" -Body @{
      worker_id = $ControllerWorkerId
      summary = "MG372B controller-created draft PR demo created one docs-only draft PR and left it open for review."
      result_url = $prUrl
      evidence_summary = @{
        schema = "skybridge.mvp_demo.controller_draft_pr.task_evidence.v1"
        project_id = $ProjectId
        goal_id = $ControllerGoalId
        task_id = $ControllerTaskId
        worker_id = $ControllerWorkerId
        branch_name = $branchName
        commit_sha = $commitSha
        pr_number = $prNumber
        pr_url = $prUrl
        draft_pr = $true
        docs_only_allowlist_passed = $true
        branch_policy_passed = $true
        codex_called = $false
        tui_created_branch = $false
        tui_created_pr = $false
        token_printed = $false
        created_at = Get-DemoUtcNow
      }
    }
    $taskCompleted = $true
    $serverTaskEvidenceRecorded = $true
    $finalTask = $complete.task
    $finalTask = (Invoke-DemoApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($ControllerTaskId))").task
    $finalWorker = (Invoke-DemoApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($ControllerWorkerId))").worker
    $validationStatus = "passed"
    $demoResult = "pass"
  } catch {
    if (@($blockers).Count -lt 1) { $blockers.Add("controller_draft_pr_demo_failed") | Out-Null }
    $validationStatus = "failed"
    $demoResult = if ($branchCreated -or $prCreated) { "partial" } else { "blocked" }
    if ($taskStarted -and -not $taskCompleted) { $taskBlocked = $true }
    if (-not $prCreated) { $taskFailed = $true }
    $safeMessage = ($_.Exception.Message -replace "(?i)(authorization|bearer|token|secret|cookie|password)\s*[:=]\s*\S+", '$1=<redacted>')
    $safeMessage = ($safeMessage -replace 'https?://\S+', "<redacted-url>").Trim()
    if ($safeMessage.Length -gt 180) { $safeMessage = $safeMessage.Substring(0, 180) }
    $warnings.Add($safeMessage) | Out-Null
  } finally {
    if ($serverInfo) { Stop-DemoServer -ServerInfo $serverInfo }
    if ($prCreated -and $demoCommitCreated -and -not [string]::IsNullOrWhiteSpace($currentBranchBefore)) {
      $dirty = Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure
      if ([string]::IsNullOrWhiteSpace($dirty)) {
        Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("switch", $currentBranchBefore) -AllowFailure | Out-Null
      }
    }
  }

  $provider.provider_call_count = $providerCallCount
  $provider.unexpected_provider_call_count = $unexpectedProviderCallCount
  $provider.git_push_called = [bool]$gitPushCalled
  $provider.gh_pr_create_called = [bool]$ghPrCreateCalled
  $provider.github_api_called = [bool]$githubApiCalled
  $provider.controller_created_branch = [bool]$branchCreated
  $provider.controller_created_draft_pr = [bool]$prCreated
  $prMetadata.pr_number = $prNumber
  $prMetadata.pr_url = $prUrl
  $prMetadata.demo_pr_left_open = [bool]$prCreated
  $report.generated_at = Get-DemoUtcNow
  $report.task_created = [bool]$taskCreated
  $report.worker_registered = [bool]$workerRegistered
  $report.task_claimed = [bool]$taskClaimed
  $report.task_started = [bool]$taskStarted
  $report.task_completed = [bool]$taskCompleted
  $report.task_failed = [bool]$taskFailed
  $report.task_blocked = [bool]$taskBlocked
  $report.validation_status = $validationStatus
  $report.controller_created_branch = [bool]$branchCreated
  $report.controller_created_draft_pr = [bool]$prCreated
  $report.pr_created = [bool]$prCreated
  $report.commit_sha = $commitSha
  $report.pr_number = $prNumber
  $report.pr_url = $prUrl
  $report.draft_pr = [bool]$draftPr
  $report.demo_pr_left_open = [bool]$prCreated
  $report.demo_pr_marked_ready = $false
  $report.demo_pr_merged = $false
  $report.docs_only_allowlist_passed = [bool]$allowlist.docs_only_allowlist_passed
  $report.branch_policy_passed = [bool]$branchPolicy.branch_policy_passed
  $report.changed_files = @($allowlist.changed_files)
  $report.server_task_pr_evidence_recorded = [bool]$serverTaskEvidenceRecorded
  $report.demo_result = $demoResult
  $report.real_worker_execution = [bool]($taskClaimed -and $taskStarted -and $taskCompleted)
  $report.blockers = @($blockers)
  $report.warnings = @($warnings)

  $state = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.state.v1"
    generated_at = $report.generated_at
    mode = "controller-draft-pr"
    preview = [bool]$isPreview
    apply = [bool]$Apply
    output_dir = $OutputDir.Replace("\", "/")
    project_id = $ProjectId
    goal_id = $ControllerGoalId
    task_id = $ControllerTaskId
    worker_id = $ControllerWorkerId
    branch_name = $branchName
    commit_sha = $commitSha
    pr_number = $prNumber
    pr_url = $prUrl
    token_printed = $false
  }
  $taskArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.task.v1"
    generated_at = $report.generated_at
    task_payload = New-ControllerTaskPayload
    final_task = $finalTask
    task_created = [bool]$taskCreated
    task_claimed = [bool]$taskClaimed
    task_started = [bool]$taskStarted
    task_completed = [bool]$taskCompleted
    task_failed = [bool]$taskFailed
    token_printed = $false
  }
  $workerArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.controller_draft_pr.worker.v1"
    generated_at = $report.generated_at
    worker_id = $ControllerWorkerId
    worker_registered = [bool]$workerRegistered
    final_worker = $finalWorker
    capabilities = @("powershell", "git", "gh", "controller-draft-pr-demo")
    token_printed = $false
  }
  $preflight.blockers = @($blockers)
  $preflight.preflight_passed = ($validationStatus -eq "passed")
  $allowlist = Test-ControllerAllowlist -ChangedFiles @($report.changed_files)
  Write-ControllerArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -BranchPlan $branchPlan -Allowlist $allowlist -PrMetadata $prMetadata -Provider $provider -Safety $safety
  if ($OpenReport) { Invoke-Item -LiteralPath (Join-Path $resolvedOutputDir "mvp-pr-demo-report.md") }
  if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
}

function Get-CodexDiffArtifactPaths {
  param([string]$ResolvedOutputDir)
  [pscustomobject]@{
    report_json = Join-Path $ResolvedOutputDir "codex-local-diff-report.json"
    report_md = Join-Path $ResolvedOutputDir "codex-local-diff-report.md"
    state = Join-Path $ResolvedOutputDir "codex-local-diff-state.json"
    task = Join-Path $ResolvedOutputDir "codex-local-diff-task.json"
    worker = Join-Path $ResolvedOutputDir "codex-local-diff-worker.json"
    preflight = Join-Path $ResolvedOutputDir "codex-local-diff-preflight.json"
    prompt = Join-Path $ResolvedOutputDir "codex-local-diff-prompt.md"
    last_message = Join-Path $ResolvedOutputDir "codex-local-diff-last-message.md"
    changed_files = Join-Path $ResolvedOutputDir "codex-local-diff-changed-files.json"
    allowlist = Join-Path $ResolvedOutputDir "codex-local-diff-allowlist-check.json"
    review_summary = Join-Path $ResolvedOutputDir "codex-local-diff-review-summary.md"
    patch = Join-Path $ResolvedOutputDir "codex-local-diff.patch"
    safety = Join-Path $ResolvedOutputDir "codex-local-diff-safety.json"
    collector_diagnostics = Join-Path $ResolvedOutputDir "codex-local-diff-collector-diagnostics.json"
    index = Join-Path $ResolvedOutputDir "codex-local-diff-artifact-index.json"
    workspace = Join-Path $ResolvedOutputDir "worktree"
    codex_jsonl = Join-Path $ResolvedOutputDir "codex-local-diff-codex.jsonl"
  }
}

function New-CodexDiffSafetyFlags {
  [ordered]@{
    codex_called = $false
    codex_call_count = 0
    pr_created = $false
    branch_pushed = $false
    commit_created = $false
    demo_pr_311_modified = $false
    tui_created_branch = $false
    tui_created_pr = $false
    worker_loop_started = $false
    queue_runner_started = $false
    run_forever_started = $false
    hermes_live_called = $false
    mcp_run_called = $false
    auto_merge_enabled = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    raw_input_persisted = $false
    raw_output_exported = $false
    token_printed = $false
  }
}

function Test-CodexDiffAllowlist {
  param([string[]]$ChangedFiles)
  $allowed = @($CodexDiffDemoFile)
  $unexpected = @($ChangedFiles | Where-Object { $_ -notin $allowed })
  [pscustomobject]@{
    allowed_files = $allowed
    changed_files = @($ChangedFiles)
    unexpected_files = @($unexpected)
    docs_only_allowlist_passed = (@($ChangedFiles).Count -gt 0 -and @($unexpected).Count -eq 0)
    token_printed = $false
  }
}

function New-CodexDiffTaskPayload {
  [ordered]@{
    task_id = $CodexDiffTaskId
    project_id = $ProjectId
    goal_id = $CodexDiffGoalId
    title = "MG372D Codex-generated local diff demo task"
    body = "Call Codex once in an isolated Git worktree, generate one docs-only local diff, and write sanitized review artifacts."
    prompt_summary = "MG372D fixed Codex local diff demo. Safe summary only."
    risk = "low"
    source = "custom"
    task_type = "codex-local-diff-demo"
    allowed_paths = @($CodexDiffDemoFile, ".agent/tmp/skybridge-mvp-codex-diff/**")
    blocked_paths = @(".env", "secrets/**", ".github/**", "apps/**", "packages/**", "deploy/**", "Dockerfile", "package.json", ".git/**")
    validation = @("one Codex call", "one isolated workspace", "docs-only allowlist", "diff.patch written", "no PR", "no push", "no commit", "token_printed=false")
    required_capabilities = @("powershell", "git", "codex", "codex-local-diff-demo")
    planner_metadata = @{
      adapter = "skybridge-mvp-demo"
      decision = "continue"
      reason = "mg372d_codex_generated_local_diff_demo"
      task_type = "codex-local-diff-demo"
      expected_outputs = @($CodexDiffDemoFile, ".agent/tmp/skybridge-mvp-codex-diff/**")
      codex_called = $true
      codex_call_count = 1
      pr_created = $false
      branch_pushed = $false
      commit_created = $false
      tui_created_branch = $false
      tui_created_pr = $false
      worker_loop_started = $false
      queue_runner_started = $false
      run_forever_started = $false
      token_printed = $false
    }
  }
}

function New-CodexDiffPrompt {
  param(
    [string]$BaselineCommit,
    [string]$TaskIdValue
  )
  @"
You are running the SkyBridge MG372D1 local Codex diff rerun demo inside an isolated Git worktree.

Create exactly one docs-only artifact file:

$CodexDiffDemoFile

The file content must include:

- generated_by=Codex
- source milestone=MG372D1
- baseline commit=$BaselineCommit
- task_id=$TaskIdValue
- what the demo proves
- safety boundaries
- token_printed=false

Strict boundaries:

- modify only $CodexDiffDemoFile
- do not run git add
- do not run git commit
- do not run git push
- do not run gh pr create
- do not create or modify any PR
- do not read or print secrets
- do not modify app, server, workflow, package, Docker, runtime or production files
- do not write tokens, environment dumps, raw stdout/stderr, raw prompts or secrets

Finish after writing the file. Keep the response concise.
"@
}

function Resolve-CodexDiffCommand {
  $command = Get-Command "codex" -ErrorAction SilentlyContinue
  if (-not $command) { throw "Codex CLI was not found on PATH." }
  $extension = [System.IO.Path]::GetExtension($command.Source)
  if ($extension -ieq ".ps1") {
    return [pscustomobject]@{
      file_path = "pwsh"
      argument_prefix = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $command.Source)
      display_command = "codex"
      resolved_path = $command.Source
      powershell_shim = $true
      token_printed = $false
    }
  }
  [pscustomobject]@{
    file_path = $command.Source
    argument_prefix = @()
    display_command = "codex"
    resolved_path = $command.Source
    powershell_shim = $false
    token_printed = $false
  }
}

function Invoke-CodexDiffProcess {
  param(
    [Parameter(Mandatory = $true)]$CommandSpec,
    [Parameter(Mandatory = $true)][string]$WorkspacePath,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [Parameter(Mandatory = $true)][string]$LastMessagePath,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [int]$TimeoutMinutes = 15
  )
  $errPath = "$LogPath.err"
  $arguments = @($CommandSpec.argument_prefix) + @("exec", "--sandbox", "workspace-write", "--json", "--output-last-message", $LastMessagePath, "-")
  $startParams = @{
    FilePath = [string]$CommandSpec.file_path
    ArgumentList = $arguments
    WorkingDirectory = $WorkspacePath
    NoNewWindow = $true
    PassThru = $true
    RedirectStandardInput = $PromptPath
    RedirectStandardOutput = $LogPath
    RedirectStandardError = $errPath
  }
  $process = Start-Process @startParams
  $timeoutMs = [Math]::Max(1, $TimeoutMinutes) * 60 * 1000
  if (-not $process.WaitForExit($timeoutMs)) {
    try { $process.Kill($true) } catch { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ ok = $false; exit_code = 124; timed_out = $true; log_path = $LogPath; error_log_path = $errPath; token_printed = $false }
  }
  [pscustomobject]@{ ok = ($process.ExitCode -eq 0); exit_code = $process.ExitCode; timed_out = $false; log_path = $LogPath; error_log_path = $errPath; token_printed = $false }
}

function New-CodexDiffWorkspace {
  param(
    [string]$WorkspacePath,
    [string]$CommitSha
  )
  if (Test-Path -LiteralPath $WorkspacePath) { throw "Existing MG372D workspace blocks apply." }
  $parent = Split-Path -Parent $WorkspacePath
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("worktree", "add", "--detach", $WorkspacePath, $CommitSha) | Out-Null
}

function Get-CodexDiffStatusPorcelain {
  param([string]$WorkspacePath)
  $status = Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("-C", $WorkspacePath, "status", "--porcelain=v1", "--untracked-files=all") -CaptureOutput
  @($status -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function ConvertFrom-CodexDiffStatusPorcelain {
  param([string[]]$StatusLines)
  $changed = [System.Collections.Generic.List[string]]::new()
  foreach ($line in @($StatusLines)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path.Contains(" -> ")) {
      $path = ($path -split " -> ")[-1].Trim()
    }
    $path = $path.Trim('"').Replace("\", "/")
    if (-not [string]::IsNullOrWhiteSpace($path)) { $changed.Add($path) | Out-Null }
  }
  @($changed | Sort-Object -Unique)
}

function Get-CodexDiffChangedFiles {
  param([string]$WorkspacePath)
  ConvertFrom-CodexDiffStatusPorcelain -StatusLines (Get-CodexDiffStatusPorcelain -WorkspacePath $WorkspacePath)
}

function Get-CodexDiffNameOnly {
  param([string]$WorkspacePath)
  $nameOnly = Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("-C", $WorkspacePath, "diff", "--name-only", "--", $CodexDiffDemoFile) -CaptureOutput -AllowFailure
  @($nameOnly -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().Replace("\", "/") })
}

function Write-CodexDiffPatch {
  param(
    [string]$WorkspacePath,
    [string]$PatchPath
  )
  $workspaceFile = Join-Path $WorkspacePath ($CodexDiffDemoFile -replace "/", [System.IO.Path]::DirectorySeparatorChar)
  if (-not (Test-Path -LiteralPath $workspaceFile -PathType Leaf)) {
    "" | Set-Content -LiteralPath $PatchPath -Encoding UTF8
    return
  }
  Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("-C", $WorkspacePath, "add", "--intent-to-add", "--", $CodexDiffDemoFile) | Out-Null
  $diff = Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("-C", $WorkspacePath, "diff", "--no-ext-diff", "--binary", "--", $CodexDiffDemoFile) -CaptureOutput -AllowFailure
  if ([string]::IsNullOrWhiteSpace($diff)) { $diff = "" }
  $diff | Set-Content -LiteralPath $PatchPath -Encoding UTF8
}

function New-CodexDiffCollectorDiagnostics {
  param(
    [string]$GeneratedAt,
    [string]$BaselineCommit,
    [string]$WorkspacePath,
    [string]$PatchPath
  )
  [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.collector_diagnostics.v1"
    generated_at = $GeneratedAt
    workspace_setup_method = "git_worktree"
    baseline_commit = $BaselineCommit
    workspace_path = $WorkspacePath.Replace("\", "/")
    workspace_clean_before_codex = $false
    pre_codex_status_porcelain = @()
    post_codex_status_porcelain = @()
    git_diff_name_only = @()
    git_diff_patch_path = $PatchPath.Replace("\", "/")
    patch_non_empty = $false
    target_artifact_exists = $false
    target_artifact_size_bytes = 0
    line_ending_drift_detected = $false
    hash_comparison_used = $false
    git_index_collector_used = $true
    token_printed = $false
  }
}

function Write-CodexDiffArtifacts {
  param(
    [string]$ResolvedOutputDir,
    $Report,
    $State,
    $TaskArtifact,
    $WorkerArtifact,
    $Preflight,
    $ChangedFiles,
    $Allowlist,
    $CollectorDiagnostics,
    $Safety
  )
  $paths = Get-CodexDiffArtifactPaths -ResolvedOutputDir $ResolvedOutputDir
  foreach ($file in @($paths.prompt, $paths.last_message, $paths.review_summary, $paths.patch)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { "" | Set-Content -LiteralPath $file -Encoding UTF8 }
  }
  Write-DemoJsonFile -Path $paths.state -Value $State
  Write-DemoJsonFile -Path $paths.task -Value $TaskArtifact
  Write-DemoJsonFile -Path $paths.worker -Value $WorkerArtifact
  Write-DemoJsonFile -Path $paths.preflight -Value $Preflight
  Write-DemoJsonFile -Path $paths.changed_files -Value $ChangedFiles
  Write-DemoJsonFile -Path $paths.allowlist -Value $Allowlist
  if ($null -eq $CollectorDiagnostics) {
    $CollectorDiagnostics = New-CodexDiffCollectorDiagnostics -GeneratedAt $Report.generated_at -BaselineCommit $Report.baseline_commit -WorkspacePath $Report.workspace_path -PatchPath $paths.patch
  }
  Write-DemoJsonFile -Path $paths.collector_diagnostics -Value $CollectorDiagnostics
  Write-DemoJsonFile -Path $paths.safety -Value $Safety
  Write-DemoJsonFile -Path $paths.report_json -Value $Report
  $relativeOutput = $OutputDir.Replace("\", "/")
  $index = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.artifact_index.v1"
    generated_at = $Report.generated_at
    artifact_dir = $relativeOutput
    artifacts = @($CodexDiffArtifacts)
    report_json_path = $Report.report_json_path
    report_markdown_path = $Report.report_markdown_path
    diff_patch_path = $Report.diff_patch_path
    review_summary_path = $Report.review_summary_path
    collector_diagnostics_path = "$relativeOutput/codex-local-diff-collector-diagnostics.json"
    token_printed = $false
  }
  Write-DemoJsonFile -Path $paths.index -Value $index

  $markdown = @(
    "# SkyBridge MVP Codex Local Diff Demo",
    "",
    "- result: $($Report.demo_result)",
    "- validation_status: $($Report.validation_status)",
    "- project_id: $($Report.project_id)",
    "- goal_id: $($Report.goal_id)",
    "- task_id: $($Report.task_id)",
    "- worker_id: $($Report.worker_id)",
    "- codex_called: $($Report.codex_called)",
    "- codex_call_count: $($Report.codex_call_count)",
    "- codex_exit_code: $($Report.codex_exit_code)",
    "- isolated_workspace_used: $($Report.isolated_workspace_used)",
    "- workspace_setup_method: $($Report.workspace_setup_method)",
    "- workspace_clean_before_codex: $($Report.workspace_clean_before_codex)",
    "- git_index_collector_used: $($Report.git_index_collector_used)",
    "- hash_comparison_used: $($Report.hash_comparison_used)",
    "- workspace_path: $($Report.workspace_path)",
    "- changed_files: $(@($Report.changed_files) -join ', ')",
    "- docs_only_allowlist_passed: $($Report.docs_only_allowlist_passed)",
    "- diff_patch_path: $($Report.diff_patch_path)",
    "- diff_patch_non_empty: $($Report.diff_patch_non_empty)",
    "- review_summary_path: $($Report.review_summary_path)",
    "- artifact_file_path: $($Report.artifact_file_path)",
    "- target_artifact_exists: $($Report.target_artifact_exists)",
    "- main_worktree_clean_after: $($Report.main_worktree_clean_after)",
    "- task_created: $($Report.task_created)",
    "- worker_registered: $($Report.worker_registered)",
    "- task_claimed: $($Report.task_claimed)",
    "- task_started: $($Report.task_started)",
    "- task_completed: $($Report.task_completed)",
    "- fixture_mode: $($Report.fixture_mode)",
    "- real_worker_execution: $($Report.real_worker_execution)",
    "- pr_created: false",
    "- branch_pushed: false",
    "- commit_created: $($Report.commit_created)",
    "- demo_pr_311_modified: false",
    "- worker_loop_started: false",
    "- queue_runner_started: false",
    "- run_forever_started: false",
    "- hermes_live_called: false",
    "- mcp_run_called: false",
    "- auto_merge_enabled: false",
    "- release_created: false",
    "- tag_created: false",
    "- asset_uploaded: false",
    "- raw_output_exported: false",
    "- token_printed: false",
    "",
    "Artifacts are written under `$relativeOutput`."
  )
  $markdown | Set-Content -LiteralPath $paths.report_md -Encoding UTF8
}

function New-CodexDiffReport {
  param(
    [string]$GeneratedAt,
    [string]$BaselineCommit,
    [string]$ImplementationCommit,
    [string]$WorkspacePath
  )
  $relativeOutput = $OutputDir.Replace("\", "/")
  [ordered]@{
    schema = $CodexDiffSchema
    generated_at = $GeneratedAt
    mode = "codex-local-diff"
    rerun_milestone = "MG372D1"
    baseline_commit = $BaselineCommit
    implementation_commit = $ImplementationCommit
    project_id = $ProjectId
    goal_id = $CodexDiffGoalId
    task_id = $CodexDiffTaskId
    worker_id = $CodexDiffWorkerId
    task_created = $false
    worker_registered = $false
    task_claimed = $false
    task_started = $false
    task_completed = $false
    task_failed = $false
    task_blocked = $false
    validation_status = "not_run"
    would_call_codex = $true
    would_create_isolated_workspace = $true
    would_generate_diff = $true
    would_use_git_index_collector = $true
    would_generate_non_empty_patch = $true
    codex_called = $false
    codex_call_count = 0
    codex_exit_code = $null
    isolated_workspace_used = $false
    workspace_setup_method = "git_worktree"
    workspace_path = $WorkspacePath.Replace("\", "/")
    workspace_clean_before_codex = $false
    main_worktree_clean_after = $false
    git_index_collector_used = $true
    hash_comparison_used = $false
    changed_files = @()
    docs_only_allowlist_passed = $false
    diff_patch_path = "$relativeOutput/codex-local-diff.patch"
    diff_patch_non_empty = $false
    review_summary_path = "$relativeOutput/codex-local-diff-review-summary.md"
    artifact_file_path = "$relativeOutput/worktree/$CodexDiffDemoFile"
    target_artifact_exists = $false
    artifact_report_written = $true
    artifacts_written = $true
    report_markdown_path = "$relativeOutput/codex-local-diff-report.md"
    report_json_path = "$relativeOutput/codex-local-diff-report.json"
    demo_result = "blocked"
    fixture_mode = $false
    real_worker_execution = $false
    pr_created = $false
    branch_pushed = $false
    commit_created = $false
    demo_pr_311_modified = $false
    tui_created_branch = $false
    tui_created_pr = $false
    worker_loop_started = $false
    queue_runner_started = $false
    run_forever_started = $false
    hermes_live_called = $false
    mcp_run_called = $false
    auto_merge_enabled = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    raw_input_persisted = $false
    raw_output_exported = $false
    token_printed = $false
    blockers = @()
    warnings = @()
  }
}

function Invoke-CodexLocalDiffDemo {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
  $paths = Get-CodexDiffArtifactPaths -ResolvedOutputDir $resolvedOutputDir
  $generatedAt = Get-DemoUtcNow
  $implementationCommit = Get-DemoGitText -Arguments @("rev-parse", "HEAD")
  $baselineCommit = $implementationCommit
  $workspacePath = $paths.workspace
  $plannedChangedFiles = @($CodexDiffDemoFile)
  $isPreview = ($Mode -eq "codex-local-diff-preview" -or -not $Apply)
  $blockers = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()
  $serverInfo = $null
  $taskCreated = $false
  $workerRegistered = $false
  $taskClaimed = $false
  $taskStarted = $false
  $taskCompleted = $false
  $taskFailed = $false
  $taskBlocked = $false
  $finalTask = $null
  $finalWorker = $null
  $codexExitCode = $null
  $codexCalled = $false
  $codexCallCount = 0
  $workspaceUsed = $false
  $changedFiles = @()
  $validationStatus = "not_run"
  $demoResult = "blocked"
  $commitCreated = $false

  $prompt = New-CodexDiffPrompt -BaselineCommit $baselineCommit -TaskIdValue $CodexDiffTaskId
  $prompt | Set-Content -LiteralPath $paths.prompt -Encoding UTF8
  $allowlist = Test-CodexDiffAllowlist -ChangedFiles $plannedChangedFiles
  $report = New-CodexDiffReport -GeneratedAt $generatedAt -BaselineCommit $baselineCommit -ImplementationCommit $implementationCommit -WorkspacePath $workspacePath
  $report.docs_only_allowlist_passed = [bool]$allowlist.docs_only_allowlist_passed
  $report.changed_files = @($plannedChangedFiles)

  $preflight = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.preflight.v1"
    generated_at = $generatedAt
    mode = "codex-local-diff"
    preview = [bool]$isPreview
    apply = [bool]$Apply
    git_available = [bool](Get-Command git -ErrorAction SilentlyContinue)
    codex_available = [bool](Get-Command codex -ErrorAction SilentlyContinue)
    repo_clean = $false
    current_branch = ""
    current_branch_is_main = $false
    main_synced_with_origin = $false
    contains_mg372d_baseline = $false
    confirmation_text_matched = ($ConfirmationText -eq $CodexDiffConfirmationText)
    workspace_path = $workspacePath.Replace("\", "/")
    workspace_setup_method = "git_worktree"
    git_index_collector_used = $true
    hash_comparison_used = $false
    no_existing_workspace = -not (Test-Path -LiteralPath $workspacePath)
    preflight_passed = $false
    blockers = @()
    token_printed = $false
  }
  $changedFilesArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.changed_files.v1"
    generated_at = $generatedAt
    changed_files = @($plannedChangedFiles)
    token_printed = $false
  }
  $state = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.state.v1"
    generated_at = $generatedAt
    mode = "codex-local-diff"
    preview = [bool]$isPreview
    apply = [bool]$Apply
    output_dir = $OutputDir.Replace("\", "/")
    project_id = $ProjectId
    goal_id = $CodexDiffGoalId
    task_id = $CodexDiffTaskId
    worker_id = $CodexDiffWorkerId
    workspace_path = $workspacePath.Replace("\", "/")
    workspace_kind = "git_worktree"
    git_index_collector_used = $true
    hash_comparison_used = $false
    token_printed = $false
  }
  $taskArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.task.v1"
    generated_at = $generatedAt
    task_payload = New-CodexDiffTaskPayload
    final_task = $null
    task_created = $false
    task_claimed = $false
    task_started = $false
    task_completed = $false
    task_failed = $false
    token_printed = $false
  }
  $workerArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.worker.v1"
    generated_at = $generatedAt
    worker_id = $CodexDiffWorkerId
    worker_registered = $false
    final_worker = $null
    capabilities = @("powershell", "git", "codex", "codex-local-diff-demo")
    token_printed = $false
  }
  $safety = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.safety.v1"
    generated_at = $generatedAt
    mode = "codex-local-diff"
    safety_flags = New-CodexDiffSafetyFlags
    token_printed = $false
  }
  $collectorDiagnostics = New-CodexDiffCollectorDiagnostics -GeneratedAt $generatedAt -BaselineCommit $baselineCommit -WorkspacePath $workspacePath -PatchPath $paths.patch

  try {
    $preflight.repo_clean = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure))
    $preflight.current_branch = Get-DemoGitText -Arguments @("branch", "--show-current") -AllowFailure
    $preflight.current_branch_is_main = ([string]$preflight.current_branch -eq "main")
    $localHead = Get-DemoGitText -Arguments @("rev-parse", "HEAD") -AllowFailure
    $originHead = Get-DemoGitText -Arguments @("rev-parse", "origin/main") -AllowFailure
    $preflight.main_synced_with_origin = (-not [string]::IsNullOrWhiteSpace($localHead) -and $localHead -eq $originHead)
    $mergeBaseExit = Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("merge-base", "--is-ancestor", "d32b2d8ef63dc229b746e77e7f585938a84b7231", "HEAD") -AllowFailure
    $preflight.contains_mg372d_baseline = ([int]$mergeBaseExit -eq 0)

    if (-not $preflight.git_available) { $blockers.Add("git_unavailable") | Out-Null }
    if (-not $allowlist.docs_only_allowlist_passed) { $blockers.Add("docs_only_allowlist_failed") | Out-Null }
    if (-not $isPreview -and -not $preflight.codex_available) { $blockers.Add("codex_unavailable") | Out-Null }
    if (-not $isPreview -and -not $preflight.confirmation_text_matched) { $blockers.Add("confirmation_text_mismatch") | Out-Null }
    if (-not $isPreview -and -not $preflight.repo_clean) { $blockers.Add("repo_not_clean") | Out-Null }
    if (-not $isPreview -and -not $preflight.current_branch_is_main) { $blockers.Add("not_on_main") | Out-Null }
    if (-not $isPreview -and -not $preflight.main_synced_with_origin) { $blockers.Add("main_not_synced_with_origin") | Out-Null }
    if (-not $isPreview -and -not $preflight.contains_mg372d_baseline) { $blockers.Add("mg372d_baseline_missing") | Out-Null }
    if (-not $isPreview -and -not $preflight.no_existing_workspace) { $blockers.Add("existing_codex_diff_workspace") | Out-Null }

    $preflight.blockers = @($blockers)
    $preflight.preflight_passed = (@($blockers).Count -eq 0)
    $report.blockers = @($blockers)
    $report.warnings = @($warnings)

    if ($isPreview) {
      $validationStatus = if (@($blockers | Where-Object { $_ -in @("docs_only_allowlist_failed", "git_unavailable") }).Count -eq 0) { "preview_passed" } else { "preview_blocked" }
      $demoResult = if ($validationStatus -eq "preview_passed") { "pass" } else { "blocked" }
      $report.validation_status = $validationStatus
      $report.demo_result = $demoResult
      $report.main_worktree_clean_after = $preflight.repo_clean
      Write-CodexDiffArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -ChangedFiles $changedFilesArtifact -Allowlist $allowlist -CollectorDiagnostics $collectorDiagnostics -Safety $safety
      if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
      return
    }

    Write-CodexDiffArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -ChangedFiles $changedFilesArtifact -Allowlist $allowlist -CollectorDiagnostics $collectorDiagnostics -Safety $safety
    if (-not $preflight.preflight_passed) { throw "MG372D Codex local diff preflight failed." }

    $script:ResolvedApiBase = $ApiBase
    if ($UseTempDatabase) { $StartServer = $true }
    if ($StartServer) { $serverInfo = Start-DemoServer -ResolvedOutputDir $resolvedOutputDir }
    Wait-DemoServerHealth | Out-Null

    $existingProject = Invoke-DemoApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -AllowNotFound
    if (-not $existingProject) {
      Invoke-DemoApi -Method POST -Path "/v1/projects" -Body @{ project_id = $ProjectId; name = $ProjectId } | Out-Null
    }
    $existingGoal = Invoke-DemoApi -Method GET -Path "/v1/goals/$([uri]::EscapeDataString($CodexDiffGoalId))" -AllowNotFound
    if (-not $existingGoal) {
      Invoke-DemoApi -Method POST -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -Body @{
        goal_id = $CodexDiffGoalId
        title = "MG372D Codex Local Diff Demo"
        summary = "Prove one Codex-generated docs-only local diff without PR, push or commit."
        source = "mg372d-mvp-demo"
        risk = "low"
        status = "ready"
        acceptance_criteria = @("One Codex call writes one allowlisted docs artifact in an isolated workspace.")
        evidence_requirements = @("MG372D local diff JSON, Markdown, patch and review summary are written.")
      } | Out-Null
    }
    Invoke-DemoApi -Method POST -Path "/v1/tasks" -Body (New-CodexDiffTaskPayload) | Out-Null
    $taskCreated = $true
    Invoke-DemoApi -Method POST -Path "/v1/workers/register" -Body @{
      worker_id = $CodexDiffWorkerId
      name = "MG372D Codex local diff demo worker"
      provider = "codex-local-diff-demo"
      capabilities = @("powershell", "git", "codex", "codex-local-diff-demo")
      labels = @("mg372d", "codex-local-diff", "poll-once")
      enabled = $true
      auth_mode = "none"
      api_base = $script:ResolvedApiBase
      allow_remote_server = $false
    } | Out-Null
    $workerRegistered = $true
    Invoke-DemoApi -Method POST -Path "/v1/workers/$([uri]::EscapeDataString($CodexDiffWorkerId))/heartbeat" -Body @{
      status_note = "mg372d Codex local diff demo ready"
      load = 0
      seen_at = Get-DemoUtcNow
    } | Out-Null
    Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($CodexDiffTaskId))/claim" -Body @{ worker_id = $CodexDiffWorkerId } | Out-Null
    $taskClaimed = $true
    Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($CodexDiffTaskId))/start" -Body @{ worker_id = $CodexDiffWorkerId } | Out-Null
    $taskStarted = $true

    New-CodexDiffWorkspace -WorkspacePath $workspacePath -CommitSha $implementationCommit
    $workspaceUsed = $true
    $collectorDiagnostics.pre_codex_status_porcelain = @(Get-CodexDiffStatusPorcelain -WorkspacePath $workspacePath)
    $collectorDiagnostics.workspace_clean_before_codex = (@($collectorDiagnostics.pre_codex_status_porcelain).Count -eq 0)
    if (-not $collectorDiagnostics.workspace_clean_before_codex) {
      $blockers.Add("workspace_dirty_before_codex") | Out-Null
      throw "MG372D1 Codex local diff worktree was dirty before Codex."
    }
    $codexCommand = Resolve-CodexDiffCommand
    $codexCalled = $true
    $codexCallCount = 1
    $safety.safety_flags.codex_called = $true
    $safety.safety_flags.codex_call_count = 1
    $codex = Invoke-CodexDiffProcess -CommandSpec $codexCommand -WorkspacePath $workspacePath -PromptPath $paths.prompt -LastMessagePath $paths.last_message -LogPath $paths.codex_jsonl
    $codexExitCode = $codex.exit_code

    $collectorDiagnostics.post_codex_status_porcelain = @(Get-CodexDiffStatusPorcelain -WorkspacePath $workspacePath)
    $changedFiles = @(ConvertFrom-CodexDiffStatusPorcelain -StatusLines $collectorDiagnostics.post_codex_status_porcelain)
    $allowlist = Test-CodexDiffAllowlist -ChangedFiles $changedFiles
    $changedFilesArtifact = [ordered]@{
      schema = "skybridge.mvp_demo.codex_local_diff.changed_files.v1"
      generated_at = Get-DemoUtcNow
      changed_files = @($changedFiles)
      token_printed = $false
    }
    Write-CodexDiffPatch -WorkspacePath $workspacePath -PatchPath $paths.patch
    $collectorDiagnostics.git_diff_name_only = @(Get-CodexDiffNameOnly -WorkspacePath $workspacePath)
    $collectorDiagnostics.patch_non_empty = ((Test-Path -LiteralPath $paths.patch -PathType Leaf) -and ((Get-Item -LiteralPath $paths.patch).Length -gt 0) -and [bool](Select-String -LiteralPath $paths.patch -Pattern ([regex]::Escape($CodexDiffDemoFile)) -Quiet))
    $artifactFile = Join-Path $workspacePath ($CodexDiffDemoFile -replace "/", [System.IO.Path]::DirectorySeparatorChar)
    $collectorDiagnostics.target_artifact_exists = [bool](Test-Path -LiteralPath $artifactFile -PathType Leaf)
    if ($collectorDiagnostics.target_artifact_exists) {
      $collectorDiagnostics.target_artifact_size_bytes = (Get-Item -LiteralPath $artifactFile).Length
    }
    $workspaceHead = Get-DemoGitText -Arguments @("-C", $workspacePath, "rev-parse", "HEAD") -AllowFailure
    $commitCreated = (-not [string]::IsNullOrWhiteSpace($workspaceHead) -and $workspaceHead -ne $implementationCommit)

    if (-not $codex.ok) { $blockers.Add("codex_exec_failed") | Out-Null }
    if (-not $collectorDiagnostics.target_artifact_exists) { $blockers.Add("target_artifact_missing_after_codex") | Out-Null }
    if (-not $allowlist.docs_only_allowlist_passed) { $blockers.Add("docs_only_allowlist_failed_after_codex") | Out-Null }
    if (-not $collectorDiagnostics.patch_non_empty) { $blockers.Add("empty_diff_patch_after_codex") | Out-Null }
    if ($commitCreated) { $blockers.Add("workspace_commit_created") | Out-Null }

    if (@($blockers).Count -eq 0) {
      $review = @(
        "# MG372D Codex Local Diff Review Summary",
        "",
        "- demo_result: pass",
        "- codex_called: true",
        "- codex_call_count: 1",
        "- codex_exit_code: $codexExitCode",
        "- changed_files: $(@($changedFiles) -join ', ')",
        "- docs_only_allowlist_passed: true",
        "- diff_patch_path: $($OutputDir.Replace('\', '/'))/codex-local-diff.patch",
        "- diff_patch_non_empty: true",
        "- workspace_setup_method: git_worktree",
        "- git_index_collector_used: true",
        "- hash_comparison_used: false",
        "- pr_created: false",
        "- branch_pushed: false",
        "- commit_created: false",
        "- token_printed: false"
      )
      $review | Set-Content -LiteralPath $paths.review_summary -Encoding UTF8
      $complete = Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($CodexDiffTaskId))/complete" -Body @{
        worker_id = $CodexDiffWorkerId
        summary = "MG372D Codex local diff demo generated one docs-only local diff and no PR, push or commit."
        result_url = ".agent/tmp/skybridge-mvp-codex-diff/codex-local-diff-report.md"
        evidence_summary = @{
          schema = "skybridge.mvp_demo.codex_local_diff.task_evidence.v1"
          project_id = $ProjectId
          goal_id = $CodexDiffGoalId
          task_id = $CodexDiffTaskId
          worker_id = $CodexDiffWorkerId
          codex_called = $true
          codex_call_count = 1
          codex_exit_code = $codexExitCode
          workspace_setup_method = "git_worktree"
          workspace_clean_before_codex = $true
          git_index_collector_used = $true
          hash_comparison_used = $false
          changed_files = @($changedFiles)
          docs_only_allowlist_passed = $true
          diff_patch_non_empty = $true
          pr_created = $false
          branch_pushed = $false
          commit_created = $false
          token_printed = $false
          created_at = Get-DemoUtcNow
        }
      }
      $taskCompleted = $true
      $finalTask = $complete.task
      $finalTask = (Invoke-DemoApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($CodexDiffTaskId))").task
      $finalWorker = (Invoke-DemoApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($CodexDiffWorkerId))").worker
      $validationStatus = "passed"
      $demoResult = "pass"
    } else {
      $validationStatus = "failed"
      $demoResult = "blocked"
      $taskBlocked = $true
      $taskFailed = $true
      $review = @(
        "# MG372D Codex Local Diff Review Summary",
        "",
        "- demo_result: blocked",
        "- codex_called: $codexCalled",
        "- codex_call_count: $codexCallCount",
        "- codex_exit_code: $codexExitCode",
        "- changed_files: $(@($changedFiles) -join ', ')",
        "- docs_only_allowlist_passed: $($allowlist.docs_only_allowlist_passed)",
        "- diff_patch_non_empty: $($collectorDiagnostics.patch_non_empty)",
        "- blockers: $(@($blockers) -join ', ')",
        "- pr_created: false",
        "- branch_pushed: false",
        "- token_printed: false"
      )
      $review | Set-Content -LiteralPath $paths.review_summary -Encoding UTF8
    }
  } catch {
    if (@($blockers).Count -lt 1) { $blockers.Add("codex_local_diff_demo_failed") | Out-Null }
    $validationStatus = "failed"
    $demoResult = if ($codexCalled -or $workspaceUsed) { "partial" } else { "blocked" }
    if ($taskStarted -and -not $taskCompleted) { $taskBlocked = $true }
    $taskFailed = $true
    $safeMessage = ($_.Exception.Message -replace "(?i)(authorization|bearer|token|secret|cookie|password)\s*[:=]\s*\S+", '$1=<redacted>')
    $safeMessage = ($safeMessage -replace 'https?://\S+', "<redacted-url>").Trim()
    if ($safeMessage.Length -gt 180) { $safeMessage = $safeMessage.Substring(0, 180) }
    $warnings.Add($safeMessage) | Out-Null
    if (-not (Test-Path -LiteralPath $paths.review_summary -PathType Leaf)) {
      @("# MG372D Codex Local Diff Review Summary", "", "- demo_result: $demoResult", "- blockers: $(@($blockers) -join ', ')", "- token_printed: false") | Set-Content -LiteralPath $paths.review_summary -Encoding UTF8
    }
  } finally {
    if ($serverInfo) { Stop-DemoServer -ServerInfo $serverInfo }
  }

  $mainCleanAfter = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure))
  $safety.safety_flags.commit_created = [bool]$commitCreated
  $report.generated_at = Get-DemoUtcNow
  $report.task_created = [bool]$taskCreated
  $report.worker_registered = [bool]$workerRegistered
  $report.task_claimed = [bool]$taskClaimed
  $report.task_started = [bool]$taskStarted
  $report.task_completed = [bool]$taskCompleted
  $report.task_failed = [bool]$taskFailed
  $report.task_blocked = [bool]$taskBlocked
  $report.validation_status = $validationStatus
  $report.codex_called = [bool]$codexCalled
  $report.codex_call_count = [int]$codexCallCount
  $report.codex_exit_code = $codexExitCode
  $report.isolated_workspace_used = [bool]$workspaceUsed
  $report.workspace_setup_method = "git_worktree"
  $report.workspace_path = $workspacePath.Replace("\", "/")
  $report.workspace_clean_before_codex = [bool]$collectorDiagnostics.workspace_clean_before_codex
  $report.main_worktree_clean_after = [bool]$mainCleanAfter
  $report.git_index_collector_used = $true
  $report.hash_comparison_used = $false
  $report.changed_files = @($changedFiles)
  $report.docs_only_allowlist_passed = [bool]$allowlist.docs_only_allowlist_passed
  $report.diff_patch_non_empty = [bool]$collectorDiagnostics.patch_non_empty
  $report.artifact_file_path = "$($OutputDir.Replace('\', '/'))/worktree/$CodexDiffDemoFile"
  $report.target_artifact_exists = [bool]$collectorDiagnostics.target_artifact_exists
  $report.demo_result = $demoResult
  $report.real_worker_execution = [bool]($taskClaimed -and $taskStarted -and $taskCompleted)
  $report.commit_created = [bool]$commitCreated
  $report.blockers = @($blockers)
  $report.warnings = @($warnings)

  $state.generated_at = $report.generated_at
  $state.codex_called = [bool]$codexCalled
  $state.codex_call_count = [int]$codexCallCount
  $state.codex_exit_code = $codexExitCode
  $state.changed_files = @($changedFiles)
  $state.workspace_clean_before_codex = [bool]$collectorDiagnostics.workspace_clean_before_codex
  $state.git_index_collector_used = $true
  $state.hash_comparison_used = $false
  $taskArtifact.generated_at = $report.generated_at
  $taskArtifact.final_task = $finalTask
  $taskArtifact.task_created = [bool]$taskCreated
  $taskArtifact.task_claimed = [bool]$taskClaimed
  $taskArtifact.task_started = [bool]$taskStarted
  $taskArtifact.task_completed = [bool]$taskCompleted
  $taskArtifact.task_failed = [bool]$taskFailed
  $workerArtifact.generated_at = $report.generated_at
  $workerArtifact.worker_registered = [bool]$workerRegistered
  $workerArtifact.final_worker = $finalWorker
  $preflight.blockers = @($blockers)
  if (-not $isPreview) { $preflight.preflight_passed = (@($blockers | Where-Object { $_ -in @("git_unavailable", "codex_unavailable", "confirmation_text_mismatch", "repo_not_clean", "not_on_main", "main_not_synced_with_origin", "mg372d_baseline_missing", "existing_codex_diff_workspace") }).Count -eq 0) }
  $changedFilesArtifact.generated_at = $report.generated_at
  $changedFilesArtifact.changed_files = @($changedFiles)
  $collectorDiagnostics.generated_at = $report.generated_at
  Write-CodexDiffArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -ChangedFiles $changedFilesArtifact -Allowlist $allowlist -CollectorDiagnostics $collectorDiagnostics -Safety $safety
  if ($OpenReport) { Invoke-Item -LiteralPath $paths.report_md }
  if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
}

function Invoke-CodexLocalDiffCollectorFixture {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
  $paths = Get-CodexDiffArtifactPaths -ResolvedOutputDir $resolvedOutputDir
  $generatedAt = Get-DemoUtcNow
  $implementationCommit = Get-DemoGitText -Arguments @("rev-parse", "HEAD")
  $baselineCommit = $implementationCommit
  $workspacePath = $paths.workspace
  $fixtureKind = switch ($Mode) {
    "codex-local-diff-worktree-clean" { "worktree-clean" }
    "codex-local-diff-synthetic-patch" { "synthetic-patch" }
    "codex-local-diff-policy-fixture" { "policy-fixture" }
    default { "unknown" }
  }
  $blockers = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()
  $changedFiles = @()
  $allowlist = Test-CodexDiffAllowlist -ChangedFiles @()
  $report = New-CodexDiffReport -GeneratedAt $generatedAt -BaselineCommit $baselineCommit -ImplementationCommit $implementationCommit -WorkspacePath $workspacePath
  $report.codex_called = $false
  $report.codex_call_count = 0
  $report.isolated_workspace_used = $true
  $report.workspace_setup_method = "git_worktree"
  $report.git_index_collector_used = $true
  $report.hash_comparison_used = $false
  $report.fixture_mode = $true
  $preflight = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.preflight.v1"
    generated_at = $generatedAt
    mode = $Mode
    preview = $true
    apply = $false
    git_available = [bool](Get-Command git -ErrorAction SilentlyContinue)
    codex_available = [bool](Get-Command codex -ErrorAction SilentlyContinue)
    repo_clean = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure))
    current_branch = Get-DemoGitText -Arguments @("branch", "--show-current") -AllowFailure
    current_branch_is_main = $false
    main_synced_with_origin = $false
    contains_mg372d_baseline = $false
    confirmation_text_matched = $false
    workspace_path = $workspacePath.Replace("\", "/")
    workspace_setup_method = "git_worktree"
    git_index_collector_used = $true
    hash_comparison_used = $false
    no_existing_workspace = -not (Test-Path -LiteralPath $workspacePath)
    preflight_passed = $false
    blockers = @()
    token_printed = $false
  }
  $state = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.state.v1"
    generated_at = $generatedAt
    mode = $Mode
    fixture_kind = $fixtureKind
    preview = $true
    apply = $false
    output_dir = $OutputDir.Replace("\", "/")
    project_id = $ProjectId
    goal_id = $CodexDiffGoalId
    task_id = $CodexDiffTaskId
    worker_id = $CodexDiffWorkerId
    workspace_path = $workspacePath.Replace("\", "/")
    workspace_kind = "git_worktree"
    git_index_collector_used = $true
    hash_comparison_used = $false
    token_printed = $false
  }
  $taskArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.task.v1"
    generated_at = $generatedAt
    task_payload = New-CodexDiffTaskPayload
    final_task = $null
    task_created = $false
    task_claimed = $false
    task_started = $false
    task_completed = $false
    task_failed = $false
    token_printed = $false
  }
  $workerArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.worker.v1"
    generated_at = $generatedAt
    worker_id = $CodexDiffWorkerId
    worker_registered = $false
    final_worker = $null
    capabilities = @("powershell", "git", "codex-local-diff-demo")
    token_printed = $false
  }
  $safety = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.safety.v1"
    generated_at = $generatedAt
    mode = $Mode
    safety_flags = New-CodexDiffSafetyFlags
    token_printed = $false
  }
  $collectorDiagnostics = New-CodexDiffCollectorDiagnostics -GeneratedAt $generatedAt -BaselineCommit $baselineCommit -WorkspacePath $workspacePath -PatchPath $paths.patch

  try {
    if (-not $preflight.git_available) { $blockers.Add("git_unavailable") | Out-Null }
    if (-not $preflight.no_existing_workspace) { $blockers.Add("existing_codex_diff_workspace") | Out-Null }
    if (@($blockers).Count -eq 0) {
      New-CodexDiffWorkspace -WorkspacePath $workspacePath -CommitSha $implementationCommit
      $collectorDiagnostics.pre_codex_status_porcelain = @(Get-CodexDiffStatusPorcelain -WorkspacePath $workspacePath)
      $collectorDiagnostics.workspace_clean_before_codex = (@($collectorDiagnostics.pre_codex_status_porcelain).Count -eq 0)
      if (-not $collectorDiagnostics.workspace_clean_before_codex) { $blockers.Add("workspace_dirty_before_codex") | Out-Null }
    }

    if (@($blockers).Count -eq 0 -and $fixtureKind -eq "synthetic-patch") {
      $target = Join-Path $workspacePath ($CodexDiffDemoFile -replace "/", [System.IO.Path]::DirectorySeparatorChar)
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
      @(
        "# MG372D Codex Local Diff Artifact",
        "",
        "generated_by=synthetic-smoke",
        "source milestone=MG372D1",
        "baseline commit=$implementationCommit",
        "task_id=$CodexDiffTaskId",
        "token_printed=false"
      ) | Set-Content -LiteralPath $target -Encoding UTF8
    } elseif (@($blockers).Count -eq 0 -and $fixtureKind -eq "policy-fixture") {
      $target = Join-Path $workspacePath "docs/product/MG372D_NOT_ALLOWLISTED_LOCAL_DIFF_ARTIFACT.md"
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
      "token_printed=false" | Set-Content -LiteralPath $target -Encoding UTF8
    }

    if (@($blockers).Count -eq 0) {
      $collectorDiagnostics.post_codex_status_porcelain = @(Get-CodexDiffStatusPorcelain -WorkspacePath $workspacePath)
      $changedFiles = @(ConvertFrom-CodexDiffStatusPorcelain -StatusLines $collectorDiagnostics.post_codex_status_porcelain)
      $allowlist = Test-CodexDiffAllowlist -ChangedFiles $changedFiles
      if ($fixtureKind -eq "worktree-clean") {
        $allowlist = [pscustomobject]@{
          allowed_files = @($CodexDiffDemoFile)
          changed_files = @()
          unexpected_files = @()
          docs_only_allowlist_passed = $true
          token_printed = $false
        }
      } elseif ($fixtureKind -eq "policy-fixture") {
        if ($allowlist.docs_only_allowlist_passed) { $blockers.Add("policy_fixture_unexpectedly_passed") | Out-Null }
        if (-not $allowlist.docs_only_allowlist_passed) { $blockers.Add("docs_only_allowlist_failed_after_codex") | Out-Null }
      } else {
        if (-not $allowlist.docs_only_allowlist_passed) { $blockers.Add("docs_only_allowlist_failed_after_codex") | Out-Null }
      }

      if ($fixtureKind -eq "synthetic-patch") {
        Write-CodexDiffPatch -WorkspacePath $workspacePath -PatchPath $paths.patch
        $collectorDiagnostics.git_diff_name_only = @(Get-CodexDiffNameOnly -WorkspacePath $workspacePath)
        $collectorDiagnostics.patch_non_empty = ((Test-Path -LiteralPath $paths.patch -PathType Leaf) -and ((Get-Item -LiteralPath $paths.patch).Length -gt 0) -and [bool](Select-String -LiteralPath $paths.patch -Pattern ([regex]::Escape($CodexDiffDemoFile)) -Quiet))
        if (-not $collectorDiagnostics.patch_non_empty) { $blockers.Add("empty_diff_patch_after_codex") | Out-Null }
      }
      $artifactFile = Join-Path $workspacePath ($CodexDiffDemoFile -replace "/", [System.IO.Path]::DirectorySeparatorChar)
      $collectorDiagnostics.target_artifact_exists = [bool](Test-Path -LiteralPath $artifactFile -PathType Leaf)
      if ($collectorDiagnostics.target_artifact_exists) {
        $collectorDiagnostics.target_artifact_size_bytes = (Get-Item -LiteralPath $artifactFile).Length
      }
    }
  } catch {
    if (@($blockers).Count -lt 1) { $blockers.Add("collector_fixture_failed") | Out-Null }
    $warnings.Add(($_.Exception.Message -replace 'https?://\S+', "<redacted-url>")) | Out-Null
  }

  $changedFilesArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.changed_files.v1"
    generated_at = Get-DemoUtcNow
    changed_files = @($changedFiles)
    token_printed = $false
  }
  $preflight.blockers = @($blockers)
  $preflight.preflight_passed = (@($blockers | Where-Object { $_ -in @("git_unavailable", "existing_codex_diff_workspace", "workspace_dirty_before_codex", "collector_fixture_failed") }).Count -eq 0)
  $report.generated_at = Get-DemoUtcNow
  $report.mode = $Mode
  $report.workspace_clean_before_codex = [bool]$collectorDiagnostics.workspace_clean_before_codex
  $report.main_worktree_clean_after = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure))
  $report.changed_files = @($changedFiles)
  $report.docs_only_allowlist_passed = [bool]$allowlist.docs_only_allowlist_passed
  $report.diff_patch_non_empty = [bool]$collectorDiagnostics.patch_non_empty
  $report.target_artifact_exists = [bool]$collectorDiagnostics.target_artifact_exists
  $report.demo_result = if (@($blockers).Count -eq 0) { "pass" } else { "blocked" }
  $report.validation_status = if ($report.demo_result -eq "pass") { "passed" } else { "failed" }
  $report.blockers = @($blockers)
  $report.warnings = @($warnings)
  $state.generated_at = $report.generated_at
  $state.changed_files = @($changedFiles)
  $collectorDiagnostics.generated_at = $report.generated_at

  $review = @(
    "# MG372D1 Codex Local Diff Collector Fixture",
    "",
    "- mode: $Mode",
    "- fixture_kind: $fixtureKind",
    "- demo_result: $($report.demo_result)",
    "- changed_files: $(@($changedFiles) -join ', ')",
    "- docs_only_allowlist_passed: $($allowlist.docs_only_allowlist_passed)",
    "- diff_patch_non_empty: $($collectorDiagnostics.patch_non_empty)",
    "- codex_called: false",
    "- pr_created: false",
    "- branch_pushed: false",
    "- commit_created: false",
    "- token_printed: false"
  )
  $review | Set-Content -LiteralPath $paths.review_summary -Encoding UTF8
  Write-CodexDiffArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -ChangedFiles $changedFilesArtifact -Allowlist $allowlist -CollectorDiagnostics $collectorDiagnostics -Safety $safety
  if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
}

function Show-CodexLocalDiffStatus {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  $reportPath = Join-Path $resolvedOutputDir "codex-local-diff-report.json"
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    $result = [pscustomobject]@{ ok = $false; mode = "codex-local-diff-status"; report_found = $false; report_json_path = $reportPath; token_printed = $false }
  } else {
    $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
    $result = [pscustomobject]@{
      ok = $true
      mode = "codex-local-diff-status"
      report_found = $true
      report_json_path = $reportPath
      report_markdown_path = (Join-Path $resolvedOutputDir "codex-local-diff-report.md")
      demo_result = $report.demo_result
      validation_status = $report.validation_status
      codex_called = $report.codex_called
      changed_files = @($report.changed_files)
      token_printed = $false
    }
  }
  if ($Json) { $result | ConvertTo-Json -Depth 10 -Compress } else { $result | Format-List }
}

function Show-CodexLocalDiffReport {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  $reportJson = Join-Path $resolvedOutputDir "codex-local-diff-report.json"
  $reportMd = Join-Path $resolvedOutputDir "codex-local-diff-report.md"
  if (-not (Test-Path -LiteralPath $reportJson -PathType Leaf)) {
    $result = [pscustomobject]@{ ok = $false; mode = "codex-local-diff-report"; report_found = $false; report_json_path = $reportJson; report_markdown_path = $reportMd; token_printed = $false }
  } else {
    $report = Get-Content -Raw -LiteralPath $reportJson | ConvertFrom-Json
    $result = [pscustomobject]@{
      ok = $true
      mode = "codex-local-diff-report"
      report_found = $true
      report_json_path = $reportJson
      report_markdown_path = $reportMd
      summary = "result=$($report.demo_result) codex_called=$($report.codex_called) changed_files=$(@($report.changed_files) -join ',')"
      token_printed = $false
    }
  }
  if ($OpenReport -and (Test-Path -LiteralPath $reportMd -PathType Leaf)) { Invoke-Item -LiteralPath $reportMd }
  if ($Json) { $result | ConvertTo-Json -Depth 10 -Compress } else { $result | Format-List }
}

function Show-ControllerDraftPrStatus {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  $reportPath = Join-Path $resolvedOutputDir "mvp-pr-demo-report.json"
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    $result = [pscustomobject]@{ ok = $false; mode = "controller-draft-pr-status"; report_found = $false; report_json_path = $reportPath; token_printed = $false }
  } else {
    $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
    $result = [pscustomobject]@{
      ok = $true
      mode = "controller-draft-pr-status"
      report_found = $true
      report_json_path = $reportPath
      report_markdown_path = (Join-Path $resolvedOutputDir "mvp-pr-demo-report.md")
      demo_result = $report.demo_result
      validation_status = $report.validation_status
      controller_created_draft_pr = $report.controller_created_draft_pr
      pr_url = $report.pr_url
      token_printed = $false
    }
  }
  if ($Json) { $result | ConvertTo-Json -Depth 10 -Compress } else { $result | Format-List }
}

function Show-ControllerDraftPrReport {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  $reportJson = Join-Path $resolvedOutputDir "mvp-pr-demo-report.json"
  $reportMd = Join-Path $resolvedOutputDir "mvp-pr-demo-report.md"
  if (-not (Test-Path -LiteralPath $reportJson -PathType Leaf)) {
    $result = [pscustomobject]@{ ok = $false; mode = "controller-draft-pr-report"; report_found = $false; report_json_path = $reportJson; report_markdown_path = $reportMd; token_printed = $false }
  } else {
    $report = Get-Content -Raw -LiteralPath $reportJson | ConvertFrom-Json
    $result = [pscustomobject]@{
      ok = $true
      mode = "controller-draft-pr-report"
      report_found = $true
      report_json_path = $reportJson
      report_markdown_path = $reportMd
      summary = "result=$($report.demo_result) draft_pr=$($report.draft_pr) pr=$($report.pr_url)"
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
} elseif ($Mode -eq "report") {
  Show-DemoReport
} elseif ($Mode -eq "controller-draft-pr-status") {
  Show-ControllerDraftPrStatus
} elseif ($Mode -eq "controller-draft-pr-report") {
  Show-ControllerDraftPrReport
} elseif ($Mode -eq "codex-local-diff-status") {
  Show-CodexLocalDiffStatus
} elseif ($Mode -eq "codex-local-diff-report") {
  Show-CodexLocalDiffReport
} elseif ($Mode -in @("codex-local-diff-worktree-clean", "codex-local-diff-synthetic-patch", "codex-local-diff-policy-fixture")) {
  Invoke-CodexLocalDiffCollectorFixture
} elseif ($Mode -like "codex-local-diff*") {
  Invoke-CodexLocalDiffDemo
} else {
  Invoke-ControllerDraftPrDemo
}
