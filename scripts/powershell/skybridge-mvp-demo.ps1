[CmdletBinding()]
param(
  [ValidateSet("local-safe", "status", "report", "controller-draft-pr", "controller-draft-pr-preview", "controller-draft-pr-status", "controller-draft-pr-report", "codex-local-diff", "codex-local-diff-preview", "codex-local-diff-status", "codex-local-diff-report", "codex-local-diff-worktree-clean", "codex-local-diff-synthetic-patch", "codex-local-diff-policy-fixture", "codex-local-diff-timeout-fixture", "codex-local-diff-mock-success", "codex-local-diff-mock-disallowed-file", "codex-local-diff-cleanup-safety", "codex-diff-draft-pr", "codex-diff-draft-pr-preview", "codex-diff-draft-pr-status", "codex-diff-draft-pr-report")]
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
  [string]$ConfirmationText = "",
  [int]$CodexTimeoutSeconds = 900,
  [string]$CodexSandbox = "workspace-write",
  [bool]$KeepCodexWorktree = $true,
  [switch]$CleanExistingCodexWorktree,
  [switch]$ArchiveExistingCodexWorktree,
  [string]$SourceReportPath = ".agent/tmp/skybridge-mvp-codex-diff/codex-local-diff-report.json",
  [string]$SourcePatchPath = ".agent/tmp/skybridge-mvp-codex-diff/codex-local-diff.patch",
  [string]$SourceArtifactPath = ".agent/tmp/skybridge-mvp-codex-diff/worktree/docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md"
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
$CodexDiffSchema = "skybridge.mvp_demo.codex_local_diff.v4"
$CodexDiffOutputDir = ".agent/tmp/skybridge-mvp-codex-diff"
$CodexDiffGoalId = "mg372d2r-codex-local-diff-worktree-cleanup-rerun"
$CodexDiffTaskId = "mg372d-codex-local-diff-task-001"
$CodexDiffWorkerId = "mg372d2r-codex-local-diff-worker"
$CodexDiffConfirmationText = "I_UNDERSTAND_AUTHORIZE_MG372D2R_CLEAN_STALE_CODEX_DIFF_WORKTREE_AND_RERUN_CODEX_ONCE"
$CodexDiffDemoFile = "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md"
$CodexDraftPrSchema = "skybridge.mvp_demo.codex_generated_draft_pr.v1"
$CodexDraftPrOutputDir = ".agent/tmp/skybridge-mvp-codex-draft-pr"
$CodexDraftPrGoalId = "mg372e2-codex-generated-draft-pr-demo"
$CodexDraftPrTaskId = "mg372e2-codex-generated-draft-pr-task-001"
$CodexDraftPrWorkerId = "mg372e2-codex-draft-pr-worker"
$CodexDraftPrConfirmationText = "I_UNDERSTAND_AUTHORIZE_MG372E2_CREATE_ONE_CODEX_GENERATED_DOCS_ONLY_DRAFT_PR_DEMO"
$CodexDraftPrCommitMessage = "docs(demo): add MG372E2 Codex-generated draft PR artifact"
$CodexDraftPrTitle = "MG372E2 Demo: Codex-generated Draft PR"
$CodexDraftPrImplementationBaseline = "59454cca78febc679de713b1c347b1352e84a039"
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
  "codex-local-diff-stdout.log",
  "codex-local-diff-stderr.log",
  "codex-local-diff-last-message.md",
  "codex-local-diff-changed-files.json",
  "codex-local-diff-allowlist-check.json",
  "codex-local-diff-review-summary.md",
  "codex-local-diff.patch",
  "codex-local-diff-safety.json",
  "codex-local-diff-collector-diagnostics.json",
  "codex-local-diff-execution-diagnostics.json",
  "codex-local-diff-failure-classification.json",
  "codex-local-diff-cleanup-report.json",
  "codex-local-diff-cleanup-report.md",
  "codex-local-diff-worktree-list-before.txt",
  "codex-local-diff-worktree-list-after.txt",
  "codex-local-diff-cleanup-safety.json",
  "codex-local-diff-artifact-index.json"
)
$CodexDraftPrArtifacts = @(
  "codex-draft-pr-report.json",
  "codex-draft-pr-report.md",
  "codex-draft-pr-state.json",
  "codex-draft-pr-task.json",
  "codex-draft-pr-worker.json",
  "codex-draft-pr-preflight.json",
  "codex-draft-pr-source-diff-validation.json",
  "codex-draft-pr-branch-plan.json",
  "codex-draft-pr-allowlist-check.json",
  "codex-draft-pr-pr-metadata.json",
  "codex-draft-pr-provider-report.json",
  "codex-draft-pr-safety.json",
  "codex-draft-pr-artifact-index.json"
)

