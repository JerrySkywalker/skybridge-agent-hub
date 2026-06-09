[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("contract", "import-reviewed-goal", "start-one-preview", "start-one-gates", "single-task-limit", "worker-route", "no-start-all", "no-second-task", "pr-safety", "evidence", "clean-worktree", "one-shot-claim-gate", "one-shot-executor-gate", "claim-refuses-second-task", "claim-refuses-wrong-campaign", "claim-refuses-wrong-task-type", "executor-path-allowlist", "pr-limit", "no-auto-merge", "lease-release", "no-raw-transcript", "no-secrets", "sanitized-executor-contract", "no-raw-prompt-persistence", "no-raw-transcript-persistence", "no-raw-stdout-stderr", "redaction", "executor-fails-closed-if-raw-logs", "executor-one-task-only", "task-pr-open-only", "task-pr-path-allowlist", "evidence-safe", "gates-are-side-effect-free", "start-one-apply-creates-one-claim", "owned-claim-resumable", "second-foreign-claim-refused", "malformed-claim-refused", "executor-resumes-owned-claim", "executor-refuses-existing-pr", "executor-refuses-existing-executor-evidence", "claim-state-safe-evidence", "no-secret-in-claim-evidence", "codex-launcher-resolves-ps1", "codex-launcher-resolves-cmd", "codex-launcher-resolves-exe", "codex-launcher-rejects-unknown", "codex-launcher-does-not-persist-raw-command", "codex-launcher-preserves-stdin", "codex-launcher-token-printed-false")]
  [string]$Scenario,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "skybridge-bootstrap-trial-goal201.ps1"

function Invoke-Trial {
  param([string]$Command, [string[]]$Extra = @())
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command @Extra -Json 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  $output | ConvertFrom-Json
}

function Assert-FalseFlag {
  param($Object, [string]$Name)
  if ($Object.PSObject.Properties[$Name] -and $Object.$Name -ne $false) {
    throw "Expected $Name=false."
  }
}

function Assert-SafeJson {
  param($Object)
  $jsonText = $Object | ConvertTo-Json -Depth 100 -Compress
  if ($jsonText -notmatch '"token_printed":false') { throw "Expected token_printed=false." }
  if ($jsonText -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true') {
    throw "Secret-looking or raw-log output detected."
  }
}

function New-SmokeStateDir {
  Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal201d-" + [Guid]::NewGuid().ToString("n"))
}

function Write-OwnedClaimEvidence {
  param([Parameter(Mandatory = $true)][string]$StateDir)
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  [pscustomobject]@{
    schema = "skybridge.bootstrap_trial_goal201_safe_claim_evidence.v1"
    campaign_id = "bootstrap-trial-201"
    goal_id = "goal-201-controlled-start-one-bootstrap-trial"
    task_id = "bootstrap-trial-201-task-001"
    worker_id = "laptop-zenbookduo"
    lease_id = "bootstrap-trial-201-lease-001"
    allowed_paths = @("README.md", "docs/**")
    claim_state = "claimed"
    claim_created_at = (Get-Date).ToUniversalTime().ToString("o")
    executor_evidence_path = $null
    pr_url = $null
    prompt_included = $false
    raw_transcript_included = $false
    raw_logs_included = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $StateDir "claim-evidence.json") -Encoding UTF8
}

function New-LauncherFixture {
  param(
    [Parameter(Mandatory = $true)][string]$Extension,
    [switch]$ReadsStdin
  )
  $stateDir = New-SmokeStateDir
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  $name = if ([string]::IsNullOrWhiteSpace($Extension)) { "codex" } else { "codex$Extension" }
  $path = Join-Path $stateDir $name
  if ($ReadsStdin -or $Extension -eq ".ps1") {
    $markerPath = Join-Path $stateDir "stdin-marker.txt"
@'
$stdinText = [Console]::In.ReadToEnd()
[System.IO.File]::WriteAllText($env:SKYBRIDGE_STDIN_MARKER, $stdinText, [System.Text.Encoding]::UTF8)
exit 0
'@ | Set-Content -LiteralPath $path -Encoding UTF8
  } elseif ($Extension -eq ".cmd" -or $Extension -eq ".bat") {
    "@echo off`r`nexit /b 0`r`n" | Set-Content -LiteralPath $path -Encoding ASCII
    $markerPath = $null
  } elseif ($Extension -eq ".exe") {
    New-Item -ItemType File -Path $path -Force | Out-Null
    $markerPath = $null
  } else {
    New-Item -ItemType File -Path $path -Force | Out-Null
    $markerPath = $null
  }
  [pscustomobject]@{ state_dir = $stateDir; path = $path; marker_path = $markerPath; token_printed = $false }
}

