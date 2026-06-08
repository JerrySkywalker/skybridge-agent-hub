param(
  [ValidateSet("contract", "action-matrix", "preview", "audit", "safe-pause", "emergency-stop", "start-apply-forbidden", "no-arbitrary-shell", "no-secrets")]
  [string]$Scenario = "contract",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$control = Join-Path $PSScriptRoot "skybridge-dev-queue-control.ps1"
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")

function Invoke-ControlJson {
  param([string[]]$Arguments)
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $control @Arguments -Json 2>&1
  if ($LASTEXITCODE -ne 0) { throw "control command failed: $($raw -join "`n")" }
  return (($raw -join "`n") | ConvertFrom-Json)
}

function Assert-NoSecretText {
  param([string]$Text)
  if ($Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----') {
    throw "Secret-looking output detected."
  }
}

$matrix = Invoke-ControlJson @("-Command", "control-matrix", "-Fixture")
$byAction = @{}
foreach ($entry in @($matrix.action_matrix)) { $byAction[[string]$entry.action] = $entry }

switch ($Scenario) {
  "contract" {
    foreach ($required in @("QueueControlIntent", "QueueControlState", "QueueControlActionResponse", "QueueControlAuditEvent", "QueueControlRunBudget", "QueueControlArmLease", "queueControlActionMatrix", "fixtureQueueControlState")) {
      if ($client -notmatch [regex]::Escape($required)) { throw "Missing shared contract symbol: $required" }
    }
    if (-not $matrix.ok -or $matrix.token_printed) { throw "Invalid control matrix output." }
  }
  "action-matrix" {
    if ($byAction.refresh_status.class -ne "read_only") { throw "refresh_status must be read_only." }
    if ($byAction.report.class -ne "read_only") { throw "report must be read_only." }
    if ($byAction.preflight.class -ne "read_only") { throw "preflight must be read_only." }
    if ($byAction.heartbeat.class -ne "heartbeat_only") { throw "heartbeat must be heartbeat_only." }
    if (-not $byAction.safe_pause.apply_allowed -or -not $byAction.safe_pause.reason_required) { throw "safe_pause must allow reason-gated apply." }
    if ($byAction.start_one_preview.apply_allowed) { throw "start_one_preview must be preview-only." }
    if ($byAction.start_queue_preview.apply_allowed) { throw "start_queue_preview must be preview-only." }
    if ($byAction.start_one_apply.apply_allowed) { throw "start_one_apply must be forbidden for Goal 194." }
    if ($byAction.start_queue_apply.apply_allowed) { throw "start_queue_apply must be forbidden for Goal 194." }
    if ($byAction.start_all.class -ne "forbidden") { throw "start_all must be forbidden." }
    if ($byAction.arbitrary_shell.class -ne "forbidden") { throw "arbitrary_shell must be forbidden." }
  }
  "preview" {
    $preview = Invoke-ControlJson @("-Command", "start-one-preview", "-Fixture")
    if (-not $preview.ok -or $preview.mutates -or $preview.task_created -or $preview.worker_loop_started) { throw "start-one preview mutated or failed." }
    $mismatch = Invoke-ControlJson @("-Command", "control-preview", "-Fixture", "-ControlAction", "start_one_preview", "-TargetRevision", "wrong-revision")
    if ($mismatch.allowed -or @($mismatch.blockers) -notcontains "target_revision_mismatch") { throw "Mismatched revision was not rejected." }
  }
  "audit" {
    $audit = Invoke-ControlJson @("-Command", "safe-pause", "-Fixture", "-Apply", "-Reason", "smoke audit")
    if (-not $audit.ok -or [string]::IsNullOrWhiteSpace([string]$audit.audit_event_id)) { throw "safe-pause apply did not create audit id." }
    $auditText = Get-Content -Raw -LiteralPath $audit.audit_path
    Assert-NoSecretText $auditText
    if ($auditText -match '(raw_stdout|raw_stderr|Authorization|raw_prompt|private_key|cookie)') { throw "Audit ledger contains forbidden raw fields." }
  }
  "safe-pause" {
    $missingReasonFailed = $false
    try { Invoke-ControlJson @("-Command", "safe-pause", "-Fixture") | Out-Null } catch { $missingReasonFailed = $true }
    if (-not $missingReasonFailed) { throw "safe-pause without reason must fail." }
    $pause = Invoke-ControlJson @("-Command", "safe-pause", "-Fixture", "-Reason", "smoke preview")
    if (-not $pause.ok -or $pause.mutates) { throw "safe-pause preview must be allowed and non-mutating." }
  }
  "emergency-stop" {
    $stop = Invoke-ControlJson @("-Command", "emergency-stop", "-Fixture", "-Reason", "smoke stop preview")
    if (-not $stop.ok -or $stop.mutates -or $stop.task_created) { throw "emergency-stop preview must not create tasks." }
  }
  "start-apply-forbidden" {
    $startOne = Invoke-ControlJson @("-Command", "start-one", "-Fixture", "-Apply", "-Reason", "must fail")
    if ($startOne.allowed -or @($startOne.blockers) -notcontains "apply_forbidden_in_goal_194") { throw "start-one apply was not forbidden." }
    $startAll = Invoke-ControlJson @("-Command", "start-all", "-Fixture", "-Apply", "-Reason", "must fail")
    if ($startAll.allowed -or @($startAll.blockers) -notcontains "forbidden_action") { throw "start-all was not forbidden." }
  }
  "no-arbitrary-shell" {
    if ($client -notmatch '"arbitrary_shell"') { throw "arbitrary_shell is missing from the shared action matrix." }
    if ($byAction.arbitrary_shell.class -ne "forbidden") { throw "arbitrary_shell must be forbidden." }
  }
  "no-secrets" {
    $raw = ($matrix | ConvertTo-Json -Depth 80 -Compress)
    Assert-NoSecretText $raw
    if ($raw -notmatch '"token_printed":false') { throw "token_printed=false missing from output." }
  }
}

[pscustomobject]@{
  ok = $true
  scenario = "queue-control-$Scenario"
  current_step = "dev-queue-189-200:super-194-worker-service-mode"
  active_tasks = 0
  stale_leases = 0
  worker_status = "offline"
  can_start_one = $false
  can_start_queue = $false
  can_resume = $false
  token_printed = $false
} | ConvertTo-Json -Compress