if ($Mode -like "controller-draft-pr*" -and -not $PSBoundParameters.ContainsKey("OutputDir")) {
  $OutputDir = $ControllerOutputDir
}
if ($Mode -like "codex-local-diff*" -and -not $PSBoundParameters.ContainsKey("OutputDir")) {
  $OutputDir = $CodexDiffOutputDir
}
if ($Mode -like "codex-diff-draft-pr*" -and -not $PSBoundParameters.ContainsKey("OutputDir")) {
  $OutputDir = $CodexDraftPrOutputDir
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

function Get-CodexDraftPrArtifactPaths {
  param([string]$ResolvedOutputDir)
  [pscustomobject]@{
    report_json = Join-Path $ResolvedOutputDir "codex-draft-pr-report.json"
    report_md = Join-Path $ResolvedOutputDir "codex-draft-pr-report.md"
    state = Join-Path $ResolvedOutputDir "codex-draft-pr-state.json"
    task = Join-Path $ResolvedOutputDir "codex-draft-pr-task.json"
    worker = Join-Path $ResolvedOutputDir "codex-draft-pr-worker.json"
    preflight = Join-Path $ResolvedOutputDir "codex-draft-pr-preflight.json"
    source_validation = Join-Path $ResolvedOutputDir "codex-draft-pr-source-diff-validation.json"
    branch_plan = Join-Path $ResolvedOutputDir "codex-draft-pr-branch-plan.json"
    allowlist = Join-Path $ResolvedOutputDir "codex-draft-pr-allowlist-check.json"
    pr_metadata = Join-Path $ResolvedOutputDir "codex-draft-pr-pr-metadata.json"
    provider = Join-Path $ResolvedOutputDir "codex-draft-pr-provider-report.json"
    safety = Join-Path $ResolvedOutputDir "codex-draft-pr-safety.json"
    index = Join-Path $ResolvedOutputDir "codex-draft-pr-artifact-index.json"
    pr_body = Join-Path $ResolvedOutputDir "codex-draft-pr-body.md"
  }
}

function New-CodexDraftPrSafetyFlags {
  [ordered]@{
    codex_called_in_mg372e2 = $false
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

function Get-CodexDraftPrBranchName {
  $date = (Get-Date).ToUniversalTime().ToString("yyyyMMdd")
  $short = Get-DemoGitText -Arguments @("rev-parse", "--short=7", "HEAD")
  return "demo/mg372e2-codex-draft-pr-$date-$short"
}

function Test-CodexDraftPrBranchPolicy {
  param([string]$BranchName)
  $checks = [ordered]@{
    prefix_demo = $BranchName.StartsWith("demo/")
    milestone_mg372e2 = ($BranchName -match "(^|/)mg372e2-")
    no_spaces = ($BranchName -notmatch "\s")
    no_shell_metacharacters = ($BranchName -match "^[A-Za-z0-9/_-]+$")
    under_80_characters = ($BranchName.Length -lt 80)
    pattern_matched = ($BranchName -match "^demo/mg372e2-codex-draft-pr-[0-9]{8}-[A-Za-z0-9]{7}$")
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

function Test-CodexDraftPrAllowlist {
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

function Get-CodexDraftPrChangedFiles {
  Get-ControllerChangedFiles
}

function Test-CodexDraftPrSourceArtifacts {
  param(
    [string]$ReportPath,
    [string]$PatchPath,
    [string]$ArtifactPath
  )
  $resolvedReport = Resolve-DemoPath $ReportPath
  $resolvedPatch = Resolve-DemoPath $PatchPath
  $resolvedArtifact = Resolve-DemoPath $ArtifactPath
  $blockers = [System.Collections.Generic.List[string]]::new()
  $source = $null
  $patchSize = 0
  $artifactSize = 0
  $patchContainsArtifact = $false

  try {
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) {
      $blockers.Add("source_report_missing") | Out-Null
    } else {
      $source = Get-Content -Raw -LiteralPath $resolvedReport | ConvertFrom-Json
    }
  } catch {
    $blockers.Add("source_report_invalid_json") | Out-Null
  }

  if ($null -ne $source) {
    $changed = @($source.changed_files | ForEach-Object { [string]$_ })
    if ([string]$source.demo_result -ne "pass") { $blockers.Add("source_demo_result_not_pass") | Out-Null }
    if (-not [bool]$source.codex_called) { $blockers.Add("source_codex_not_called") | Out-Null }
    if ([int]$source.codex_call_count -ne 1) { $blockers.Add("source_codex_call_count_not_one") | Out-Null }
    if ([int]$source.codex_exit_code -ne 0) { $blockers.Add("source_codex_exit_code_nonzero") | Out-Null }
    if (@($changed).Count -ne 1 -or [string]$changed[0] -ne $CodexDiffDemoFile) { $blockers.Add("source_changed_files_mismatch") | Out-Null }
    if (-not [bool]$source.docs_only_allowlist_passed) { $blockers.Add("source_docs_only_allowlist_failed") | Out-Null }
    if (-not [bool]$source.diff_patch_non_empty) { $blockers.Add("source_diff_patch_empty") | Out-Null }
    if ([bool]$source.pr_created) { $blockers.Add("source_pr_created") | Out-Null }
    if ([bool]$source.branch_pushed) { $blockers.Add("source_branch_pushed") | Out-Null }
    if ([bool]$source.commit_created) { $blockers.Add("source_commit_created") | Out-Null }
    if ([bool]$source.token_printed) { $blockers.Add("source_token_printed") | Out-Null }
  }

  if (-not (Test-Path -LiteralPath $resolvedPatch -PathType Leaf)) {
    $blockers.Add("source_patch_missing") | Out-Null
  } else {
    $patchItem = Get-Item -LiteralPath $resolvedPatch
    $patchSize = [int64]$patchItem.Length
    if ($patchSize -le 0) { $blockers.Add("source_patch_empty_file") | Out-Null }
    $patchContainsArtifact = [bool](Select-String -LiteralPath $resolvedPatch -Pattern ([regex]::Escape($CodexDiffDemoFile)) -Quiet)
    if (-not $patchContainsArtifact) { $blockers.Add("source_patch_missing_artifact_path") | Out-Null }
  }

  if (-not (Test-Path -LiteralPath $resolvedArtifact -PathType Leaf)) {
    $blockers.Add("source_artifact_missing") | Out-Null
  } else {
    $artifactItem = Get-Item -LiteralPath $resolvedArtifact
    $artifactSize = [int64]$artifactItem.Length
    if ($artifactSize -le 0) { $blockers.Add("source_artifact_empty") | Out-Null }
  }

  [pscustomobject]@{
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.source_validation.v1"
    generated_at = Get-DemoUtcNow
    source_report_path = $ReportPath.Replace("\", "/")
    source_patch_path = $PatchPath.Replace("\", "/")
    source_artifact_path = $ArtifactPath.Replace("\", "/")
    source_report_exists = [bool](Test-Path -LiteralPath $resolvedReport -PathType Leaf)
    source_patch_exists = [bool](Test-Path -LiteralPath $resolvedPatch -PathType Leaf)
    source_artifact_exists = [bool](Test-Path -LiteralPath $resolvedArtifact -PathType Leaf)
    source_patch_size_bytes = [int64]$patchSize
    source_artifact_size_bytes = [int64]$artifactSize
    source_patch_contains_artifact_path = [bool]$patchContainsArtifact
    source_demo_result = if ($null -ne $source) { [string]$source.demo_result } else { "" }
    source_codex_called = if ($null -ne $source) { [bool]$source.codex_called } else { $false }
    source_codex_call_count = if ($null -ne $source) { [int]$source.codex_call_count } else { 0 }
    source_codex_exit_code = if ($null -ne $source -and $null -ne $source.codex_exit_code) { [int]$source.codex_exit_code } else { $null }
    source_changed_files = if ($null -ne $source) { @($source.changed_files | ForEach-Object { [string]$_ }) } else { @() }
    source_docs_only_allowlist_passed = if ($null -ne $source) { [bool]$source.docs_only_allowlist_passed } else { $false }
    source_diff_patch_non_empty = if ($null -ne $source) { [bool]$source.diff_patch_non_empty } else { $false }
    source_pr_created = if ($null -ne $source) { [bool]$source.pr_created } else { $false }
    source_branch_pushed = if ($null -ne $source) { [bool]$source.branch_pushed } else { $false }
    source_commit_created = if ($null -ne $source) { [bool]$source.commit_created } else { $false }
    source_token_printed = if ($null -ne $source) { [bool]$source.token_printed } else { $false }
    source_validation_passed = (@($blockers).Count -eq 0)
    blockers = @($blockers)
    token_printed = $false
  }
}

function New-CodexDraftPrTaskPayload {
  [ordered]@{
    task_id = $CodexDraftPrTaskId
    project_id = $ProjectId
    goal_id = $CodexDraftPrGoalId
    title = "MG372E2 Codex-generated draft PR demo task"
    body = "Package the already validated MG372D2R Codex local docs diff into one controller-created draft PR."
    prompt_summary = "MG372E2 packages validated MG372D2R local diff. No Codex call in MG372E2."
    risk = "low"
    source = "custom"
    task_type = "codex-generated-draft-pr-demo"
    allowed_paths = @($CodexDiffDemoFile, ".agent/tmp/skybridge-mvp-codex-draft-pr/**")
    blocked_paths = @(".env", "secrets/**", ".github/**", "apps/**", "packages/**", "deploy/**", "Dockerfile", "package.json", ".git/**")
    validation = @("validated MG372D2R source diff", "one controller-created branch", "one controller-created commit", "one draft PR", "token_printed=false")
    required_capabilities = @("powershell", "git", "gh", "codex-diff-draft-pr-demo")
    planner_metadata = @{
      adapter = "skybridge-mvp-demo"
      decision = "continue"
      reason = "mg372e2_codex_generated_draft_pr_demo"
      task_type = "codex-generated-draft-pr-demo"
      expected_outputs = @($CodexDiffDemoFile, ".agent/tmp/skybridge-mvp-codex-draft-pr/**")
      source_milestone = "MG372D2R"
      codex_called_in_mg372e2 = $false
      tui_created_branch = $false
      tui_created_pr = $false
      worker_loop_started = $false
      queue_runner_started = $false
      run_forever_started = $false
      token_printed = $false
    }
  }
}

function New-CodexDraftPrReport {
  param(
    [string]$GeneratedAt,
    [string]$BaselineCommit,
    [string]$ImplementationCommit,
    [string]$BranchName,
    [string[]]$ChangedFiles
  )
  $relativeOutput = $OutputDir.Replace("\", "/")
  [ordered]@{
    schema = $CodexDraftPrSchema
    generated_at = $GeneratedAt
    mode = "codex-diff-draft-pr"
    baseline_commit = $BaselineCommit
    implementation_commit = $ImplementationCommit
    source_milestone = "MG372D2R"
    source_report_path = $SourceReportPath.Replace("\", "/")
    source_patch_path = $SourcePatchPath.Replace("\", "/")
    source_artifact_path = $SourceArtifactPath.Replace("\", "/")
    source_codex_called = $true
    source_codex_call_count = 1
    source_codex_exit_code = 0
    source_diff_patch_non_empty = $false
    source_docs_only_allowlist_passed = $false
    project_id = $ProjectId
    goal_id = $CodexDraftPrGoalId
    task_id = $CodexDraftPrTaskId
    worker_id = $CodexDraftPrWorkerId
    task_created = $false
    worker_registered = $false
    task_claimed = $false
    task_started = $false
    task_completed = $false
    task_failed = $false
    task_blocked = $false
    validation_status = "not_run"
    controller_created_branch = $false
    controller_created_commit = $false
    controller_created_draft_pr = $false
    would_validate_source_codex_diff = $true
    would_create_branch = $true
    would_create_commit = $true
    would_push_branch = $true
    would_create_draft_pr = $true
    branch_name = $BranchName
    commit_sha = ""
    pr_number = $null
    pr_url = ""
    draft_pr = $true
    demo_pr_left_open = $false
    demo_pr_marked_ready = $false
    demo_pr_merged = $false
    docs_only_allowlist_passed = $false
    branch_policy_passed = $false
    changed_files = @($ChangedFiles)
    server_task_pr_evidence_recorded = $false
    artifact_report_written = $true
    report_markdown_path = "$relativeOutput/codex-draft-pr-report.md"
    report_json_path = "$relativeOutput/codex-draft-pr-report.json"
    demo_result = "blocked"
    fixture_mode = $false
    real_worker_execution = $false
    codex_called_in_mg372e2 = $false
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

function Write-CodexDraftPrArtifacts {
  param(
    [string]$ResolvedOutputDir,
    $Report,
    $State,
    $TaskArtifact,
    $WorkerArtifact,
    $Preflight,
    $SourceValidation,
    $BranchPlan,
    $Allowlist,
    $PrMetadata,
    $Provider,
    $Safety
  )
  $paths = Get-CodexDraftPrArtifactPaths -ResolvedOutputDir $ResolvedOutputDir
  Write-DemoJsonFile -Path $paths.state -Value $State
  Write-DemoJsonFile -Path $paths.task -Value $TaskArtifact
  Write-DemoJsonFile -Path $paths.worker -Value $WorkerArtifact
  Write-DemoJsonFile -Path $paths.preflight -Value $Preflight
  Write-DemoJsonFile -Path $paths.source_validation -Value $SourceValidation
  Write-DemoJsonFile -Path $paths.branch_plan -Value $BranchPlan
  Write-DemoJsonFile -Path $paths.allowlist -Value $Allowlist
  Write-DemoJsonFile -Path $paths.pr_metadata -Value $PrMetadata
  Write-DemoJsonFile -Path $paths.provider -Value $Provider
  Write-DemoJsonFile -Path $paths.safety -Value $Safety
  Write-DemoJsonFile -Path $paths.report_json -Value $Report
  $relativeOutput = $OutputDir.Replace("\", "/")
  $index = [ordered]@{
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.artifact_index.v1"
    generated_at = $Report.generated_at
    artifact_dir = $relativeOutput
    artifacts = @($CodexDraftPrArtifacts)
    report_json_path = $Report.report_json_path
    report_markdown_path = $Report.report_markdown_path
    source_validation_path = "$relativeOutput/codex-draft-pr-source-diff-validation.json"
    token_printed = $false
  }
  Write-DemoJsonFile -Path $paths.index -Value $index

  $markdown = @(
    "# SkyBridge MVP Codex-generated Draft PR Demo",
    "",
    "- result: $($Report.demo_result)",
    "- validation_status: $($Report.validation_status)",
    "- source_milestone: MG372D2R",
    "- source_report_path: $($Report.source_report_path)",
    "- source_patch_path: $($Report.source_patch_path)",
    "- source_artifact_path: $($Report.source_artifact_path)",
    "- source_codex_called: $($Report.source_codex_called)",
    "- source_codex_call_count: $($Report.source_codex_call_count)",
    "- source_diff_patch_non_empty: $($Report.source_diff_patch_non_empty)",
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
    "- demo_pr_marked_ready: false",
    "- demo_pr_merged: false",
    "- docs_only_allowlist_passed: $($Report.docs_only_allowlist_passed)",
    "- branch_policy_passed: $($Report.branch_policy_passed)",
    "- task_created: $($Report.task_created)",
    "- worker_registered: $($Report.worker_registered)",
    "- task_claimed: $($Report.task_claimed)",
    "- task_started: $($Report.task_started)",
    "- task_completed: $($Report.task_completed)",
    "- server_task_pr_evidence_recorded: $($Report.server_task_pr_evidence_recorded)",
    "- fixture_mode: false",
    "- real_worker_execution: $($Report.real_worker_execution)",
    "- codex_called_in_mg372e2: false",
    "- pr_created: $($Report.pr_created)",
    "- branch_pushed: $($Report.branch_pushed)",
    "- commit_created: $($Report.commit_created)",
    "- demo_pr_311_modified: false",
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
    "- raw_output_exported: false",
    "- token_printed: false",
    "",
    "Artifacts are written under `$relativeOutput`."
  )
  $markdown | Set-Content -LiteralPath $paths.report_md -Encoding UTF8
}

function Invoke-CodexDiffDraftPrDemo {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
  $generatedAt = Get-DemoUtcNow
  $implementationCommit = Get-DemoGitText -Arguments @("rev-parse", "HEAD")
  $baselineCommit = $CodexDraftPrImplementationBaseline
  $branchName = Get-CodexDraftPrBranchName
  $plannedChangedFiles = @($CodexDiffDemoFile)
  $isPreview = ($Mode -eq "codex-diff-draft-pr-preview" -or -not $Apply)
  $blockers = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()
  $providerCallCount = 0
  $gitPushCalled = $false
  $ghPrCreateCalled = $false
  $githubApiCalled = $false
  $serverInfo = $null
  $currentBranchBefore = ""
  $branchCreated = $false
  $demoCommitCreated = $false
  $branchPushed = $false
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

  $branchPolicy = Test-CodexDraftPrBranchPolicy -BranchName $branchName
  $allowlist = Test-CodexDraftPrAllowlist -ChangedFiles $plannedChangedFiles
  $sourceValidation = Test-CodexDraftPrSourceArtifacts -ReportPath $SourceReportPath -PatchPath $SourcePatchPath -ArtifactPath $SourceArtifactPath
  $report = New-CodexDraftPrReport -GeneratedAt $generatedAt -BaselineCommit $baselineCommit -ImplementationCommit $implementationCommit -BranchName $branchName -ChangedFiles $plannedChangedFiles
  $report.branch_policy_passed = [bool]$branchPolicy.branch_policy_passed
  $report.docs_only_allowlist_passed = [bool]$allowlist.docs_only_allowlist_passed
  $report.source_codex_called = [bool]$sourceValidation.source_codex_called
  $report.source_codex_call_count = [int]$sourceValidation.source_codex_call_count
  $report.source_codex_exit_code = $sourceValidation.source_codex_exit_code
  $report.source_diff_patch_non_empty = [bool]$sourceValidation.source_diff_patch_non_empty
  $report.source_docs_only_allowlist_passed = [bool]$sourceValidation.source_docs_only_allowlist_passed

  $preflight = [ordered]@{
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.preflight.v1"
    generated_at = $generatedAt
    mode = "codex-diff-draft-pr"
    preview = [bool]$isPreview
    apply = [bool]$Apply
    git_available = [bool](Get-Command git -ErrorAction SilentlyContinue)
    gh_available = [bool](Get-Command gh -ErrorAction SilentlyContinue)
    gh_auth_available = $false
    repo_clean = $false
    current_branch = ""
    current_branch_is_main = $false
    main_synced_with_origin = $false
    implementation_commit = $implementationCommit
    implementation_commit_on_main = $false
    contains_mg372d2r_baseline = $false
    demo_pr_311_exists = $false
    demo_pr_311_open = $false
    demo_pr_311_draft = $false
    no_existing_demo_branch = $false
    no_existing_demo_pr = $false
    confirmation_text_matched = ($ConfirmationText -eq $CodexDraftPrConfirmationText)
    source_validation_passed = [bool]$sourceValidation.source_validation_passed
    preflight_passed = $false
    blockers = @()
    token_printed = $false
  }
  $branchPlan = [ordered]@{
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.branch_plan.v1"
    generated_at = $generatedAt
    branch_name = $branchName
    branch_policy = $branchPolicy
    branch_policy_passed = [bool]$branchPolicy.branch_policy_passed
    branch_name_recorded_before_mutation = $true
    one_branch_max = $true
    token_printed = $false
  }
  $prMetadata = [ordered]@{
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.pr_metadata.v1"
    generated_at = $generatedAt
    title = $CodexDraftPrTitle
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
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.provider_report.v1"
    generated_at = $generatedAt
    provider = "controller-git-gh"
    preview = [bool]$isPreview
    provider_call_count = 0
    git_push_called = $false
    gh_pr_create_called = $false
    github_api_called = $false
    codex_called = $false
    controller_created_branch = $false
    controller_created_commit = $false
    controller_created_draft_pr = $false
    token_printed = $false
  }
  $safety = [ordered]@{
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.safety.v1"
    generated_at = $generatedAt
    mode = "codex-diff-draft-pr"
    safety_flags = New-CodexDraftPrSafetyFlags
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
    $preflight.implementation_commit_on_main = ($preflight.current_branch_is_main -and $preflight.main_synced_with_origin)
    $mergeBaseExit = Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("merge-base", "--is-ancestor", $CodexDraftPrImplementationBaseline, "HEAD") -AllowFailure
    $preflight.contains_mg372d2r_baseline = ([int]$mergeBaseExit -eq 0)
    $ghAuthExit = Invoke-DemoExternalQuiet -FilePath "gh" -Arguments @("auth", "status") -AllowFailure
    $preflight.gh_auth_available = ([int]$ghAuthExit -eq 0)
    if ($preflight.gh_available) {
      $pr311Raw = Invoke-DemoExternalQuiet -FilePath "gh" -Arguments @("pr", "view", "311", "--json", "number,state,isDraft,autoMergeRequest") -CaptureOutput -AllowFailure
      if (-not [string]::IsNullOrWhiteSpace($pr311Raw)) {
        $pr311 = $pr311Raw | ConvertFrom-Json
        $preflight.demo_pr_311_exists = ([int]$pr311.number -eq 311)
        $preflight.demo_pr_311_open = ([string]$pr311.state -eq "OPEN")
        $preflight.demo_pr_311_draft = [bool]$pr311.isDraft
      }
    }
    $localExactBranch = Get-DemoGitText -Arguments @("rev-parse", "--verify", "--quiet", $branchName) -AllowFailure
    $remoteExactBranch = Get-DemoGitText -Arguments @("ls-remote", "--heads", "origin", $branchName) -AllowFailure
    $localAnyBranch = Get-DemoGitText -Arguments @("branch", "--list", "demo/mg372e2-codex-draft-pr-*") -AllowFailure
    $remoteAnyBranch = Get-DemoGitText -Arguments @("ls-remote", "--heads", "origin", "demo/mg372e2-codex-draft-pr-*") -AllowFailure
    $preflight.no_existing_demo_branch = ([string]::IsNullOrWhiteSpace($localExactBranch) -and [string]::IsNullOrWhiteSpace($remoteExactBranch) -and [string]::IsNullOrWhiteSpace($localAnyBranch) -and [string]::IsNullOrWhiteSpace($remoteAnyBranch))
    $existingPrRaw = Invoke-DemoExternalQuiet -FilePath "gh" -Arguments @("pr", "list", "--state", "all", "--search", "MG372E2 Demo: Codex-generated Draft PR in:title", "--json", "number,url,state,isDraft,headRefName") -CaptureOutput -AllowFailure
    $existingPr = @()
    if (-not [string]::IsNullOrWhiteSpace($existingPrRaw)) { $existingPr = @($existingPrRaw | ConvertFrom-Json) }
    $preflight.no_existing_demo_pr = (@($existingPr).Count -eq 0)

    if (-not $preflight.git_available) { $blockers.Add("git_unavailable") | Out-Null }
    if (-not $preflight.gh_available) { $blockers.Add("gh_unavailable") | Out-Null }
    if (-not $preflight.gh_auth_available) { $blockers.Add("gh_auth_unavailable") | Out-Null }
    if (-not $branchPolicy.branch_policy_passed) { $blockers.Add("branch_policy_failed") | Out-Null }
    if (-not $allowlist.docs_only_allowlist_passed) { $blockers.Add("docs_only_allowlist_failed") | Out-Null }
    if (-not $sourceValidation.source_validation_passed) {
      foreach ($sourceBlocker in @($sourceValidation.blockers)) { $blockers.Add([string]$sourceBlocker) | Out-Null }
    }
    if (-not $isPreview -and -not $preflight.confirmation_text_matched) { $blockers.Add("confirmation_text_mismatch") | Out-Null }
    if (-not $isPreview -and -not $preflight.repo_clean) { $blockers.Add("repo_not_clean") | Out-Null }
    if (-not $isPreview -and -not $preflight.current_branch_is_main) { $blockers.Add("not_on_main") | Out-Null }
    if (-not $isPreview -and -not $preflight.main_synced_with_origin) { $blockers.Add("main_not_synced_with_origin") | Out-Null }
    if (-not $isPreview -and -not $preflight.implementation_commit_on_main) { $blockers.Add("implementation_commit_not_on_synced_main") | Out-Null }
    if (-not $isPreview -and -not $preflight.contains_mg372d2r_baseline) { $blockers.Add("mg372d2r_baseline_missing") | Out-Null }
    if (-not $isPreview -and -not $preflight.demo_pr_311_exists) { $blockers.Add("demo_pr_311_missing") | Out-Null }
    if (-not $isPreview -and -not $preflight.demo_pr_311_open) { $blockers.Add("demo_pr_311_not_open") | Out-Null }
    if (-not $isPreview -and -not $preflight.demo_pr_311_draft) { $blockers.Add("demo_pr_311_not_draft") | Out-Null }
    if (-not $isPreview -and -not $preflight.no_existing_demo_branch) { $blockers.Add("existing_mg372e2_demo_branch") | Out-Null }
    if (-not $isPreview -and -not $preflight.no_existing_demo_pr) { $blockers.Add("existing_mg372e2_demo_pr") | Out-Null }

    $preflight.blockers = @($blockers)
    $preflight.preflight_passed = (@($blockers).Count -eq 0)
    $report.blockers = @($blockers)
    $report.warnings = @($warnings)

    $state = [ordered]@{
      schema = "skybridge.mvp_demo.codex_generated_draft_pr.state.v1"
      generated_at = $generatedAt
      mode = "codex-diff-draft-pr"
      preview = [bool]$isPreview
      apply = [bool]$Apply
      output_dir = $OutputDir.Replace("\", "/")
      project_id = $ProjectId
      goal_id = $CodexDraftPrGoalId
      task_id = $CodexDraftPrTaskId
      worker_id = $CodexDraftPrWorkerId
      branch_name = $branchName
      token_printed = $false
    }
    $taskArtifact = [ordered]@{
      schema = "skybridge.mvp_demo.codex_generated_draft_pr.task.v1"
      generated_at = $generatedAt
      task_payload = New-CodexDraftPrTaskPayload
      final_task = $null
      task_created = $false
      task_claimed = $false
      task_started = $false
      task_completed = $false
      task_failed = $false
      token_printed = $false
    }
    $workerArtifact = [ordered]@{
      schema = "skybridge.mvp_demo.codex_generated_draft_pr.worker.v1"
      generated_at = $generatedAt
      worker_id = $CodexDraftPrWorkerId
      worker_registered = $false
      final_worker = $null
      capabilities = @("powershell", "git", "gh", "codex-diff-draft-pr-demo")
      token_printed = $false
    }

    if ($isPreview) {
      $report.validation_status = if (@($blockers | Where-Object { $_ -in @("branch_policy_failed", "docs_only_allowlist_failed", "git_unavailable", "gh_unavailable", "gh_auth_unavailable") }).Count -eq 0 -and [bool]$sourceValidation.source_validation_passed) { "preview_passed" } else { "preview_blocked" }
      $report.demo_result = if ($report.validation_status -eq "preview_passed") { "pass" } else { "blocked" }
      Write-CodexDraftPrArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -SourceValidation $sourceValidation -BranchPlan $branchPlan -Allowlist $allowlist -PrMetadata $prMetadata -Provider $provider -Safety $safety
      if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
      return
    }

    Write-CodexDraftPrArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -SourceValidation $sourceValidation -BranchPlan $branchPlan -Allowlist $allowlist -PrMetadata $prMetadata -Provider $provider -Safety $safety
    if (-not $preflight.preflight_passed) { throw "MG372E2 Codex-generated draft PR preflight failed." }

    $script:ResolvedApiBase = $ApiBase
    if ($UseTempDatabase) { $StartServer = $true }
    if ($StartServer) { $serverInfo = Start-DemoServer -ResolvedOutputDir $resolvedOutputDir }
    Wait-DemoServerHealth | Out-Null

    $existingProject = Invoke-DemoApi -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))" -AllowNotFound
    if (-not $existingProject) {
      Invoke-DemoApi -Method POST -Path "/v1/projects" -Body @{ project_id = $ProjectId; name = $ProjectId } | Out-Null
    }
    $existingGoal = Invoke-DemoApi -Method GET -Path "/v1/goals/$([uri]::EscapeDataString($CodexDraftPrGoalId))" -AllowNotFound
    if (-not $existingGoal) {
      Invoke-DemoApi -Method POST -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -Body @{
        goal_id = $CodexDraftPrGoalId
        title = "MG372E2 Codex-generated Draft PR Demo"
        summary = "Package the validated MG372D2R local Codex docs diff into one controller-created draft PR."
        source = "mg372e2-mvp-demo"
        risk = "low"
        status = "ready"
        acceptance_criteria = @("One controller-created demo branch, commit and draft PR are created from the validated source diff.")
        evidence_requirements = @("MG372E2 draft PR demo JSON and Markdown reports are written.")
      } | Out-Null
    }
    Invoke-DemoApi -Method POST -Path "/v1/tasks" -Body (New-CodexDraftPrTaskPayload) | Out-Null
    $taskCreated = $true
    Invoke-DemoApi -Method POST -Path "/v1/workers/register" -Body @{
      worker_id = $CodexDraftPrWorkerId
      name = "MG372E2 Codex draft PR demo worker"
      provider = "controller-demo"
      capabilities = @("powershell", "git", "gh", "codex-diff-draft-pr-demo")
      labels = @("mg372e2", "controller-created", "codex-diff", "draft-pr", "poll-once")
      enabled = $true
      auth_mode = "none"
      api_base = $script:ResolvedApiBase
      allow_remote_server = $false
    } | Out-Null
    $workerRegistered = $true
    Invoke-DemoApi -Method POST -Path "/v1/workers/$([uri]::EscapeDataString($CodexDraftPrWorkerId))/heartbeat" -Body @{
      status_note = "mg372e2 codex diff draft PR demo ready"
      load = 0
      seen_at = Get-DemoUtcNow
    } | Out-Null
    Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($CodexDraftPrTaskId))/claim" -Body @{ worker_id = $CodexDraftPrWorkerId } | Out-Null
    $taskClaimed = $true
    Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($CodexDraftPrTaskId))/start" -Body @{ worker_id = $CodexDraftPrWorkerId } | Out-Null
    $taskStarted = $true

    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("switch", "-c", $branchName) | Out-Null
    $branchCreated = $true
    $targetPath = Join-Path (Get-Location) ($CodexDiffDemoFile -replace "/", [System.IO.Path]::DirectorySeparatorChar)
    $targetDir = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
    Copy-Item -LiteralPath (Resolve-DemoPath $SourceArtifactPath) -Destination $targetPath -Force
    $actualChangedFiles = @(Get-CodexDraftPrChangedFiles)
    $allowlist = Test-CodexDraftPrAllowlist -ChangedFiles $actualChangedFiles
    if (-not $allowlist.docs_only_allowlist_passed) {
      $blockers.Add("docs_only_allowlist_failed_after_copy") | Out-Null
      throw "MG372E2 demo changed files failed allowlist."
    }
    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("add", "--", $CodexDiffDemoFile) | Out-Null
    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("commit", "-m", $CodexDraftPrCommitMessage) | Out-Null
    $demoCommitCreated = $true
    $commitSha = Get-DemoGitText -Arguments @("rev-parse", "HEAD")
    Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("push", "--set-upstream", "origin", $branchName) | Out-Null
    $gitPushCalled = $true
    $branchPushed = $true
    $providerCallCount += 1

    $paths = Get-CodexDraftPrArtifactPaths -ResolvedOutputDir $resolvedOutputDir
    $body = @(
      "## MG372E2 Codex-generated Draft PR Demo",
      "",
      "- demo_result=pass",
      "- source_milestone=MG372D2R",
      "- source_codex_called=true",
      "- source_codex_call_count=1",
      "- source_diff_patch_non_empty=true",
      "- controller_created_branch=true",
      "- controller_created_commit=true",
      "- controller_created_draft_pr=true",
      "- draft=true",
      "- task_created=true",
      "- worker_registered=true",
      "- task_claimed=true",
      "- task_started=true",
      "- task_completed=true",
      "- docs_only_allowlist_passed=true",
      "- branch_policy_passed=true",
      "- codex_called_in_mg372e2=false",
      "- tui_created_branch=false",
      "- tui_created_pr=false",
      "- auto_merge_enabled=false",
      "- release_created=false",
      "- tag_created=false",
      "- asset_uploaded=false",
      "- token_printed=false",
      "- artifacts path: .agent/tmp/skybridge-mvp-codex-draft-pr/",
      "",
      "This PR is intentionally draft-only and must remain open for Jerry review."
    )
    $body | Set-Content -LiteralPath $paths.pr_body -Encoding UTF8
    $prUrl = Invoke-DemoExternalQuiet -FilePath "gh" -Arguments @("pr", "create", "--draft", "--base", "main", "--head", $branchName, "--title", $CodexDraftPrTitle, "--body-file", $paths.pr_body) -CaptureOutput
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
    $allowlist = Test-CodexDraftPrAllowlist -ChangedFiles $actualPrFiles
    if (-not $draftPr) {
      $blockers.Add("demo_pr_not_draft") | Out-Null
      throw "MG372E2 demo PR was not draft."
    }
    if ($null -ne $prView.autoMergeRequest) {
      $blockers.Add("demo_pr_auto_merge_enabled") | Out-Null
      throw "MG372E2 demo PR auto-merge was enabled."
    }
    if (-not $allowlist.docs_only_allowlist_passed) {
      $blockers.Add("demo_pr_allowlist_failed") | Out-Null
      throw "MG372E2 demo PR changed files failed allowlist."
    }

    $complete = Invoke-DemoApi -Method POST -Path "/v1/tasks/$([uri]::EscapeDataString($CodexDraftPrTaskId))/complete" -Body @{
      worker_id = $CodexDraftPrWorkerId
      summary = "MG372E2 controller-created draft PR demo created one docs-only draft PR from validated MG372D2R Codex local diff and left it open for review."
      result_url = $prUrl
      evidence_summary = @{
        schema = "skybridge.mvp_demo.codex_generated_draft_pr.task_evidence.v1"
        project_id = $ProjectId
        goal_id = $CodexDraftPrGoalId
        task_id = $CodexDraftPrTaskId
        worker_id = $CodexDraftPrWorkerId
        source_milestone = "MG372D2R"
        branch_name = $branchName
        commit_sha = $commitSha
        pr_number = $prNumber
        pr_url = $prUrl
        draft_pr = $true
        docs_only_allowlist_passed = $true
        branch_policy_passed = $true
        codex_called_in_mg372e2 = $false
        source_codex_called = $true
        source_codex_call_count = 1
        tui_created_branch = $false
        tui_created_pr = $false
        token_printed = $false
        created_at = Get-DemoUtcNow
      }
    }
    $taskCompleted = $true
    $serverTaskEvidenceRecorded = $true
    $finalTask = $complete.task
    $finalTask = (Invoke-DemoApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($CodexDraftPrTaskId))").task
    $finalWorker = (Invoke-DemoApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($CodexDraftPrWorkerId))").worker
    $validationStatus = "passed"
    $demoResult = "pass"
  } catch {
    if (@($blockers).Count -lt 1) { $blockers.Add("codex_generated_draft_pr_demo_failed") | Out-Null }
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
    if ($branchCreated -and -not [string]::IsNullOrWhiteSpace($currentBranchBefore)) {
      $dirty = Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure
      if ([string]::IsNullOrWhiteSpace($dirty)) {
        Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("switch", $currentBranchBefore) -AllowFailure | Out-Null
      }
    }
  }

  $provider.provider_call_count = $providerCallCount
  $provider.git_push_called = [bool]$gitPushCalled
  $provider.gh_pr_create_called = [bool]$ghPrCreateCalled
  $provider.github_api_called = [bool]$githubApiCalled
  $provider.controller_created_branch = [bool]$branchCreated
  $provider.controller_created_commit = [bool]$demoCommitCreated
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
  $report.controller_created_commit = [bool]$demoCommitCreated
  $report.controller_created_draft_pr = [bool]$prCreated
  $report.pr_created = [bool]$prCreated
  $report.branch_pushed = [bool]$branchPushed
  $report.commit_created = [bool]$demoCommitCreated
  $report.commit_sha = $commitSha
  $report.pr_number = $prNumber
  $report.pr_url = $prUrl
  $report.draft_pr = if ($prCreated) { [bool]$draftPr } else { $true }
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
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.state.v1"
    generated_at = $report.generated_at
    mode = "codex-diff-draft-pr"
    preview = [bool]$isPreview
    apply = [bool]$Apply
    output_dir = $OutputDir.Replace("\", "/")
    project_id = $ProjectId
    goal_id = $CodexDraftPrGoalId
    task_id = $CodexDraftPrTaskId
    worker_id = $CodexDraftPrWorkerId
    branch_name = $branchName
    commit_sha = $commitSha
    pr_number = $prNumber
    pr_url = $prUrl
    token_printed = $false
  }
  $taskArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.task.v1"
    generated_at = $report.generated_at
    task_payload = New-CodexDraftPrTaskPayload
    final_task = $finalTask
    task_created = [bool]$taskCreated
    task_claimed = [bool]$taskClaimed
    task_started = [bool]$taskStarted
    task_completed = [bool]$taskCompleted
    task_failed = [bool]$taskFailed
    token_printed = $false
  }
  $workerArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_generated_draft_pr.worker.v1"
    generated_at = $report.generated_at
    worker_id = $CodexDraftPrWorkerId
    worker_registered = [bool]$workerRegistered
    final_worker = $finalWorker
    capabilities = @("powershell", "git", "gh", "codex-diff-draft-pr-demo")
    token_printed = $false
  }
  $preflight.blockers = @($blockers)
  $preflight.preflight_passed = ($validationStatus -eq "passed")
  $allowlist = Test-CodexDraftPrAllowlist -ChangedFiles @($report.changed_files)
  Write-CodexDraftPrArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -SourceValidation $sourceValidation -BranchPlan $branchPlan -Allowlist $allowlist -PrMetadata $prMetadata -Provider $provider -Safety $safety
  if ($OpenReport) { Invoke-Item -LiteralPath (Join-Path $resolvedOutputDir "codex-draft-pr-report.md") }
  if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
}

function Show-CodexDiffDraftPrStatus {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  $reportPath = Join-Path $resolvedOutputDir "codex-draft-pr-report.json"
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    $result = [pscustomobject]@{ ok = $false; mode = "codex-diff-draft-pr-status"; report_found = $false; report_json_path = $reportPath; token_printed = $false }
  } else {
    $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
    $result = [pscustomobject]@{
      ok = $true
      mode = "codex-diff-draft-pr-status"
      report_found = $true
      report_json_path = $reportPath
      report_markdown_path = (Join-Path $resolvedOutputDir "codex-draft-pr-report.md")
      demo_result = $report.demo_result
      validation_status = $report.validation_status
      controller_created_draft_pr = $report.controller_created_draft_pr
      pr_url = $report.pr_url
      token_printed = $false
    }
  }
  if ($Json) { $result | ConvertTo-Json -Depth 10 -Compress } else { $result | Format-List }
}

function Show-CodexDiffDraftPrReport {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  $reportJson = Join-Path $resolvedOutputDir "codex-draft-pr-report.json"
  $reportMd = Join-Path $resolvedOutputDir "codex-draft-pr-report.md"
  if (-not (Test-Path -LiteralPath $reportJson -PathType Leaf)) {
    $result = [pscustomobject]@{ ok = $false; mode = "codex-diff-draft-pr-report"; report_found = $false; report_json_path = $reportJson; report_markdown_path = $reportMd; token_printed = $false }
  } else {
    $report = Get-Content -Raw -LiteralPath $reportJson | ConvertFrom-Json
    $result = [pscustomobject]@{
      ok = $true
      mode = "codex-diff-draft-pr-report"
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
    stdout_log = Join-Path $ResolvedOutputDir "codex-local-diff-stdout.log"
    stderr_log = Join-Path $ResolvedOutputDir "codex-local-diff-stderr.log"
    changed_files = Join-Path $ResolvedOutputDir "codex-local-diff-changed-files.json"
    allowlist = Join-Path $ResolvedOutputDir "codex-local-diff-allowlist-check.json"
    review_summary = Join-Path $ResolvedOutputDir "codex-local-diff-review-summary.md"
    patch = Join-Path $ResolvedOutputDir "codex-local-diff.patch"
    safety = Join-Path $ResolvedOutputDir "codex-local-diff-safety.json"
    collector_diagnostics = Join-Path $ResolvedOutputDir "codex-local-diff-collector-diagnostics.json"
    execution_diagnostics = Join-Path $ResolvedOutputDir "codex-local-diff-execution-diagnostics.json"
    failure_classification = Join-Path $ResolvedOutputDir "codex-local-diff-failure-classification.json"
    cleanup_report_json = Join-Path $ResolvedOutputDir "codex-local-diff-cleanup-report.json"
    cleanup_report_md = Join-Path $ResolvedOutputDir "codex-local-diff-cleanup-report.md"
    worktree_list_before = Join-Path $ResolvedOutputDir "codex-local-diff-worktree-list-before.txt"
    worktree_list_after = Join-Path $ResolvedOutputDir "codex-local-diff-worktree-list-after.txt"
    cleanup_safety = Join-Path $ResolvedOutputDir "codex-local-diff-cleanup-safety.json"
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
Create exactly this file:
$CodexDiffDemoFile

Write 8 to 20 lines of Markdown.
Include these exact fields:
generated_by=Codex
source_milestone=MG372D2R
baseline_commit=$BaselineCommit
task_id=$TaskIdValue
token_printed=false

Also include one short bullet for what the demo proves and one short bullet for safety boundaries.
Do not modify any other file.
Do not run tests, builds, git add, git commit, git push, or gh pr create.
Do not inspect secrets or read .env files.
Finish immediately after writing the file.
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

function Get-CodexDiffVersion {
  param($CommandSpec)
  try {
    $version = Invoke-DemoExternalQuiet -FilePath ([string]$CommandSpec.file_path) -Arguments (@($CommandSpec.argument_prefix) + @("--version")) -CaptureOutput -AllowFailure
    if ([string]::IsNullOrWhiteSpace($version)) { return $null }
    return (($version -replace "`r?`n", " ").Trim())
  } catch {
    return $null
  }
}

function New-CodexDiffExecutionDiagnostics {
  param(
    [string]$GeneratedAt,
    [string]$StdoutPath,
    [string]$StderrPath,
    [string]$LastMessagePath,
    [int]$TimeoutSeconds,
    [string]$Command = "codex exec"
  )
  [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.execution_diagnostics.v1"
    generated_at = $GeneratedAt
    codex_command = $Command
    codex_version = $null
    codex_available = $false
    codex_timeout_seconds = [int]$TimeoutSeconds
    codex_started_at = $null
    codex_completed_at = $null
    codex_duration_ms = $null
    codex_exit_code = $null
    codex_timed_out = $false
    codex_stdout_path = $StdoutPath.Replace("\", "/")
    codex_stderr_path = $StderrPath.Replace("\", "/")
    codex_last_message_path = $LastMessagePath.Replace("\", "/")
    codex_process_killed = $false
    codex_artifact_created_before_timeout = $false
    codex_artifact_size_bytes = 0
    codex_transport_error_detected = $false
    codex_auth_or_login_error_detected = $false
    codex_rate_limit_or_usage_error_detected = $false
    codex_network_error_detected = $false
    token_printed = $false
  }
}

function Get-CodexDiffFailureSignals {
  param(
    [string]$StdoutPath,
    [string]$StderrPath,
    [string]$LastMessagePath
  )
  $combined = ""
  foreach ($path in @($StdoutPath, $StderrPath, $LastMessagePath)) {
    if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
      $text = Get-Content -Raw -LiteralPath $path -ErrorAction SilentlyContinue
      if ($text) { $combined = "$combined`n$text" }
    }
  }
  [pscustomobject]@{
    transport = [bool]($combined -match "(?i)\btransport\b|connection reset|stream error|protocol error")
    auth = [bool]($combined -match "(?i)not logged in|login required|unauthorized|authentication|auth error|invalid api key")
    usage = [bool]($combined -match "(?i)rate limit|quota|usage limit|insufficient quota|too many requests")
    network = [bool]($combined -match "(?i)network|dns|timed out connecting|connection refused|tls|proxy")
  }
}

function Get-CodexDiffFailureClass {
  param(
    [bool]$CodexAvailable,
    [bool]$PreflightPassed,
    [bool]$CodexCalled,
    [bool]$TimedOut,
    [int]$ExitCode,
    [bool]$TargetExists,
    [bool]$AllowlistPassed,
    [bool]$PatchNonEmpty,
    $Signals
  )
  if (-not $CodexAvailable) { return "codex_cli_unavailable" }
  if (-not $PreflightPassed -and -not $CodexCalled) { return "codex_preflight_failed" }
  if ($Signals -and $Signals.transport) { return "codex_transport_error" }
  if ($Signals -and $Signals.auth) { return "codex_auth_or_login_error" }
  if ($Signals -and $Signals.usage) { return "codex_usage_or_rate_limit_error" }
  if ($Signals -and $Signals.network) { return "codex_network_error" }
  if ($TimedOut -and -not $TargetExists) { return "codex_exec_timeout_no_artifact" }
  if ($TimedOut -and $TargetExists) { return "codex_exec_timeout_with_artifact" }
  if ($CodexCalled -and $ExitCode -ne 0 -and -not $TargetExists) { return "codex_exec_nonzero_no_artifact" }
  if ($CodexCalled -and $ExitCode -ne 0 -and $TargetExists) { return "codex_exec_nonzero_with_artifact" }
  if (-not $TargetExists) { return "codex_target_missing" }
  if (-not $AllowlistPassed) { return "codex_modified_disallowed_files" }
  if (-not $PatchNonEmpty) { return "codex_empty_patch" }
  return "none"
}

function Invoke-CodexDiffProcess {
  param(
    [Parameter(Mandatory = $true)]$CommandSpec,
    [Parameter(Mandatory = $true)][string]$WorkspacePath,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [Parameter(Mandatory = $true)][string]$LastMessagePath,
    [Parameter(Mandatory = $true)][string]$StdoutPath,
    [Parameter(Mandatory = $true)][string]$StderrPath,
    [Parameter(Mandatory = $true)][string]$TargetArtifactPath,
    [int]$TimeoutSeconds = 900,
    [string]$Sandbox = "workspace-write"
  )
  $arguments = @($CommandSpec.argument_prefix) + @("exec", "--sandbox", $Sandbox, "--color", "never", "--ephemeral", "--json", "--output-last-message", $LastMessagePath, "-")
  $startParams = @{
    FilePath = [string]$CommandSpec.file_path
    ArgumentList = $arguments
    WorkingDirectory = $WorkspacePath
    NoNewWindow = $true
    PassThru = $true
    RedirectStandardInput = $PromptPath
    RedirectStandardOutput = $StdoutPath
    RedirectStandardError = $StderrPath
  }
  $startedAt = Get-DemoUtcNow
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $process = Start-Process @startParams
  $timeoutMs = [Math]::Max(1, $TimeoutSeconds) * 1000
  if (-not $process.WaitForExit($timeoutMs)) {
    try { $process.Kill($true) } catch { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $stopwatch.Stop()
    $artifactExists = [bool](Test-Path -LiteralPath $TargetArtifactPath -PathType Leaf)
    $artifactSize = if ($artifactExists) { (Get-Item -LiteralPath $TargetArtifactPath).Length } else { 0 }
    return [pscustomobject]@{
      ok = $false
      exit_code = 124
      timed_out = $true
      stdout_path = $StdoutPath
      stderr_path = $StderrPath
      started_at = $startedAt
      completed_at = Get-DemoUtcNow
      duration_ms = [int64]$stopwatch.ElapsedMilliseconds
      process_killed = $true
      artifact_created_before_timeout = $artifactExists
      artifact_size_bytes = $artifactSize
      token_printed = $false
    }
  }
  $stopwatch.Stop()
  $artifactExists = [bool](Test-Path -LiteralPath $TargetArtifactPath -PathType Leaf)
  $artifactSize = if ($artifactExists) { (Get-Item -LiteralPath $TargetArtifactPath).Length } else { 0 }
  [pscustomobject]@{
    ok = ($process.ExitCode -eq 0)
    exit_code = $process.ExitCode
    timed_out = $false
    stdout_path = $StdoutPath
    stderr_path = $StderrPath
    started_at = $startedAt
    completed_at = Get-DemoUtcNow
    duration_ms = [int64]$stopwatch.ElapsedMilliseconds
    process_killed = $false
    artifact_created_before_timeout = $false
    artifact_size_bytes = $artifactSize
    token_printed = $false
  }
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

function Get-CodexDiffFullPath {
  param([string]$Path)
  [System.IO.Path]::GetFullPath((Resolve-DemoPath $Path)).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Test-CodexDiffPathStartsWith {
  param(
    [string]$Path,
    [string]$Parent
  )
  $fullPath = Get-CodexDiffFullPath -Path $Path
  $fullParent = Get-CodexDiffFullPath -Path $Parent
  return ($fullPath.Equals($fullParent, [System.StringComparison]::OrdinalIgnoreCase) -or
    $fullPath.StartsWith($fullParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-CodexDiffWorktreeListText {
  Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("worktree", "list", "--porcelain") -CaptureOutput -AllowFailure
}

function Get-CodexDiffWorktreeRecords {
  param([string]$WorktreeListText)
  $records = [System.Collections.Generic.List[object]]::new()
  $current = $null
  foreach ($line in @($WorktreeListText -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      if ($null -ne $current) {
        $records.Add([pscustomobject]$current) | Out-Null
        $current = $null
      }
      continue
    }
    if ($line -like "worktree *") {
      if ($null -ne $current) { $records.Add([pscustomobject]$current) | Out-Null }
      $current = [ordered]@{ worktree = $line.Substring(9).Trim(); HEAD = ""; branch = ""; detached = $false }
    } elseif ($null -ne $current -and $line -like "HEAD *") {
      $current.HEAD = $line.Substring(5).Trim()
    } elseif ($null -ne $current -and $line -like "branch *") {
      $current.branch = $line.Substring(7).Trim()
    } elseif ($null -ne $current -and $line -eq "detached") {
      $current.detached = $true
    }
  }
  if ($null -ne $current) { $records.Add([pscustomobject]$current) | Out-Null }
  @($records)
}

function Find-CodexDiffRegisteredWorktree {
  param(
    [string]$WorktreePath,
    [string]$WorktreeListText
  )
  $target = Get-CodexDiffFullPath -Path $WorktreePath
  foreach ($record in @(Get-CodexDiffWorktreeRecords -WorktreeListText $WorktreeListText)) {
    $candidate = Get-CodexDiffFullPath -Path ([string]$record.worktree)
    if ($candidate.Equals($target, [System.StringComparison]::OrdinalIgnoreCase)) { return $record }
  }
  return $null
}

function New-CodexDiffCleanupArtifacts {
  param(
    [string]$GeneratedAt,
    [string]$ResolvedOutputDir,
    [string]$WorkspacePath,
    [bool]$Requested,
    [string]$BeforeText = "",
    [string]$AfterText = "",
    [string]$Method = "not_requested",
    [bool]$Completed = $false,
    [string[]]$Blockers = @()
  )
  $repoRoot = Get-CodexDiffFullPath -Path "."
  $defaultAllowedRoot = Get-CodexDiffFullPath -Path ".agent/tmp/skybridge-mvp-codex-diff"
  $defaultExactWorktree = Get-CodexDiffFullPath -Path ".agent/tmp/skybridge-mvp-codex-diff/worktree"
  $target = Get-CodexDiffFullPath -Path $WorkspacePath
  $root = [System.IO.Path]::GetPathRoot($target).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $registered = Find-CodexDiffRegisteredWorktree -WorktreePath $WorkspacePath -WorktreeListText $BeforeText
  $pathUnderAgentTmp = Test-CodexDiffPathStartsWith -Path $WorkspacePath -Parent $defaultAllowedRoot
  $pathExactMatch = $target.Equals($defaultExactWorktree, [System.StringComparison]::OrdinalIgnoreCase)
  $isRepoRoot = $target.Equals($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)
  $isRoot = $target.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar).Equals($root, [System.StringComparison]::OrdinalIgnoreCase)
  $isParentOfRepo = $repoRoot.StartsWith($target + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
  $safety = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.cleanup_safety.v1"
    generated_at = $GeneratedAt
    workspace_path = $target.Replace("\", "/")
    default_allowed_root = $defaultAllowedRoot.Replace("\", "/")
    default_exact_worktree = $defaultExactWorktree.Replace("\", "/")
    path_under_agent_tmp = [bool]$pathUnderAgentTmp
    path_exact_match = [bool]$pathExactMatch
    path_is_repo_root = [bool]$isRepoRoot
    path_is_root = [bool]$isRoot
    path_is_parent_of_repo = [bool]$isParentOfRepo
    path_registered_worktree = [bool]($null -ne $registered)
    main_worktree_path = $repoRoot.Replace("\", "/")
    token_printed = $false
  }
  $report = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.cleanup_report.v1"
    generated_at = $GeneratedAt
    cleanup_requested = [bool]$Requested
    cleanup_authorization_phrase_matched = ($ConfirmationText -eq $CodexDiffConfirmationText)
    stale_worktree_detected = [bool](Test-Path -LiteralPath $WorkspacePath)
    stale_worktree_path = $target.Replace("\", "/")
    stale_worktree_registered = [bool]($null -ne $registered)
    stale_worktree_commit = if ($null -ne $registered) { [string]$registered.HEAD } else { $null }
    path_under_agent_tmp = [bool]$pathUnderAgentTmp
    path_exact_match = [bool]$pathExactMatch
    main_worktree_clean_before_cleanup = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure))
    cleanup_method = $Method
    cleanup_completed = [bool]$Completed
    cleanup_blockers = @($Blockers)
    token_printed = $false
  }
  [pscustomobject]@{ report = $report; safety = $safety }
}

function Write-CodexDiffCleanupFiles {
  param(
    [string]$ResolvedOutputDir,
    $CleanupReport,
    $CleanupSafety,
    [string]$BeforeText,
    [string]$AfterText
  )
  $paths = Get-CodexDiffArtifactPaths -ResolvedOutputDir $ResolvedOutputDir
  if ($null -eq $CleanupReport -or $null -eq $CleanupSafety) {
    $generatedAt = Get-DemoUtcNow
    $items = New-CodexDiffCleanupArtifacts -GeneratedAt $generatedAt -ResolvedOutputDir $ResolvedOutputDir -WorkspacePath $paths.workspace -Requested $false -BeforeText $BeforeText -AfterText $AfterText
    $CleanupReport = $items.report
    $CleanupSafety = $items.safety
  }
  Write-DemoJsonFile -Path $paths.cleanup_report_json -Value $CleanupReport
  Write-DemoJsonFile -Path $paths.cleanup_safety -Value $CleanupSafety
  if ($null -eq $BeforeText) { $BeforeText = "" }
  if ($null -eq $AfterText) { $AfterText = $BeforeText }
  $BeforeText | Set-Content -LiteralPath $paths.worktree_list_before -Encoding UTF8
  $AfterText | Set-Content -LiteralPath $paths.worktree_list_after -Encoding UTF8
  $markdown = @(
    "# MG372D2R Codex Local Diff Cleanup Report",
    "",
    "- cleanup_requested: $($CleanupReport.cleanup_requested)",
    "- cleanup_authorization_phrase_matched: $($CleanupReport.cleanup_authorization_phrase_matched)",
    "- stale_worktree_detected: $($CleanupReport.stale_worktree_detected)",
    "- stale_worktree_registered: $($CleanupReport.stale_worktree_registered)",
    "- stale_worktree_commit: $($CleanupReport.stale_worktree_commit)",
    "- stale_worktree_path: $($CleanupReport.stale_worktree_path)",
    "- path_under_agent_tmp: $($CleanupReport.path_under_agent_tmp)",
    "- path_exact_match: $($CleanupReport.path_exact_match)",
    "- main_worktree_clean_before_cleanup: $($CleanupReport.main_worktree_clean_before_cleanup)",
    "- cleanup_method: $($CleanupReport.cleanup_method)",
    "- cleanup_completed: $($CleanupReport.cleanup_completed)",
    "- cleanup_blockers: $(@($CleanupReport.cleanup_blockers) -join ', ')",
    "- token_printed: false"
  )
  $markdown | Set-Content -LiteralPath $paths.cleanup_report_md -Encoding UTF8
}

function Invoke-CodexDiffStaleWorktreeCleanup {
  param(
    [string]$ResolvedOutputDir,
    [string]$WorkspacePath,
    [bool]$Requested,
    [bool]$AllowFixturePath = $false
  )
  $paths = Get-CodexDiffArtifactPaths -ResolvedOutputDir $ResolvedOutputDir
  $beforeText = Get-CodexDiffWorktreeListText
  $blockers = [System.Collections.Generic.List[string]]::new()
  $method = if ($Requested) { if ($ArchiveExistingCodexWorktree) { "archive_requested_git_worktree_remove_force" } else { "git_worktree_remove_force" } } else { "not_requested" }
  $cleanupCompleted = $false
  $items = New-CodexDiffCleanupArtifacts -GeneratedAt (Get-DemoUtcNow) -ResolvedOutputDir $ResolvedOutputDir -WorkspacePath $WorkspacePath -Requested $Requested -BeforeText $beforeText -Method $method
  $report = $items.report
  $safety = $items.safety
  $initialStaleDetected = [bool]$report.stale_worktree_detected
  $initialStaleRegistered = [bool]$report.stale_worktree_registered
  $initialStaleCommit = $report.stale_worktree_commit

  if (-not $Requested) {
    $afterText = $beforeText
    Write-CodexDiffCleanupFiles -ResolvedOutputDir $ResolvedOutputDir -CleanupReport $report -CleanupSafety $safety -BeforeText $beforeText -AfterText $afterText
    return [pscustomobject]@{ report = $report; safety = $safety; before = $beforeText; after = $afterText }
  }

  if (-not $report.cleanup_authorization_phrase_matched) { $blockers.Add("cleanup_authorization_phrase_mismatch") | Out-Null }
  if (-not $report.main_worktree_clean_before_cleanup) { $blockers.Add("main_worktree_not_clean_before_cleanup") | Out-Null }
  if (-not $safety.path_under_agent_tmp) { $blockers.Add("cleanup_path_outside_agent_tmp") | Out-Null }
  if ($safety.path_is_repo_root) { $blockers.Add("cleanup_path_is_repo_root") | Out-Null }
  if ($safety.path_is_root) { $blockers.Add("cleanup_path_is_root") | Out-Null }
  if ($safety.path_is_parent_of_repo) { $blockers.Add("cleanup_path_is_parent_of_repo") | Out-Null }
  if (-not $AllowFixturePath -and -not $safety.path_exact_match) { $blockers.Add("cleanup_path_not_exact_default_worktree") | Out-Null }
  if ($report.stale_worktree_detected -and -not $report.stale_worktree_registered) { $blockers.Add("stale_worktree_not_registered") | Out-Null }

  if (@($blockers).Count -eq 0) {
    if (-not $report.stale_worktree_detected) {
      $method = "verified_absent"
      $cleanupCompleted = $true
    } else {
      Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("worktree", "remove", "--force", $WorkspacePath) | Out-Null
      $afterRemove = Get-CodexDiffWorktreeListText
      if (Find-CodexDiffRegisteredWorktree -WorktreePath $WorkspacePath -WorktreeListText $afterRemove) {
        $blockers.Add("stale_worktree_still_registered_after_remove") | Out-Null
      }
      if (Test-Path -LiteralPath $WorkspacePath) {
        if ($safety.path_under_agent_tmp -and (-not $safety.path_is_repo_root) -and (-not $safety.path_is_root) -and (-not $safety.path_is_parent_of_repo)) {
          Remove-Item -LiteralPath $WorkspacePath -Recurse -Force
        } else {
          $blockers.Add("stale_worktree_directory_left_in_unsafe_path") | Out-Null
        }
      }
      if (Test-Path -LiteralPath $WorkspacePath) { $blockers.Add("stale_worktree_directory_still_exists_after_cleanup") | Out-Null }
      $cleanupCompleted = (@($blockers).Count -eq 0)
    }
  }

  $afterText = Get-CodexDiffWorktreeListText
  $items = New-CodexDiffCleanupArtifacts -GeneratedAt (Get-DemoUtcNow) -ResolvedOutputDir $ResolvedOutputDir -WorkspacePath $WorkspacePath -Requested $Requested -BeforeText $beforeText -AfterText $afterText -Method $method -Completed $cleanupCompleted -Blockers @($blockers)
  $report = $items.report
  $safety = $items.safety
  $report.stale_worktree_detected = $initialStaleDetected
  $report.stale_worktree_registered = $initialStaleRegistered
  $report.stale_worktree_commit = $initialStaleCommit
  Write-CodexDiffCleanupFiles -ResolvedOutputDir $ResolvedOutputDir -CleanupReport $report -CleanupSafety $safety -BeforeText $beforeText -AfterText $afterText
  [pscustomobject]@{ report = $report; safety = $safety; before = $beforeText; after = $afterText }
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
    $ExecutionDiagnostics,
    $FailureClassification,
    $CleanupReport,
    $CleanupSafety,
    $Safety
  )
  $paths = Get-CodexDiffArtifactPaths -ResolvedOutputDir $ResolvedOutputDir
  foreach ($file in @($paths.prompt, $paths.last_message, $paths.stdout_log, $paths.stderr_log, $paths.review_summary, $paths.patch)) {
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
  if ($null -eq $ExecutionDiagnostics) {
    $ExecutionDiagnostics = New-CodexDiffExecutionDiagnostics -GeneratedAt $Report.generated_at -StdoutPath $paths.stdout_log -StderrPath $paths.stderr_log -LastMessagePath $paths.last_message -TimeoutSeconds $CodexTimeoutSeconds
  }
  if ($null -eq $FailureClassification) {
    $FailureClassification = [ordered]@{
      schema = "skybridge.mvp_demo.codex_local_diff.failure_classification.v1"
      generated_at = $Report.generated_at
      codex_failure_class = $Report.codex_failure_class
      blockers = @($Report.blockers)
      token_printed = $false
    }
  }
  Write-DemoJsonFile -Path $paths.collector_diagnostics -Value $CollectorDiagnostics
  Write-DemoJsonFile -Path $paths.execution_diagnostics -Value $ExecutionDiagnostics
  Write-DemoJsonFile -Path $paths.failure_classification -Value $FailureClassification
  if ($null -eq $CleanupReport -or $null -eq $CleanupSafety) {
    $beforeText = Get-CodexDiffWorktreeListText
    $cleanupItems = New-CodexDiffCleanupArtifacts -GeneratedAt $Report.generated_at -ResolvedOutputDir $ResolvedOutputDir -WorkspacePath $paths.workspace -Requested $false -BeforeText $beforeText -AfterText $beforeText
    $CleanupReport = $cleanupItems.report
    $CleanupSafety = $cleanupItems.safety
    Write-CodexDiffCleanupFiles -ResolvedOutputDir $ResolvedOutputDir -CleanupReport $CleanupReport -CleanupSafety $CleanupSafety -BeforeText $beforeText -AfterText $beforeText
  } else {
    $beforeText = if (Test-Path -LiteralPath $paths.worktree_list_before -PathType Leaf) { Get-Content -Raw -LiteralPath $paths.worktree_list_before } else { "" }
    $afterText = if (Test-Path -LiteralPath $paths.worktree_list_after -PathType Leaf) { Get-Content -Raw -LiteralPath $paths.worktree_list_after } else { $beforeText }
    Write-CodexDiffCleanupFiles -ResolvedOutputDir $ResolvedOutputDir -CleanupReport $CleanupReport -CleanupSafety $CleanupSafety -BeforeText $beforeText -AfterText $afterText
  }
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
    execution_diagnostics_path = "$relativeOutput/codex-local-diff-execution-diagnostics.json"
    failure_classification_path = "$relativeOutput/codex-local-diff-failure-classification.json"
    cleanup_report_path = "$relativeOutput/codex-local-diff-cleanup-report.json"
    cleanup_safety_path = "$relativeOutput/codex-local-diff-cleanup-safety.json"
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
    "- cleanup_requested: $($Report.cleanup_requested)",
    "- cleanup_completed: $($Report.cleanup_completed)",
    "- stale_worktree_detected: $($Report.stale_worktree_detected)",
    "- stale_worktree_cleaned: $($Report.stale_worktree_cleaned)",
    "- codex_called: $($Report.codex_called)",
    "- codex_call_count: $($Report.codex_call_count)",
    "- codex_exit_code: $($Report.codex_exit_code)",
    "- codex_timed_out: $($Report.codex_timed_out)",
    "- codex_timeout_seconds: $($Report.codex_timeout_seconds)",
    "- codex_duration_ms: $($Report.codex_duration_ms)",
    "- codex_failure_class: $($Report.codex_failure_class)",
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
    "- target_artifact_size_bytes: $($Report.target_artifact_size_bytes)",
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
    rerun_milestone = "MG372D2R"
    baseline_commit = $BaselineCommit
    implementation_commit = $ImplementationCommit
    project_id = $ProjectId
    goal_id = $CodexDiffGoalId
    task_id = $CodexDiffTaskId
    worker_id = $CodexDiffWorkerId
    cleanup_requested = $false
    cleanup_completed = $false
    stale_worktree_detected = $false
    stale_worktree_cleaned = $false
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
    would_run_codex_doctor = $true
    would_clean_existing_worktree = $false
    codex_available = $false
    codex_called = $false
    codex_call_count = 0
    codex_exit_code = $null
    codex_timed_out = $false
    codex_timeout_seconds = [int]$CodexTimeoutSeconds
    codex_duration_ms = $null
    codex_failure_class = "none"
    codex_stdout_path = "$relativeOutput/codex-local-diff-stdout.log"
    codex_stderr_path = "$relativeOutput/codex-local-diff-stderr.log"
    codex_last_message_path = "$relativeOutput/codex-local-diff-last-message.md"
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
    target_artifact_size_bytes = 0
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
  $codexTimedOut = $false
  $codexDurationMs = $null
  $codexFailureClass = "none"
  $codexAvailable = $false
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
    codex_version = $null
    codex_preflight_warning = $null
    codex_preflight_blocker = $null
    codex_timeout_seconds = [int]$CodexTimeoutSeconds
    output_dir_writable = $false
    worktree_writable = $false
    target_docs_dir_ready = $false
    repo_clean = $false
    current_branch = ""
    current_branch_is_main = $false
    main_synced_with_origin = $false
    contains_mg372d_baseline = $false
    confirmation_text_matched = ($ConfirmationText -eq $CodexDiffConfirmationText)
    cleanup_requested = $false
    cleanup_authorization_phrase_matched = ($ConfirmationText -eq $CodexDiffConfirmationText)
    would_clean_existing_worktree = $false
    cleanup_completed = $false
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
  $executionDiagnostics = New-CodexDiffExecutionDiagnostics -GeneratedAt $generatedAt -StdoutPath $paths.stdout_log -StderrPath $paths.stderr_log -LastMessagePath $paths.last_message -TimeoutSeconds $CodexTimeoutSeconds
  $cleanupReport = $null
  $cleanupSafety = $null
  $failureClassification = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.failure_classification.v1"
    generated_at = $generatedAt
    codex_failure_class = "none"
    blockers = @()
    token_printed = $false
  }

  try {
    $outputProbe = Join-Path $resolvedOutputDir ".mg372d2-output-probe"
    "probe" | Set-Content -LiteralPath $outputProbe -Encoding UTF8
    Remove-Item -LiteralPath $outputProbe -Force
    $preflight.output_dir_writable = $true

    $preflight.repo_clean = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure))
    $preflight.current_branch = Get-DemoGitText -Arguments @("branch", "--show-current") -AllowFailure
    $preflight.current_branch_is_main = ([string]$preflight.current_branch -eq "main")
    $localHead = Get-DemoGitText -Arguments @("rev-parse", "HEAD") -AllowFailure
    $originHead = Get-DemoGitText -Arguments @("rev-parse", "origin/main") -AllowFailure
    $preflight.main_synced_with_origin = (-not [string]::IsNullOrWhiteSpace($localHead) -and $localHead -eq $originHead)
    $mergeBaseExit = Invoke-DemoExternalQuiet -FilePath "git" -Arguments @("merge-base", "--is-ancestor", "d32b2d8ef63dc229b746e77e7f585938a84b7231", "HEAD") -AllowFailure
    $preflight.contains_mg372d_baseline = ([int]$mergeBaseExit -eq 0)

    if ($preflight.codex_available) {
      try {
        $doctorCommand = Resolve-CodexDiffCommand
        $executionDiagnostics.codex_available = $true
        $executionDiagnostics.codex_version = Get-CodexDiffVersion -CommandSpec $doctorCommand
        $preflight.codex_version = $executionDiagnostics.codex_version
        if ([string]::IsNullOrWhiteSpace([string]$executionDiagnostics.codex_version)) {
          $preflight.codex_preflight_warning = "codex_version_unavailable"
          $warnings.Add("codex_preflight_warning_version_unavailable") | Out-Null
        }
      } catch {
        $preflight.codex_preflight_warning = "codex_command_resolution_failed"
        $warnings.Add("codex_preflight_warning_command_resolution_failed") | Out-Null
      }
    }
    $codexAvailable = [bool]$preflight.codex_available

    $preflight.would_clean_existing_worktree = [bool](Test-Path -LiteralPath $workspacePath)
    if (-not $isPreview -and $CleanExistingCodexWorktree) {
      $preflight.cleanup_requested = $true
      $cleanup = Invoke-CodexDiffStaleWorktreeCleanup -ResolvedOutputDir $resolvedOutputDir -WorkspacePath $workspacePath -Requested $true
      $cleanupReport = $cleanup.report
      $cleanupSafety = $cleanup.safety
      $preflight.cleanup_completed = [bool]$cleanupReport.cleanup_completed
      $preflight.no_existing_workspace = -not (Test-Path -LiteralPath $workspacePath)
      if (-not $cleanupReport.cleanup_completed) {
        $blockers.Add("stale_worktree_cleanup_failed") | Out-Null
        foreach ($cleanupBlocker in @($cleanupReport.cleanup_blockers)) {
          if (-not [string]::IsNullOrWhiteSpace([string]$cleanupBlocker)) {
            $blockers.Add([string]$cleanupBlocker) | Out-Null
          }
        }
      }
    } else {
      $cleanup = Invoke-CodexDiffStaleWorktreeCleanup -ResolvedOutputDir $resolvedOutputDir -WorkspacePath $workspacePath -Requested $false
      $cleanupReport = $cleanup.report
      $cleanupSafety = $cleanup.safety
      $preflight.no_existing_workspace = -not (Test-Path -LiteralPath $workspacePath)
    }

    if (-not $preflight.git_available) { $blockers.Add("git_unavailable") | Out-Null }
    if (-not $preflight.output_dir_writable) { $blockers.Add("output_dir_not_writable") | Out-Null }
    if (-not $allowlist.docs_only_allowlist_passed) { $blockers.Add("docs_only_allowlist_failed") | Out-Null }
    if (-not $isPreview -and -not $preflight.codex_available) { $blockers.Add("codex_cli_unavailable") | Out-Null }
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
      $report.codex_available = [bool]$preflight.codex_available
      $report.main_worktree_clean_after = $preflight.repo_clean
      $report.cleanup_requested = $false
      $report.cleanup_completed = $false
      $report.stale_worktree_detected = [bool]$cleanupReport.stale_worktree_detected
      $report.stale_worktree_cleaned = $false
      $report.would_clean_existing_worktree = [bool]$preflight.would_clean_existing_worktree
      Write-CodexDiffArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -ChangedFiles $changedFilesArtifact -Allowlist $allowlist -CollectorDiagnostics $collectorDiagnostics -ExecutionDiagnostics $executionDiagnostics -FailureClassification $failureClassification -CleanupReport $cleanupReport -CleanupSafety $cleanupSafety -Safety $safety
      if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
      return
    }

    $report.cleanup_requested = [bool]$preflight.cleanup_requested
    $report.cleanup_completed = [bool]$preflight.cleanup_completed
    $report.stale_worktree_detected = [bool]$cleanupReport.stale_worktree_detected
    $report.stale_worktree_cleaned = [bool]($cleanupReport.cleanup_completed -and $cleanupReport.stale_worktree_detected)
    $report.would_clean_existing_worktree = [bool]$preflight.would_clean_existing_worktree
    Write-CodexDiffArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -ChangedFiles $changedFilesArtifact -Allowlist $allowlist -CollectorDiagnostics $collectorDiagnostics -ExecutionDiagnostics $executionDiagnostics -FailureClassification $failureClassification -CleanupReport $cleanupReport -CleanupSafety $cleanupSafety -Safety $safety
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
    $targetDir = Join-Path $workspacePath "docs/product"
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }
    $writableProbe = Join-Path $targetDir ".mg372d2-write-probe"
    "probe" | Set-Content -LiteralPath $writableProbe -Encoding UTF8
    Remove-Item -LiteralPath $writableProbe -Force
    $preflight.worktree_writable = $true
    $preflight.target_docs_dir_ready = $true
    $collectorDiagnostics.pre_codex_status_porcelain = @(Get-CodexDiffStatusPorcelain -WorkspacePath $workspacePath)
    $collectorDiagnostics.workspace_clean_before_codex = (@($collectorDiagnostics.pre_codex_status_porcelain).Count -eq 0)
    if (-not $collectorDiagnostics.workspace_clean_before_codex) {
      $blockers.Add("workspace_dirty_before_codex") | Out-Null
      throw "MG372D1 Codex local diff worktree was dirty before Codex."
    }
    $codexCommand = Resolve-CodexDiffCommand
    $executionDiagnostics.codex_command = "$($codexCommand.display_command) exec --sandbox $CodexSandbox --json --output-last-message <last-message> -"
    $executionDiagnostics.codex_available = $true
    if ([string]::IsNullOrWhiteSpace([string]$executionDiagnostics.codex_version)) {
      $executionDiagnostics.codex_version = Get-CodexDiffVersion -CommandSpec $codexCommand
    }
    $codexCalled = $true
    $codexCallCount = 1
    $safety.safety_flags.codex_called = $true
    $safety.safety_flags.codex_call_count = 1
    $artifactFile = Join-Path $workspacePath ($CodexDiffDemoFile -replace "/", [System.IO.Path]::DirectorySeparatorChar)
    $codex = Invoke-CodexDiffProcess -CommandSpec $codexCommand -WorkspacePath $workspacePath -PromptPath $paths.prompt -LastMessagePath $paths.last_message -StdoutPath $paths.stdout_log -StderrPath $paths.stderr_log -TargetArtifactPath $artifactFile -TimeoutSeconds $CodexTimeoutSeconds -Sandbox $CodexSandbox
    $codexExitCode = $codex.exit_code
    $codexTimedOut = [bool]$codex.timed_out
    $codexDurationMs = $codex.duration_ms
    $executionDiagnostics.codex_started_at = $codex.started_at
    $executionDiagnostics.codex_completed_at = $codex.completed_at
    $executionDiagnostics.codex_duration_ms = $codex.duration_ms
    $executionDiagnostics.codex_exit_code = $codex.exit_code
    $executionDiagnostics.codex_timed_out = [bool]$codex.timed_out
    $executionDiagnostics.codex_process_killed = [bool]$codex.process_killed
    $executionDiagnostics.codex_artifact_created_before_timeout = [bool]$codex.artifact_created_before_timeout
    $executionDiagnostics.codex_artifact_size_bytes = [int64]$codex.artifact_size_bytes
    $signals = Get-CodexDiffFailureSignals -StdoutPath $paths.stdout_log -StderrPath $paths.stderr_log -LastMessagePath $paths.last_message
    $executionDiagnostics.codex_transport_error_detected = [bool]$signals.transport
    $executionDiagnostics.codex_auth_or_login_error_detected = [bool]$signals.auth
    $executionDiagnostics.codex_rate_limit_or_usage_error_detected = [bool]$signals.usage
    $executionDiagnostics.codex_network_error_detected = [bool]$signals.network

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
    $collectorDiagnostics.target_artifact_exists = [bool](Test-Path -LiteralPath $artifactFile -PathType Leaf)
    if ($collectorDiagnostics.target_artifact_exists) {
      $collectorDiagnostics.target_artifact_size_bytes = (Get-Item -LiteralPath $artifactFile).Length
    }
    $workspaceHead = Get-DemoGitText -Arguments @("-C", $workspacePath, "rev-parse", "HEAD") -AllowFailure
    $commitCreated = (-not [string]::IsNullOrWhiteSpace($workspaceHead) -and $workspaceHead -ne $implementationCommit)

    $codexFailureClass = Get-CodexDiffFailureClass -CodexAvailable $codexAvailable -PreflightPassed $preflight.preflight_passed -CodexCalled $codexCalled -TimedOut $codexTimedOut -ExitCode ([int]$codexExitCode) -TargetExists ([bool]$collectorDiagnostics.target_artifact_exists) -AllowlistPassed ([bool]$allowlist.docs_only_allowlist_passed) -PatchNonEmpty ([bool]$collectorDiagnostics.patch_non_empty) -Signals $signals
    if (-not $codex.ok) { $blockers.Add($codexFailureClass) | Out-Null }
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
        "- codex_timed_out: $codexTimedOut",
        "- codex_duration_ms: $codexDurationMs",
        "- codex_failure_class: $codexFailureClass",
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
        "- codex_timed_out: $codexTimedOut",
        "- codex_duration_ms: $codexDurationMs",
        "- codex_failure_class: $codexFailureClass",
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
    if ($codexFailureClass -eq "none") {
      $codexFailureClass = Get-CodexDiffFailureClass -CodexAvailable $codexAvailable -PreflightPassed $preflight.preflight_passed -CodexCalled $codexCalled -TimedOut $codexTimedOut -ExitCode ([int]($codexExitCode ?? 0)) -TargetExists ([bool]$collectorDiagnostics.target_artifact_exists) -AllowlistPassed ([bool]$allowlist.docs_only_allowlist_passed) -PatchNonEmpty ([bool]$collectorDiagnostics.patch_non_empty) -Signals $null
    }
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
  $report.codex_available = [bool]$codexAvailable
  $report.codex_called = [bool]$codexCalled
  $report.codex_call_count = [int]$codexCallCount
  $report.codex_exit_code = $codexExitCode
  $report.codex_timed_out = [bool]$codexTimedOut
  $report.codex_timeout_seconds = [int]$CodexTimeoutSeconds
  $report.codex_duration_ms = $codexDurationMs
  $report.codex_failure_class = $codexFailureClass
  $report.codex_stdout_path = "$($OutputDir.Replace('\', '/'))/codex-local-diff-stdout.log"
  $report.codex_stderr_path = "$($OutputDir.Replace('\', '/'))/codex-local-diff-stderr.log"
  $report.codex_last_message_path = "$($OutputDir.Replace('\', '/'))/codex-local-diff-last-message.md"
  $report.cleanup_requested = [bool]$preflight.cleanup_requested
  $report.cleanup_completed = [bool]$preflight.cleanup_completed
  $report.stale_worktree_detected = [bool]($cleanupReport -and $cleanupReport.stale_worktree_detected)
  $report.stale_worktree_cleaned = [bool]($cleanupReport -and $cleanupReport.cleanup_completed -and $cleanupReport.stale_worktree_detected)
  $report.would_clean_existing_worktree = [bool]$preflight.would_clean_existing_worktree
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
  $report.target_artifact_size_bytes = [int64]$collectorDiagnostics.target_artifact_size_bytes
  $report.demo_result = $demoResult
  $report.real_worker_execution = [bool]($taskClaimed -and $taskStarted)
  $report.commit_created = [bool]$commitCreated
  $report.blockers = @($blockers)
  $report.warnings = @($warnings)

  $state.generated_at = $report.generated_at
  $state.codex_called = [bool]$codexCalled
  $state.codex_call_count = [int]$codexCallCount
  $state.codex_exit_code = $codexExitCode
  $state.codex_timed_out = [bool]$codexTimedOut
  $state.codex_failure_class = $codexFailureClass
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
  if (-not $isPreview) { $preflight.preflight_passed = (@($blockers | Where-Object { $_ -in @("git_unavailable", "output_dir_not_writable", "codex_cli_unavailable", "confirmation_text_mismatch", "repo_not_clean", "not_on_main", "main_not_synced_with_origin", "mg372d_baseline_missing", "existing_codex_diff_workspace") }).Count -eq 0) }
  $changedFilesArtifact.generated_at = $report.generated_at
  $changedFilesArtifact.changed_files = @($changedFiles)
  $collectorDiagnostics.generated_at = $report.generated_at
  $executionDiagnostics.generated_at = $report.generated_at
  $failureClassification.generated_at = $report.generated_at
  $failureClassification.codex_failure_class = $codexFailureClass
  $failureClassification.blockers = @($blockers)
  Write-CodexDiffArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -ChangedFiles $changedFilesArtifact -Allowlist $allowlist -CollectorDiagnostics $collectorDiagnostics -ExecutionDiagnostics $executionDiagnostics -FailureClassification $failureClassification -CleanupReport $cleanupReport -CleanupSafety $cleanupSafety -Safety $safety
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
        "source_milestone=MG372D2R",
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
    "# MG372D2 Codex Local Diff Collector Fixture",
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

function New-CodexDiffMockExecutable {
  param(
    [string]$Path,
    [ValidateSet("success", "timeout", "disallowed-file")][string]$Behavior
  )
  $content = @"
param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$RemainingArgs)
`$ErrorActionPreference = "Stop"
`$lastMessagePath = ""
for (`$i = 0; `$i -lt `$RemainingArgs.Count; `$i++) {
  if (`$RemainingArgs[`$i] -eq "--output-last-message" -and `$i + 1 -lt `$RemainingArgs.Count) {
    `$lastMessagePath = `$RemainingArgs[`$i + 1]
  }
}
if ("$Behavior" -eq "timeout") {
  Start-Sleep -Seconds 5
  exit 0
}
`$target = Join-Path (Get-Location) "docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent `$target) | Out-Null
@(
  "# MG372D Codex Local Diff Artifact",
  "",
  "generated_by=Codex",
  "source_milestone=MG372D2R",
  "task_id=mg372d-codex-local-diff-task-001",
  "token_printed=false",
  "- proves: mock Codex artifact production path",
  "- safety: no PR, push or commit"
) | Set-Content -LiteralPath `$target -Encoding UTF8
if ("$Behavior" -eq "disallowed-file") {
  `$bad = Join-Path (Get-Location) "docs/product/MG372D_NOT_ALLOWLISTED_LOCAL_DIFF_ARTIFACT.md"
  "token_printed=false" | Set-Content -LiteralPath `$bad -Encoding UTF8
}
if (-not [string]::IsNullOrWhiteSpace(`$lastMessagePath)) {
  "mock Codex completed token_printed=false" | Set-Content -LiteralPath `$lastMessagePath -Encoding UTF8
}
exit 0
"@
  Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Invoke-CodexLocalDiffMockFixture {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
  $paths = Get-CodexDiffArtifactPaths -ResolvedOutputDir $resolvedOutputDir
  $generatedAt = Get-DemoUtcNow
  $implementationCommit = Get-DemoGitText -Arguments @("rev-parse", "HEAD")
  $workspacePath = $paths.workspace
  $fixtureKind = switch ($Mode) {
    "codex-local-diff-timeout-fixture" { "timeout" }
    "codex-local-diff-mock-disallowed-file" { "disallowed-file" }
    default { "success" }
  }
  $mockPath = Join-Path $resolvedOutputDir "mock-codex.ps1"
  $blockers = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()
  $changedFiles = @()
  $codexExitCode = $null
  $codexTimedOut = $false
  $codexDurationMs = $null
  $codexFailureClass = "none"
  $report = New-CodexDiffReport -GeneratedAt $generatedAt -BaselineCommit $implementationCommit -ImplementationCommit $implementationCommit -WorkspacePath $workspacePath
  $report.mode = $Mode
  $report.fixture_mode = $true
  $report.codex_available = $true
  $report.isolated_workspace_used = $true
  $report.workspace_setup_method = "git_worktree"
  $report.git_index_collector_used = $true
  $report.hash_comparison_used = $false

  $prompt = New-CodexDiffPrompt -BaselineCommit $implementationCommit -TaskIdValue $CodexDiffTaskId
  $prompt | Set-Content -LiteralPath $paths.prompt -Encoding UTF8
  $allowlist = Test-CodexDiffAllowlist -ChangedFiles @()
  $collectorDiagnostics = New-CodexDiffCollectorDiagnostics -GeneratedAt $generatedAt -BaselineCommit $implementationCommit -WorkspacePath $workspacePath -PatchPath $paths.patch
  $executionDiagnostics = New-CodexDiffExecutionDiagnostics -GeneratedAt $generatedAt -StdoutPath $paths.stdout_log -StderrPath $paths.stderr_log -LastMessagePath $paths.last_message -TimeoutSeconds $(if ($fixtureKind -eq "timeout") { 1 } else { 30 }) -Command "mock-codex exec"
  $executionDiagnostics.codex_available = $true
  $executionDiagnostics.codex_version = "mock-codex"
  $cleanupReport = $null
  $cleanupSafety = $null
  $preflight = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.preflight.v1"
    generated_at = $generatedAt
    mode = $Mode
    preview = $true
    apply = $false
    git_available = [bool](Get-Command git -ErrorAction SilentlyContinue)
    codex_available = $true
    codex_version = "mock-codex"
    codex_timeout_seconds = [int]$executionDiagnostics.codex_timeout_seconds
    output_dir_writable = $true
    worktree_writable = $false
    target_docs_dir_ready = $false
    repo_clean = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure))
    current_branch = Get-DemoGitText -Arguments @("branch", "--show-current") -AllowFailure
    current_branch_is_main = $false
    main_synced_with_origin = $false
    contains_mg372d_baseline = $false
    confirmation_text_matched = $false
    cleanup_requested = $false
    cleanup_authorization_phrase_matched = ($ConfirmationText -eq $CodexDiffConfirmationText)
    would_clean_existing_worktree = $false
    cleanup_completed = $false
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
    capabilities = @("powershell", "git", "mock-codex", "codex-local-diff-demo")
    token_printed = $false
  }
  $safety = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.safety.v1"
    generated_at = $generatedAt
    mode = $Mode
    safety_flags = New-CodexDiffSafetyFlags
    token_printed = $false
  }

  try {
    if (-not $preflight.git_available) { $blockers.Add("git_unavailable") | Out-Null }
    $preflight.would_clean_existing_worktree = [bool](Test-Path -LiteralPath $workspacePath)
    if ($CleanExistingCodexWorktree) {
      $preflight.cleanup_requested = $true
      $cleanup = Invoke-CodexDiffStaleWorktreeCleanup -ResolvedOutputDir $resolvedOutputDir -WorkspacePath $workspacePath -Requested $true -AllowFixturePath $true
      $cleanupReport = $cleanup.report
      $cleanupSafety = $cleanup.safety
      $preflight.cleanup_completed = [bool]$cleanupReport.cleanup_completed
      $preflight.no_existing_workspace = -not (Test-Path -LiteralPath $workspacePath)
      if (-not $cleanupReport.cleanup_completed) {
        $blockers.Add("stale_worktree_cleanup_failed") | Out-Null
        foreach ($cleanupBlocker in @($cleanupReport.cleanup_blockers)) {
          if (-not [string]::IsNullOrWhiteSpace([string]$cleanupBlocker)) {
            $blockers.Add([string]$cleanupBlocker) | Out-Null
          }
        }
      }
    } else {
      $cleanup = Invoke-CodexDiffStaleWorktreeCleanup -ResolvedOutputDir $resolvedOutputDir -WorkspacePath $workspacePath -Requested $false -AllowFixturePath $true
      $cleanupReport = $cleanup.report
      $cleanupSafety = $cleanup.safety
      $preflight.no_existing_workspace = -not (Test-Path -LiteralPath $workspacePath)
    }
    if (-not $preflight.no_existing_workspace) { $blockers.Add("existing_codex_diff_workspace") | Out-Null }
    if (@($blockers).Count -eq 0) {
      New-CodexDiffWorkspace -WorkspacePath $workspacePath -CommitSha $implementationCommit
      $targetDir = Join-Path $workspacePath "docs/product"
      if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
      }
      $preflight.worktree_writable = $true
      $preflight.target_docs_dir_ready = $true
      $collectorDiagnostics.pre_codex_status_porcelain = @(Get-CodexDiffStatusPorcelain -WorkspacePath $workspacePath)
      $collectorDiagnostics.workspace_clean_before_codex = (@($collectorDiagnostics.pre_codex_status_porcelain).Count -eq 0)
      if (-not $collectorDiagnostics.workspace_clean_before_codex) { $blockers.Add("workspace_dirty_before_codex") | Out-Null }
    }
    if (@($blockers).Count -eq 0) {
      New-CodexDiffMockExecutable -Path $mockPath -Behavior $fixtureKind
      $mockCommand = [pscustomobject]@{
        file_path = "pwsh"
        argument_prefix = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mockPath)
        display_command = "mock-codex"
        resolved_path = $mockPath
        powershell_shim = $true
        token_printed = $false
      }
      $artifactFile = Join-Path $workspacePath ($CodexDiffDemoFile -replace "/", [System.IO.Path]::DirectorySeparatorChar)
      $codex = Invoke-CodexDiffProcess -CommandSpec $mockCommand -WorkspacePath $workspacePath -PromptPath $paths.prompt -LastMessagePath $paths.last_message -StdoutPath $paths.stdout_log -StderrPath $paths.stderr_log -TargetArtifactPath $artifactFile -TimeoutSeconds ([int]$executionDiagnostics.codex_timeout_seconds) -Sandbox "workspace-write"
      $codexExitCode = $codex.exit_code
      $codexTimedOut = [bool]$codex.timed_out
      $codexDurationMs = $codex.duration_ms
      $executionDiagnostics.codex_started_at = $codex.started_at
      $executionDiagnostics.codex_completed_at = $codex.completed_at
      $executionDiagnostics.codex_duration_ms = $codex.duration_ms
      $executionDiagnostics.codex_exit_code = $codex.exit_code
      $executionDiagnostics.codex_timed_out = [bool]$codex.timed_out
      $executionDiagnostics.codex_process_killed = [bool]$codex.process_killed
      $executionDiagnostics.codex_artifact_created_before_timeout = [bool]$codex.artifact_created_before_timeout
      $executionDiagnostics.codex_artifact_size_bytes = [int64]$codex.artifact_size_bytes

      $collectorDiagnostics.post_codex_status_porcelain = @(Get-CodexDiffStatusPorcelain -WorkspacePath $workspacePath)
      $changedFiles = @(ConvertFrom-CodexDiffStatusPorcelain -StatusLines $collectorDiagnostics.post_codex_status_porcelain)
      $allowlist = Test-CodexDiffAllowlist -ChangedFiles $changedFiles
      Write-CodexDiffPatch -WorkspacePath $workspacePath -PatchPath $paths.patch
      $collectorDiagnostics.git_diff_name_only = @(Get-CodexDiffNameOnly -WorkspacePath $workspacePath)
      $collectorDiagnostics.patch_non_empty = ((Test-Path -LiteralPath $paths.patch -PathType Leaf) -and ((Get-Item -LiteralPath $paths.patch).Length -gt 0) -and [bool](Select-String -LiteralPath $paths.patch -Pattern ([regex]::Escape($CodexDiffDemoFile)) -Quiet))
      $collectorDiagnostics.target_artifact_exists = [bool](Test-Path -LiteralPath $artifactFile -PathType Leaf)
      if ($collectorDiagnostics.target_artifact_exists) {
        $collectorDiagnostics.target_artifact_size_bytes = (Get-Item -LiteralPath $artifactFile).Length
      }
      $signals = Get-CodexDiffFailureSignals -StdoutPath $paths.stdout_log -StderrPath $paths.stderr_log -LastMessagePath $paths.last_message
      $codexFailureClass = Get-CodexDiffFailureClass -CodexAvailable $true -PreflightPassed $true -CodexCalled $true -TimedOut $codexTimedOut -ExitCode ([int]$codexExitCode) -TargetExists ([bool]$collectorDiagnostics.target_artifact_exists) -AllowlistPassed ([bool]$allowlist.docs_only_allowlist_passed) -PatchNonEmpty ([bool]$collectorDiagnostics.patch_non_empty) -Signals $signals
      if (-not $codex.ok) { $blockers.Add($codexFailureClass) | Out-Null }
      if (-not $collectorDiagnostics.target_artifact_exists) { $blockers.Add("target_artifact_missing_after_codex") | Out-Null }
      if (-not $allowlist.docs_only_allowlist_passed) { $blockers.Add("docs_only_allowlist_failed_after_codex") | Out-Null }
      if (-not $collectorDiagnostics.patch_non_empty) { $blockers.Add("empty_diff_patch_after_codex") | Out-Null }
    }
  } catch {
    if (@($blockers).Count -lt 1) { $blockers.Add("codex_mock_fixture_failed") | Out-Null }
    $warnings.Add(($_.Exception.Message -replace 'https?://\S+', "<redacted-url>")) | Out-Null
  }

  $changedFilesArtifact = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.changed_files.v1"
    generated_at = Get-DemoUtcNow
    changed_files = @($changedFiles)
    token_printed = $false
  }
  $failureClassification = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.failure_classification.v1"
    generated_at = Get-DemoUtcNow
    codex_failure_class = $codexFailureClass
    blockers = @($blockers)
    token_printed = $false
  }
  $preflight.blockers = @($blockers)
  $preflight.preflight_passed = (@($blockers | Where-Object { $_ -in @("git_unavailable", "existing_codex_diff_workspace", "workspace_dirty_before_codex", "codex_mock_fixture_failed") }).Count -eq 0)
  $report.generated_at = Get-DemoUtcNow
  $report.codex_called = $true
  $report.codex_call_count = 1
  $report.codex_exit_code = $codexExitCode
  $report.codex_timed_out = [bool]$codexTimedOut
  $report.codex_timeout_seconds = [int]$executionDiagnostics.codex_timeout_seconds
  $report.codex_duration_ms = $codexDurationMs
  $report.codex_failure_class = $codexFailureClass
  $report.cleanup_requested = [bool]$preflight.cleanup_requested
  $report.cleanup_completed = [bool]$preflight.cleanup_completed
  $report.stale_worktree_detected = [bool]($cleanupReport -and $cleanupReport.stale_worktree_detected)
  $report.stale_worktree_cleaned = [bool]($cleanupReport -and $cleanupReport.cleanup_completed -and $cleanupReport.stale_worktree_detected)
  $report.would_clean_existing_worktree = [bool]$preflight.would_clean_existing_worktree
  $report.isolated_workspace_used = $true
  $report.workspace_clean_before_codex = [bool]$collectorDiagnostics.workspace_clean_before_codex
  $report.main_worktree_clean_after = [string]::IsNullOrWhiteSpace((Get-DemoGitText -Arguments @("status", "--porcelain") -AllowFailure))
  $report.changed_files = @($changedFiles)
  $report.docs_only_allowlist_passed = [bool]$allowlist.docs_only_allowlist_passed
  $report.diff_patch_non_empty = [bool]$collectorDiagnostics.patch_non_empty
  $report.target_artifact_exists = [bool]$collectorDiagnostics.target_artifact_exists
  $report.target_artifact_size_bytes = [int64]$collectorDiagnostics.target_artifact_size_bytes
  $report.demo_result = if (@($blockers).Count -eq 0) { "pass" } else { "blocked" }
  $report.validation_status = if ($report.demo_result -eq "pass") { "passed" } else { "failed" }
  $report.blockers = @($blockers)
  $report.warnings = @($warnings)
  $state.generated_at = $report.generated_at
  $state.changed_files = @($changedFiles)
  $state.codex_failure_class = $codexFailureClass
  $collectorDiagnostics.generated_at = $report.generated_at
  $executionDiagnostics.generated_at = $report.generated_at

  $review = @(
    "# MG372D2 Codex Local Diff Mock Fixture",
    "",
    "- mode: $Mode",
    "- fixture_kind: $fixtureKind",
    "- demo_result: $($report.demo_result)",
    "- codex_timed_out: $($report.codex_timed_out)",
    "- codex_failure_class: $codexFailureClass",
    "- changed_files: $(@($changedFiles) -join ', ')",
    "- docs_only_allowlist_passed: $($allowlist.docs_only_allowlist_passed)",
    "- diff_patch_non_empty: $($collectorDiagnostics.patch_non_empty)",
    "- pr_created: false",
    "- branch_pushed: false",
    "- commit_created: false",
    "- token_printed: false"
  )
  $review | Set-Content -LiteralPath $paths.review_summary -Encoding UTF8
  Write-CodexDiffArtifacts -ResolvedOutputDir $resolvedOutputDir -Report $report -State $state -TaskArtifact $taskArtifact -WorkerArtifact $workerArtifact -Preflight $preflight -ChangedFiles $changedFilesArtifact -Allowlist $allowlist -CollectorDiagnostics $collectorDiagnostics -ExecutionDiagnostics $executionDiagnostics -FailureClassification $failureClassification -CleanupReport $cleanupReport -CleanupSafety $cleanupSafety -Safety $safety
  if ($Json) { $report | ConvertTo-Json -Depth 30 -Compress } else { $report | Format-List }
}

function Invoke-CodexLocalDiffCleanupSafetyFixture {
  $resolvedOutputDir = Resolve-DemoPath $OutputDir
  New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
  $generatedAt = Get-DemoUtcNow
  $repoRoot = Get-CodexDiffFullPath -Path "."
  $outsidePath = Get-CodexDiffFullPath -Path ".agent/tmp/skybridge-mvp-codex-diff-cleanup-outside/worktree"
  $safeFixturePath = Get-CodexDiffFullPath -Path (Join-Path $OutputDir "worktree")
  $beforeText = Get-CodexDiffWorktreeListText
  $outside = New-CodexDiffCleanupArtifacts -GeneratedAt $generatedAt -ResolvedOutputDir $resolvedOutputDir -WorkspacePath $outsidePath -Requested $true -BeforeText $beforeText
  $root = New-CodexDiffCleanupArtifacts -GeneratedAt $generatedAt -ResolvedOutputDir $resolvedOutputDir -WorkspacePath $repoRoot -Requested $true -BeforeText $beforeText
  $missingAuth = New-CodexDiffCleanupArtifacts -GeneratedAt $generatedAt -ResolvedOutputDir $resolvedOutputDir -WorkspacePath $safeFixturePath -Requested $true -BeforeText $beforeText

  $outsideRejected = -not [bool]$outside.safety.path_under_agent_tmp
  $repoRootRejected = [bool]$root.safety.path_is_repo_root
  $confirmationRequired = -not [bool]$missingAuth.report.cleanup_authorization_phrase_matched
  $result = [ordered]@{
    schema = "skybridge.mvp_demo.codex_local_diff.cleanup_safety_fixture.v1"
    generated_at = $generatedAt
    mode = "codex-local-diff-cleanup-safety"
    outside_agent_tmp_rejected = [bool]$outsideRejected
    repo_root_rejected = [bool]$repoRootRejected
    confirmation_required = [bool]$confirmationRequired
    codex_called = $false
    pr_created = $false
    branch_pushed = $false
    commit_created = $false
    token_printed = $false
    demo_result = if ($outsideRejected -and $repoRootRejected -and $confirmationRequired) { "pass" } else { "blocked" }
    blockers = @()
  }
  if ($result.demo_result -ne "pass") { $result.blockers = @("cleanup_safety_fixture_failed") }
  Write-DemoJsonFile -Path (Join-Path $resolvedOutputDir "codex-local-diff-cleanup-safety-fixture-report.json") -Value $result
  Write-DemoJsonFile -Path (Join-Path $resolvedOutputDir "codex-local-diff-cleanup-safety-outside.json") -Value $outside.safety
  Write-DemoJsonFile -Path (Join-Path $resolvedOutputDir "codex-local-diff-cleanup-safety-repo-root.json") -Value $root.safety
  Write-DemoJsonFile -Path (Join-Path $resolvedOutputDir "codex-local-diff-cleanup-safety-auth.json") -Value $missingAuth.report
  if ($Json) { $result | ConvertTo-Json -Depth 30 -Compress } else { $result | Format-List }
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
} elseif ($Mode -eq "codex-diff-draft-pr-status") {
  Show-CodexDiffDraftPrStatus
} elseif ($Mode -eq "codex-diff-draft-pr-report") {
  Show-CodexDiffDraftPrReport
} elseif ($Mode -eq "codex-local-diff-status") {
  Show-CodexLocalDiffStatus
} elseif ($Mode -eq "codex-local-diff-report") {
  Show-CodexLocalDiffReport
} elseif ($Mode -eq "codex-local-diff-cleanup-safety") {
  Invoke-CodexLocalDiffCleanupSafetyFixture
} elseif ($Mode -in @("codex-local-diff-worktree-clean", "codex-local-diff-synthetic-patch", "codex-local-diff-policy-fixture")) {
  Invoke-CodexLocalDiffCollectorFixture
} elseif ($Mode -in @("codex-local-diff-timeout-fixture", "codex-local-diff-mock-success", "codex-local-diff-mock-disallowed-file")) {
  Invoke-CodexLocalDiffMockFixture
} elseif ($Mode -like "codex-diff-draft-pr*") {
  Invoke-CodexDiffDraftPrDemo
} elseif ($Mode -like "codex-local-diff*") {
  Invoke-CodexLocalDiffDemo
} else {
  Invoke-ControllerDraftPrDemo
}
