function Invoke-ManagedModePilotJson {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$Scenario = "low-docs",
    [string[]]$Extra = @()
  )
  $script = Join-Path $PSScriptRoot "skybridge-managed-mode-pilot.ps1"
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command -Scenario $Scenario -Json @Extra
  if ($LASTEXITCODE -ne 0) { throw "skybridge-managed-mode-pilot $Command failed." }
  if ($raw -match '"token_printed"\s*:\s*true') { throw "token_printed=true found." }
  if ($raw -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript') {
    throw "Secret-looking or raw artifact field found."
  }
  $raw | ConvertFrom-Json
}

function New-ManagedModePilotSmokeStateDir {
  Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-managed-mode-pilot-208-" + [Guid]::NewGuid().ToString("n"))
}

function Write-ManagedModePilotFixtureEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$StateDir,
    [int]$CodexExecutionCount = 1,
    [int]$PrCount = 1
  )
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_executor_evidence.v1"
    pilot_id = "managed-mode-pilot-208"
    mode = "managed_mode_v1_pilot"
    workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
    worker_id = "laptop-zenbookduo"
    command_class = "codex_exec_ephemeral_stdin_discard_output"
    changed_files = @("docs/dev/MANAGED_MODE_V1_PILOT.md")
    file_evidence = @(
      [pscustomobject]@{
        path = "docs/dev/MANAGED_MODE_V1_PILOT.md"
        sha256 = "fixture-doc-sha"
        token_printed = $false
      }
    )
    prompt_sha256 = "fixture-prompt-sha"
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    output_persisted = $false
    task_created = $true
    task_claimed = $true
    codex_execution_count = $CodexExecutionCount
    pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/208"
    pr_count = $PrCount
    auto_merge_enabled = $false
    final_state = "held_waiting_human_pr_review"
    token_printed = $false
  } | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $StateDir "pilot-evidence.json") -Encoding UTF8
}

function Write-ManagedModePilotAmbiguousResult {
  param([Parameter(Mandatory = $true)][string]$StateDir)
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  [pscustomobject]@{
    schema = "skybridge.bounded_queue_apply_result.v1"
    pilot_id = "managed-mode-pilot-208"
    mode = "fixture_ambiguous_partial_result"
    final_state = "unknown"
    task_created = $false
    task_claimed = $false
    codex_execution_started = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $StateDir "pilot-result.json") -Encoding UTF8
}

function Write-ManagedModePilotTimeoutResult {
  param(
    [Parameter(Mandatory = $true)][string]$StateDir,
    [string[]]$ChangedFiles = @(),
    [bool]$PrCreated = $false
  )
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  [pscustomobject]@{
    ok = $false
    schema = "skybridge.bounded_queue_apply_result.v1"
    pilot_id = "managed-mode-pilot-208"
    mode = "renewed_controlled_failure"
    final_state = "held_no_execution_executor_failed"
    renewed_authorization = $true
    prior_attempt_state = "prior_attempt_failed_before_execution"
    task_created = $true
    task_claimed = $true
    codex_execution_started = $true
    launcher_metadata = [pscustomobject]@{
      launcher_kind = "cmd"
      command_class = "codex_exec_ephemeral_stdin_discard_output"
      host_executable_name = "cmd.exe"
      prompt_persisted = $false
      transcript_persisted = $false
      stdout_persisted = $false
      stderr_persisted = $false
      token_printed = $false
    }
    pr_created = $PrCreated
    pr_url = if ($PrCreated) { "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/208" } else { $null }
    changed_files = @($ChangedFiles)
    exit_code = $null
    timed_out = $true
    elapsed_seconds = 1800
    timeout_minutes = 30
    stdout_chars_discarded = 0
    stderr_chars_discarded = 0
    stdout_persisted = $false
    stderr_persisted = $false
    prompt_persisted = $false
    transcript_persisted = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Join-Path $StateDir "pilot-result.json") -Encoding UTF8
}

function Write-ManagedModePilotRetryResult {
  param(
    [Parameter(Mandatory = $true)][string]$StateDir,
    [bool]$TimedOut = $true
  )
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  [pscustomobject]@{
    ok = $false
    schema = "skybridge.managed_mode_pilot_retry_result.v1"
    pilot_id = "managed-mode-pilot-208"
    mode = if ($TimedOut) { "retry_timeout" } else { "retry_controlled_failure" }
    final_state = if ($TimedOut) { "pilot_failed_timeout_retry_exhausted" } else { "pilot_failed_retry_exhausted" }
    prior_state = "prior_attempt_timed_out_no_mutation"
    retry_attempt = 1
    retry_count = 1
    max_retries = 1
    task_created = $true
    task_claimed = $true
    codex_execution_started = $true
    pr_created = $false
    changed_files = @()
    timed_out = $TimedOut
    token_printed = $false
  } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $StateDir "retry-result.json") -Encoding UTF8
}

function Write-ManagedModePilotRawArtifact {
  param([Parameter(Mandatory = $true)][string]$StateDir)
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  "redacted fixture raw stdout placeholder" | Set-Content -LiteralPath (Join-Path $StateDir "raw-stdout.log") -Encoding UTF8
}

function Assert-ManagedModeSafeJson {
  param($Object)
  $raw = $Object | ConvertTo-Json -Depth 100 -Compress
  if ($raw -notmatch '"token_printed"\s*:\s*false') { throw "Expected token_printed=false." }
  if ($raw -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true') {
    throw "Secret-looking or raw artifact field found."
  }
}

function Write-ManagedModeSmokeResult {
  param([string]$Scenario)
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}