function Assert-LauncherContract {
  param(
    [Parameter(Mandatory = $true)][string]$Extension,
    [Parameter(Mandatory = $true)][string]$ExpectedKind
  )
  $fixture = New-LauncherFixture -Extension $Extension
  try {
    $contract = Invoke-Trial -Command sanitized-executor-contract -Extra @("-MockCodexPath", $fixture.path)
    if (-not $contract.ok) { throw "Launcher contract blocked: $(@($contract.blockers) -join '; ')" }
    if ($contract.launcher_metadata.launcher_kind -ne $ExpectedKind) { throw "Unexpected launcher kind." }
    if ($contract.launcher_metadata.command_class -ne "codex_exec_sanitized_stdin_discard_output") { throw "Unexpected command class." }
    foreach ($flag in @("prompt_persisted", "transcript_persisted", "stdout_persisted", "stderr_persisted", "token_printed")) {
      if ($contract.launcher_metadata.$flag -ne $false) { throw "Expected launcher metadata $flag=false." }
    }
    $contract
  } finally {
    Remove-Item -LiteralPath $fixture.state_dir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$result = switch ($Scenario) {
  "contract" {
    $contract = Invoke-Trial -Command contract
    if (-not $contract.ok) { throw "Contract failed: $(@($contract.errors) -join '; ')" }
    if ($contract.campaign_id -ne "bootstrap-trial-201") { throw "Unexpected campaign id." }
    if ($contract.reviewed_goal_id -ne "goal-201-controlled-start-one-bootstrap-trial") { throw "Unexpected goal id." }
    if ($contract.task_type -ne "docs/local-smoke") { throw "Unexpected task type." }
    if ($contract.run_budget.max_steps -ne 1 -or $contract.run_budget.max_tasks -ne 1 -or $contract.run_budget.max_prs -ne 1) { throw "Budget must be one-shot." }
    $contract
  }
  "import-reviewed-goal" {
    $import = Invoke-Trial -Command import-reviewed-goal
    if (-not $import.imported_or_staged -or -not $import.execution_review_required) { throw "Reviewed trial import/stage marker missing." }
    if ($import.proposed_goal_id -ne "proposed-goal-201-local-readme-refresh") { throw "Original proposed goal trace missing." }
    $import
  }
  "start-one-preview" {
    $preview = Invoke-Trial -Command start-one-preview
    if ($preview.selected_goal_id -ne "goal-201-controlled-start-one-bootstrap-trial") { throw "Preview selected wrong goal." }
    if ($preview.task_type -ne "docs/local-smoke") { throw "Preview selected wrong task type." }
    if ($preview.would_create_tasks -gt 1) { throw "Preview must never create more than one task." }
    foreach ($flag in @("task_created", "task_claimed", "task_executed", "worker_loop_started", "pr_created")) { Assert-FalseFlag $preview $flag }
    $preview
  }
  "start-one-gates" {
    $gate = Invoke-Trial -Command start-one-gates -Extra @("-Reason", "smoke gate reason")
    if (-not $gate.ok) { throw "Start-one gates should pass after sanitized executor boundary: $(@($gate.blockers) -join '; ')" }
    if ($gate.operator_reason_recorded -ne $true) { throw "Operator reason was not recorded." }
    $gate
  }
  "one-shot-claim-gate" {
    $claim = Invoke-Trial -Command one-shot-claim-gate
    if (-not $claim.ok) { throw "Claim gate should pass in preview: $(@($claim.blockers) -join '; ')" }
    if ($claim.campaign_id -ne "bootstrap-trial-201" -or $claim.goal_id -ne "goal-201-controlled-start-one-bootstrap-trial") { throw "Claim gate selected wrong trial." }
    if ($claim.task_type -ne "docs/local-smoke") { throw "Claim gate selected wrong task type." }
    if ($claim.worker_id -ne "laptop-zenbookduo") { throw "Claim gate selected unexpected worker." }
    if ($claim.run_budget.max_tasks -ne 1 -or $claim.run_budget.max_prs -ne 1) { throw "Claim gate budget must be one-shot." }
    foreach ($flag in @("task_created", "task_claimed", "lease_created", "start_all_allowed", "start_queue_allowed", "second_task_allowed")) { Assert-FalseFlag $claim $flag }
    $claim
  }
  "one-shot-executor-gate" {
    $executor = Invoke-Trial -Command one-shot-executor-gate
    if (-not $executor.ok) { throw "Executor gate should pass after sanitized executor boundary: $(@($executor.blockers) -join '; ')" }
    foreach ($flag in @("task_claimed", "task_executed", "codex_worker_execution_started", "pr_created", "auto_merge_enabled", "raw_transcript_included", "raw_logs_included", "external_notification_sent", "stdout_persisted", "stderr_persisted", "prompt_persisted")) { Assert-FalseFlag $executor $flag }
    $executor
  }
  "claim-refuses-second-task" {
    $stateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal201b-" + [Guid]::NewGuid().ToString("n"))
    $first = Invoke-Trial -Command one-shot-claim-gate -Extra @("-Apply", "-StateDir", $stateDir)
    if (-not $first.ok -or -not $first.task_claimed -or -not $first.lease_created) { throw "First one-shot claim apply did not create safe claim evidence." }
    $second = Invoke-Trial -Command one-shot-claim-gate -Extra @("-Apply", "-StateDir", $stateDir)
    if (-not $second.ok -or $second.claim_state -ne "resumable_owned_claim") { throw "Owned second claim did not resume safely." }
    if ($second.task_created -ne $false -or $second.task_claimed -ne $true) { throw "Second claim created a duplicate task instead of resuming." }
    Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    $second
  }
  "claim-refuses-wrong-campaign" {
    $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-CampaignId", "wrong-campaign")
    if (@($claim.blockers) -notcontains "wrong_campaign_refused") { throw "Wrong campaign was not refused." }
    $claim
  }
  "claim-refuses-wrong-task-type" {
    $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-TaskType", "backend")
    if (@($claim.blockers) -notcontains "wrong_task_type_refused") { throw "Wrong task type was not refused." }
    $claim
  }
  "executor-path-allowlist" {
    $executor = Invoke-Trial -Command one-shot-executor-gate -Extra @("-AllowedPaths", "apps/server/src/index.ts")
    if (-not (@($executor.blockers) -match "^path_allowlist_violation:")) { throw "Path allowlist violation was not reported." }
    $executor
  }
  "pr-limit" {
    $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-MaxPrs", "2")
    if (@($claim.blockers) -notcontains "max_prs_must_be_1") { throw "PR limit was not enforced." }
    $claim
  }
  "no-auto-merge" {
    $pr = Invoke-Trial -Command pr-safety
    if ($pr.auto_merge_enabled -ne $false) { throw "Auto-merge must be disabled." }
    $pr
  }
  "lease-release" {
    $stateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal201b-" + [Guid]::NewGuid().ToString("n"))
    $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-Apply", "-StateDir", $stateDir)
    if ($claim.lease_created -ne $true) { throw "Expected lease evidence for first claim." }
    Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    $after = Invoke-Trial -Command one-shot-claim-gate -Extra @("-StateDir", $stateDir)
    if (-not $after.ok) { throw "Lease evidence cleanup should leave gate available again." }
    $after | Add-Member -NotePropertyName lease_outcome -NotePropertyValue "released_by_cleanup" -Force
    $after
  }
  "no-raw-transcript" {
    $executor = Invoke-Trial -Command one-shot-executor-gate
    if ($executor.raw_transcript_included -ne $false -or $executor.raw_logs_included -ne $false) { throw "Raw transcript/log flags must be false." }
    $executor
  }
  "sanitized-executor-contract" {
    $contract = Invoke-Trial -Command sanitized-executor-contract
    if (-not $contract.ok) { throw "Sanitized executor contract blocked: $(@($contract.blockers) -join '; ')" }
    if ($contract.prompt_persisted -ne $false -or $contract.transcript_persisted -ne $false) { throw "Prompt/transcript persistence must be false." }
    if ($contract.stdout_persisted -ne $false -or $contract.stderr_persisted -ne $false) { throw "stdout/stderr persistence must be false." }
    if ($contract.max_codex_executions -ne 1 -or $contract.max_tasks -ne 1 -or $contract.max_prs -ne 1) { throw "Executor must be one-shot." }
    $contract
  }
  "no-raw-prompt-persistence" {
    $contract = Invoke-Trial -Command sanitized-executor-contract
    if ($contract.prompt_persisted -ne $false) { throw "Prompt must not be persisted." }
    $contract
  }
  "no-raw-transcript-persistence" {
    $contract = Invoke-Trial -Command sanitized-executor-contract
    if ($contract.transcript_persisted -ne $false) { throw "Transcript must not be persisted." }
    $contract
  }
  "no-raw-stdout-stderr" {
    $contract = Invoke-Trial -Command sanitized-executor-contract
    if ($contract.stdout_persisted -ne $false -or $contract.stderr_persisted -ne $false) { throw "stdout/stderr must not be persisted." }
    $contract
  }
  "redaction" {
    $redaction = Invoke-Trial -Command sanitized-redaction-test
    if (-not $redaction.ok -or -not $redaction.redacted_secret_markers) { throw "Redaction failed." }
    $redaction
  }
  "executor-fails-closed-if-raw-logs" {
    $executor = Invoke-Trial -Command one-shot-executor-gate -Extra @("-SimulateRawLogPersistence")
    if ($executor.ok) { throw "Executor must fail closed when raw log persistence is simulated." }
    if (@($executor.blockers) -notcontains "sanitized_executor_refused_forced_log_persistence") { throw "Expected raw log persistence blocker." }
    $executor
  }
  "executor-one-task-only" {
    $contract = Invoke-Trial -Command sanitized-executor-contract
    if ($contract.max_tasks -ne 1 -or $contract.max_codex_executions -ne 1) { throw "Expected one task and one Codex execution." }
    $contract
  }
  "task-pr-open-only" {
    $pr = Invoke-Trial -Command pr-safety
    if ($pr.auto_merge_enabled -ne $false) { throw "Task PR must not auto-merge." }
    $pr | Add-Member -NotePropertyName task_pr_expected_state -NotePropertyValue "open" -Force
    $pr
  }
  "task-pr-path-allowlist" {
    $executor = Invoke-Trial -Command one-shot-executor-gate -Extra @("-AllowedPaths", "apps/server/src/index.ts")
    if (-not (@($executor.blockers) -match "^path_allowlist_violation:")) { throw "Path allowlist violation was not reported." }
    $executor
  }
  "evidence-safe" {
    $contract = Invoke-Trial -Command sanitized-executor-contract
    foreach ($flag in @("prompt_persisted", "transcript_persisted", "stdout_persisted", "stderr_persisted", "auto_merge_enabled")) { Assert-FalseFlag $contract $flag }
    $contract
  }
  "gates-are-side-effect-free" {
    $stateDir = New-SmokeStateDir
    try {
      $claimPath = Join-Path $stateDir "claim-evidence.json"
      $beforeExists = Test-Path -LiteralPath $claimPath -PathType Leaf
      $preview = Invoke-Trial -Command start-one-preview -Extra @("-StateDir", $stateDir)
      $gates = Invoke-Trial -Command start-one-gates -Extra @("-StateDir", $stateDir, "-Reason", "side effect free smoke")
      $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-StateDir", $stateDir)
      $afterExists = Test-Path -LiteralPath $claimPath -PathType Leaf
      if ($beforeExists -or $afterExists) { throw "Preview/gate path wrote claim evidence." }
      foreach ($item in @($preview, $gates, $claim)) {
        if ($item.mutates -eq $true -or $item.task_created -eq $true -or $item.task_claimed -eq $true -or $item.lease_created -eq $true) {
          throw "Preview/gate path reported mutation."
        }
      }
      [pscustomobject]@{ ok = $true; scenario = "gates-are-side-effect-free"; token_printed = $false }
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "start-one-apply-creates-one-claim" {
    $stateDir = New-SmokeStateDir
    try {
      $first = Invoke-Trial -Command start-one-apply -Extra @("-Apply", "-StateDir", $stateDir, "-Reason", "smoke authorized one claim")
      if (-not $first.ok -or -not $first.task_claimed) { throw "start-one apply did not create the first owned claim." }
      $claimPath = Join-Path $stateDir "claim-evidence.json"
      if (-not (Test-Path -LiteralPath $claimPath -PathType Leaf)) { throw "Claim evidence missing." }
      $before = Get-Content -Raw -LiteralPath $claimPath
      $second = Invoke-Trial -Command start-one-apply -Extra @("-Apply", "-StateDir", $stateDir, "-Reason", "smoke resume owned claim")
      $after = Get-Content -Raw -LiteralPath $claimPath
      if (-not $second.ok -or $second.task_created -ne $false -or $second.task_claimed -ne $true) { throw "Second start-one apply did not resume the owned claim." }
      if (($after | ConvertFrom-Json).claim_state -ne "resumable_owned_claim") { throw "Owned claim was not marked resumable." }
      if (($before | ConvertFrom-Json).task_id -ne "bootstrap-trial-201-task-001") { throw "Unexpected first claim task id." }
      $second
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "owned-claim-resumable" {
    $stateDir = New-SmokeStateDir
    try {
      Write-OwnedClaimEvidence -StateDir $stateDir
      $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-StateDir", $stateDir)
      if (-not $claim.ok -or $claim.claim_state -ne "resumable_owned_claim") { throw "Owned claim was not resumable." }
      if (@($claim.blockers).Count -ne 0) { throw "Owned resumable claim had blockers: $(@($claim.blockers) -join '; ')" }
      $claim
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "second-foreign-claim-refused" {
    $stateDir = New-SmokeStateDir
    try {
      Write-OwnedClaimEvidence -StateDir $stateDir
      $claimPath = Join-Path $stateDir "claim-evidence.json"
      $foreign = Get-Content -Raw -LiteralPath $claimPath | ConvertFrom-Json
      $foreign.worker_id = "foreign-worker"
      $foreign | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $claimPath -Encoding UTF8
      $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-Apply", "-StateDir", $stateDir)
      if ($claim.ok -or @($claim.blockers) -notcontains "foreign_claim_refused") { throw "Foreign claim was not refused." }
      $claim
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "malformed-claim-refused" {
    $stateDir = New-SmokeStateDir
    try {
      New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
      Set-Content -LiteralPath (Join-Path $stateDir "claim-evidence.json") -Value "{ not-json" -Encoding UTF8
      $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-Apply", "-StateDir", $stateDir)
      if ($claim.ok -or @($claim.blockers) -notcontains "malformed_claim_refused") { throw "Malformed claim was not refused." }
      $claim
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "executor-resumes-owned-claim" {
    $stateDir = New-SmokeStateDir
    try {
      Write-OwnedClaimEvidence -StateDir $stateDir
      $executor = Invoke-Trial -Command run-sanitized-executor -Extra @("-StateDir", $stateDir)
      if (-not $executor.ok -or $executor.mode -ne "preview" -or $executor.would_run_codex -ne $true) { throw "Executor preview did not accept valid owned claim." }
      $executor
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "executor-refuses-existing-pr" {
    $stateDir = New-SmokeStateDir
    try {
      Write-OwnedClaimEvidence -StateDir $stateDir
      $executor = Invoke-Trial -Command run-sanitized-executor -Extra @("-Apply", "-StateDir", $stateDir, "-SimulateExistingOpenTaskPr")
      if ($executor.ok -or @($executor.blockers) -notcontains "existing_open_task_pr_for_bootstrap_trial") { throw "Executor did not refuse existing PR." }
      $executor
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "executor-refuses-existing-executor-evidence" {
    $stateDir = New-SmokeStateDir
    try {
      Write-OwnedClaimEvidence -StateDir $stateDir
      [pscustomobject]@{ schema = "fixture"; token_printed = $false } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDir "sanitized-executor-evidence.json") -Encoding UTF8
      $executor = Invoke-Trial -Command run-sanitized-executor -Extra @("-Apply", "-StateDir", $stateDir)
      if ($executor.ok -or @($executor.blockers) -notcontains "existing_executor_evidence_for_bootstrap_trial") { throw "Executor did not refuse existing executor evidence." }
      $executor
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "claim-state-safe-evidence" {
    $stateDir = New-SmokeStateDir
    try {
      $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-Apply", "-StateDir", $stateDir)
      $evidence = Get-Content -Raw -LiteralPath (Join-Path $stateDir "claim-evidence.json") | ConvertFrom-Json
      foreach ($field in @("claim_state", "claim_created_at", "executor_evidence_path", "pr_url", "token_printed")) {
        if (-not $evidence.PSObject.Properties[$field]) { throw "Missing safe evidence field: $field" }
      }
      if ($evidence.claim_state -ne "claimed" -or $evidence.token_printed -ne $false) { throw "Unexpected safe evidence state." }
      $claim
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "no-secret-in-claim-evidence" {
    $stateDir = New-SmokeStateDir
    try {
      $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-Apply", "-StateDir", $stateDir)
      $raw = Get-Content -Raw -LiteralPath (Join-Path $stateDir "claim-evidence.json")
      if ($raw -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true') {
        throw "Claim evidence contains secret-looking or raw-log content."
      }
      $claim
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "codex-launcher-resolves-ps1" {
    $contract = Assert-LauncherContract -Extension ".ps1" -ExpectedKind "ps1"
    if ($contract.launcher_metadata.host_executable_name -notin @("pwsh.exe", "pwsh", "powershell.exe")) { throw "Unexpected PowerShell host." }
    $contract
  }
  "codex-launcher-resolves-cmd" {
    $contract = Assert-LauncherContract -Extension ".cmd" -ExpectedKind "cmd"
    if ($contract.launcher_metadata.host_executable_name -ne "cmd.exe") { throw "Expected cmd.exe host." }
    $contract
  }
  "codex-launcher-resolves-exe" {
    Assert-LauncherContract -Extension ".exe" -ExpectedKind "codex.exe"
  }
  "codex-launcher-rejects-unknown" {
    $fixture = New-LauncherFixture -Extension ".txt"
    try {
      $contract = Invoke-Trial -Command sanitized-executor-contract -Extra @("-MockCodexPath", $fixture.path)
      if ($contract.ok -or @($contract.blockers) -notcontains "codex_launcher_unclassified_or_missing") { throw "Unknown launcher was not refused." }
      $contract
    } finally {
      Remove-Item -LiteralPath $fixture.state_dir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "codex-launcher-does-not-persist-raw-command" {
    $fixture = New-LauncherFixture -Extension ".ps1"
    try {
      $contract = Invoke-Trial -Command sanitized-executor-contract -Extra @("-MockCodexPath", $fixture.path)
      $contractJsonText = $contract | ConvertTo-Json -Depth 100 -Compress
      if ($contractJsonText -match [regex]::Escape($fixture.path)) { throw "Raw launcher path leaked into safe metadata." }
      if ($contract.launcher_metadata.PSObject.Properties["file_path"] -or $contract.launcher_metadata.PSObject.Properties["argument_list"]) { throw "Raw command fields leaked into launcher metadata." }
      $contract
    } finally {
      Remove-Item -LiteralPath $fixture.state_dir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "codex-launcher-preserves-stdin" {
    $fixture = New-LauncherFixture -Extension ".ps1" -ReadsStdin
    try {
      $env:SKYBRIDGE_STDIN_MARKER = $fixture.marker_path
      $stdinResult = Invoke-Trial -Command codex-launcher-stdin-test -Extra @("-MockCodexPath", $fixture.path)
      if (-not $stdinResult.ok -or $stdinResult.stdin_preserved -ne $true) { throw "stdin was not preserved through launcher." }
      $stdinResult
    } finally {
      Remove-Item Env:\SKYBRIDGE_STDIN_MARKER -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $fixture.state_dir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "codex-launcher-token-printed-false" {
    $contract = Assert-LauncherContract -Extension ".ps1" -ExpectedKind "ps1"
    if ($contract.token_printed -ne $false -or $contract.launcher_metadata.token_printed -ne $false) { throw "Expected token_printed=false." }
    $contract
  }
  "no-secrets" {
    $claim = Invoke-Trial -Command one-shot-claim-gate
    Assert-SafeJson $claim
    $claim
  }
  "single-task-limit" {
    $contract = Invoke-Trial -Command contract
    $second = Invoke-Trial -Command no-second-task
    if ($contract.run_budget.max_tasks -ne 1 -or $second.second_task_allowed -ne $false) { throw "Single-task limit not enforced." }
    $second
  }
  "worker-route" {
    $route = Invoke-Trial -Command worker-route
    if (@($route.decisions | Where-Object { $_.accepted }).Count -ne 1) { throw "Expected exactly one accepted worker." }
    if (-not $route.selected_worker) { throw "Expected selected worker." }
    foreach ($flag in @("task_created", "task_claimed", "task_executed", "worker_loop_started", "queue_execution_enabled")) { Assert-FalseFlag $route $flag }
    $route
  }
  "no-start-all" {
    $noStartAll = Invoke-Trial -Command no-start-all
    if ($noStartAll.start_all_allowed -ne $false) { throw "start-all must be forbidden." }
    $noStartAll
  }
  "no-second-task" {
    $noSecond = Invoke-Trial -Command no-second-task
    if ($noSecond.second_task_allowed -ne $false -or $noSecond.max_tasks -ne 1) { throw "Second task must be forbidden." }
    $noSecond
  }
  "pr-safety" {
    $pr = Invoke-Trial -Command pr-safety
    if ($pr.target_branch -ne "main") { throw "PR target must be main." }
    if ($pr.auto_merge_enabled -ne $false) { throw "Auto-merge must be disabled." }
    if ($pr.github_settings_mutation_allowed -ne $false) { throw "GitHub settings mutation must be forbidden." }
    $pr
  }
  "evidence" {
    $evidence = Invoke-Trial -Command evidence
    if ($evidence.final_state -notin @("ready_for_one_shot_start_one_apply", "held_no_execution_executor_gate_blocked")) { throw "Unexpected final state." }
    if ($evidence.lease_outcome -ne "no_lease_created") { throw "No lease should be created." }
    foreach ($flag in @("no_start_all", "no_second_task", "no_auto_merge")) {
      if ($evidence.$flag -ne $true) { throw "Expected $flag=true." }
    }
    $evidence
  }
  "clean-worktree" {
    $before = (git status --short | Out-String).Trim()
    $clean = Invoke-Trial -Command clean-worktree
    $after = (git status --short | Out-String).Trim()
    if ($before -ne $after) { throw "Smoke changed worktree." }
    $clean
  }
}

Assert-SafeJson $result

$summary = [pscustomobject]@{
  ok = $true
  scenario = "bootstrap-trial-goal201-$Scenario"
  result = $result
  executed = $false
  task_created = $false
  task_claimed = $false
  task_executed = $false
  worker_loop_started = $false
  pr_created = $false
  auto_merge_enabled = $false
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 100 -Compress } else { $summary | Format-List }
