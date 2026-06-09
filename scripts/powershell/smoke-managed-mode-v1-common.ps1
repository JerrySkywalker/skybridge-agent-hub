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
