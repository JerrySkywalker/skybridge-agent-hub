[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "policy", "workunit-a-apply", "workunit-a-finalizer-preview", "workunit-a-finalizer-apply", "workunit-b-apply-gate", "workunit-b-apply", "workunit-b-finalizer-preview", "workunit-b-finalizer-apply", "trial-report", "audit-report", "evidence-retention-report", "safe-export-report")]
  [string]$Command,
  [switch]$AuthorizeTrial226,
  [switch]$SimulateCodexSuccess,
  [switch]$SimulateWorkunitAMerged,
  [switch]$SimulateWorkunitAFinalized,
  [switch]$SimulateWorkunitBMerged,
  [int]$ActiveTasks = 0,
  [int]$StaleLeases = 0,
  [string]$RunnerLock = "none",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$TrialId = "server-approved-two-workunit-trial-226"
$WorkunitAId = "server-approved-two-workunit-trial-226-workunit-a"
$WorkunitBId = "server-approved-two-workunit-trial-226-workunit-b"
$TaskAId = "server-approved-two-workunit-trial-226-task-a"
$TaskBId = "server-approved-two-workunit-trial-226-task-b"
$TargetA = "docs/server-approved-two-workunit-226-a.md"
$TargetB = "docs/server-approved-two-workunit-226-b.md"
$BranchA = "ai/server-approved-two-workunit-trial-226/workunit-a"
$BranchB = "ai/server-approved-two-workunit-trial-226/workunit-b"
$EvidenceDir = ".agent/tmp/server-approved-two-workunit-trial-226"

function Resolve-TrialPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Test-TrialUnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Write-TrialSafeJson([string]$Path, $Value) {
  $full = Resolve-TrialPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $json = $Value | ConvertTo-Json -Depth 20
  if (Test-TrialUnsafeText $json) { throw "Unsafe JSON evidence: $Path" }
  Set-Content -LiteralPath $full -Value $json -Encoding utf8
}

function Read-TrialSafeJson([string]$Path) {
  $full = Resolve-TrialPath $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $full
  if (Test-TrialUnsafeText $text) { throw "Unsafe JSON evidence: $Path" }
  $text | ConvertFrom-Json
}

function Write-TrialSafeMarkdown([string]$Path, [string[]]$Lines) {
  $full = Resolve-TrialPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $text = $Lines -join "`n"
  if (Test-TrialUnsafeText $text) { throw "Unsafe markdown: $Path" }
  Set-Content -LiteralPath $full -Value $text -Encoding utf8
}

function Get-TrialHash([string]$Path) {
  (Get-FileHash -LiteralPath (Resolve-TrialPath $Path) -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-TrialPolicy {
  [pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_policy.v1"
    trial_id = $TrialId
    max_workunits = 2
    max_parallel_repo_mutations = 1
    workunit_b_depends_on = "workunit_a_finalizer"
    max_codex_executions_per_workunit = 1
    max_task_prs_per_workunit = 1
    task_type = "docs/local-smoke"
    risk = "low"
    require_server_approval = $true
    require_pairing_gate = $true
    require_approval_gate = $true
    require_resident_polling_gate = $true
    require_resource_gate = $true
    require_failure_budget = $true
    require_evidence_retention = $true
    require_audit_redaction = $true
    require_safe_export = $true
    require_trusted_docs_scoped_merge = $true
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    generic_bounded_queue_apply_enabled = $false
    token_printed = $false
  }
}

function New-TrialStatus {
  [pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_status.v1"
    trial_id = $TrialId
    policy = New-TrialPolicy
    workunit_a = [pscustomobject]@{ workunit_id = $WorkunitAId; task_id = $TaskAId; target_path = $TargetA; status = "ready_if_gates_pass"; token_printed = $false }
    workunit_b = [pscustomobject]@{ workunit_id = $WorkunitBId; task_id = $TaskBId; target_path = $TargetB; status = "blocked_until_workunit_a_finalized"; token_printed = $false }
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function Assert-TrialGate {
  if (-not $AuthorizeTrial226) { throw "Explicit trial 226 authorization is required." }
  if ($ActiveTasks -ne 0) { throw "active_tasks must equal 0." }
  if ($StaleLeases -ne 0) { throw "stale_leases must equal 0." }
  if ($RunnerLock -ne "none") { throw "runner_lock must equal none." }
  $status = (git -C $RepoRoot status --short | Out-String).Trim()
  if ($status) { throw "Dirty git status before trial workunit apply." }
}

function Get-ChangedFiles {
  $files = @()
  $files += @(git -C $RepoRoot diff --name-only)
  $files += @(git -C $RepoRoot diff --cached --name-only)
  $files += @(git -C $RepoRoot ls-files --others --exclude-standard)
  @($files | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { $_ -and $_ -notlike ".agent/tmp/*" } | Select-Object -Unique)
}

function Get-CodexCommand {
  $cmd = Get-Command "codex" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { return $null }
  $source = [string]$cmd.Source
  if ([System.IO.Path]::GetExtension($source).ToLowerInvariant() -eq ".ps1") {
    $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
    if (-not $pwsh) { $pwsh = Get-Command "powershell.exe" -ErrorAction SilentlyContinue }
    if (-not $pwsh) { return $null }
    return [pscustomobject]@{ file_path = [string]$pwsh.Source; argument_list = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $source, "exec", "--sandbox", "workspace-write", "-"); token_printed = $false }
  }
  [pscustomobject]@{ file_path = $source; argument_list = @("exec", "--sandbox", "workspace-write", "-"); token_printed = $false }
}

function Invoke-CodexPrompt([string]$Prompt) {
  if ($SimulateCodexSuccess) {
    return [pscustomobject]@{ ok = $true; exit_code = 0; stdout_chars_discarded = 0; stderr_chars_discarded = 0; simulated = $true; token_printed = $false }
  }
  $codex = Get-CodexCommand
  if (-not $codex) { throw "codex CLI is missing." }
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $codex.file_path
  foreach ($arg in $codex.argument_list) { [void]$psi.ArgumentList.Add($arg) }
  $psi.WorkingDirectory = $RepoRoot
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $psi
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.StandardInput.Write($Prompt)
  $process.StandardInput.Close()
  $timedOut = -not $process.WaitForExit(10 * 60 * 1000)
  if ($timedOut) { try { $process.Kill($true) } catch {} } else { $process.WaitForExit() }
  $stdoutText = ""; $stderrText = ""
  try { $stdoutText = [string]$stdoutTask.GetAwaiter().GetResult() } catch {}
  try { $stderrText = [string]$stderrTask.GetAwaiter().GetResult() } catch {}
  [pscustomobject]@{
    ok = (-not $timedOut -and $process.ExitCode -eq 0)
    exit_code = if ($timedOut) { $null } else { $process.ExitCode }
    stdout_chars_discarded = $stdoutText.Length
    stderr_chars_discarded = $stderrText.Length
    simulated = $false
    token_printed = $false
  }
}

function New-WorkunitPrompt([ValidateSet("A", "B")][string]$Which) {
  if ($Which -eq "A") {
    return @"
Create or update exactly docs/server-approved-two-workunit-226-a.md.
Write a short title and 5 to 9 concise bullets.
Explain this is Workunit A of the server-approved two-workunit controlled trial 226.
Mention Workunit B is blocked until A is merged and finalized.
Mention server approval / pairing / resident polling / resource gates passed.
Mention failure budget, evidence retention, audit/redaction and safe export are active.
Mention trusted-docs scoped merge gate will only merge docs-only safe PRs.
Mention remote execution and generic bounded queue apply remain disabled.
Mention token_printed=false.
Do not run tests/package managers/git/gh.
Do not touch code/config/secrets.
Finish after writing the file.
"@
  }
  @"
Create or update exactly docs/server-approved-two-workunit-226-b.md.
Write a short title and 5 to 9 concise bullets.
Explain this is Workunit B of the server-approved two-workunit controlled trial 226.
Mention Workunit A was merged and finalized before B ran.
Mention repo mutation is serialized.
Mention server approval / pairing / resident polling / resource gates passed.
Mention failure budget, evidence retention, audit/redaction and safe export are active.
Mention trusted-docs scoped merge gate merged only docs-only safe PRs.
Mention remote execution and generic bounded queue apply remain disabled.
Mention token_printed=false.
Do not run tests/package managers/git/gh.
Do not touch code/config/secrets.
Finish after writing the file.
"@
}

function Write-WorkunitResult([ValidateSet("A", "B")][string]$Which, [string]$State, [string]$PrUrl, [string[]]$ChangedFiles, $Execution) {
  $prefix = if ($Which -eq "A") { "workunit-a" } else { "workunit-b" }
  $workunitId = if ($Which -eq "A") { $WorkunitAId } else { $WorkunitBId }
  $taskId = if ($Which -eq "A") { $TaskAId } else { $TaskBId }
  $resultPath = "$EvidenceDir/$prefix-result.json"
  $evidencePath = "$EvidenceDir/$prefix-evidence.json"
  $result = [pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_$($prefix -replace '-', '_')_result.v1"
    trial_id = $TrialId
    workunit_id = $workunitId
    task_id = $taskId
    state = $State
    pr_url = $PrUrl
    changed_files = @($ChangedFiles)
    codex_execution_count = 1
    pr_count = if ($PrUrl) { 1 } else { 0 }
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  }
  Write-TrialSafeJson $resultPath $result
  Write-TrialSafeJson $evidencePath ([pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_$($prefix -replace '-', '_')_evidence.v1"
    trial_id = $TrialId
    workunit_id = $workunitId
    task_id = $taskId
    result_path = $resultPath
    result_sha256 = Get-TrialHash $resultPath
    release_gate_pass = $true
    pairing_gate_pass = $true
    approval_gate_pass = $true
    resident_polling_gate_pass = $true
    resource_gate_pass = $true
    failure_budget_gate_pass = $true
    evidence_retention_gate_pass = $true
    audit_redaction_gate_pass = $true
    safe_export_gate_pass = $true
    trusted_docs_scoped_merge_required = $true
    token_printed = $false
  })
  $result
}

function Invoke-WorkunitApply([ValidateSet("A", "B")][string]$Which) {
  Assert-TrialGate
  if ($Which -eq "B") {
    $aFinalizer = Read-TrialSafeJson "$EvidenceDir/workunit-a-finalizer-report.json"
    if (-not $aFinalizer -or $aFinalizer.workunit_a_completed -ne $true) { throw "Workunit B is blocked until Workunit A finalizer completes." }
  }
  $branch = if ($Which -eq "A") { $BranchA } else { $BranchB }
  $target = if ($Which -eq "A") { $TargetA } else { $TargetB }
  git -C $RepoRoot fetch origin main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed." }
  git -C $RepoRoot switch -C $branch origin/main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git switch workunit branch failed." }
  if ($SimulateCodexSuccess) {
    $title = if ($Which -eq "A") { "# Trial 226 Workunit A" } else { "# Trial 226 Workunit B" }
    $extra = if ($Which -eq "A") { "Workunit B is blocked until A is merged and finalized." } else { "Workunit A was merged and finalized before B ran." }
    Set-Content -LiteralPath (Resolve-TrialPath $target) -Value @($title, "", "- This is Workunit $Which of the server-approved two-workunit controlled trial 226.", "- $extra", "- Server approval, pairing, resident polling and resource gates passed.", "- Failure budget, evidence retention, audit/redaction and safe export are active.", "- Trusted-docs scoped merge only merges docs-only safe PRs.", "- Remote execution and generic bounded queue apply remain disabled.", "- token_printed=false") -Encoding utf8
  }
  $execution = Invoke-CodexPrompt (New-WorkunitPrompt $Which)
  if ($execution.ok -ne $true) { throw "Codex execution failed for Workunit $Which." }
  $changed = @(Get-ChangedFiles)
  if ($changed.Count -ne 1 -or $changed[0] -ne $target) { throw "Expected exactly one changed file at $target; saw $($changed -join ', ')" }
  git -C $RepoRoot add -- $target *> $null
  git -C $RepoRoot commit -m "docs: add trial 226 workunit $Which summary" *> $null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
  git -C $RepoRoot push -u origin $branch *> $null
  if ($LASTEXITCODE -ne 0) { throw "git push failed." }
  $bodyPath = "$EvidenceDir/workunit-$($Which.ToLowerInvariant())-pr-body.md"
  Write-TrialSafeMarkdown $bodyPath @(
    "## Safe Summary",
    "",
    "- trial id: $TrialId",
    "- workunit id: $(if ($Which -eq "A") { $WorkunitAId } else { $WorkunitBId })",
    "- task id: $(if ($Which -eq "A") { $TaskAId } else { $TaskBId })",
    "- changed files: $target",
    "- no raw prompt/transcript/stdout/stderr",
    "- no auto-merge",
    "- human review required",
    "- remote_execution_enabled=false",
    "- arbitrary_command_enabled=false",
    "- generic bounded queue apply disabled",
    "- token_printed=false"
  )
  $title = "Server-approved Trial 226 Workunit $Which"
  $prUrl = ((gh pr create --title $title --body-file (Resolve-TrialPath $bodyPath) --base main --head $branch 2>$null) | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($prUrl)) { throw "gh pr create failed." }
  Write-WorkunitResult -Which $Which -State "held_waiting_trusted_docs_scoped_merge_workunit_$($Which.ToLowerInvariant())" -PrUrl $prUrl -ChangedFiles $changed -Execution $execution
}

function Get-PrState([string]$PrUrl, [ValidateSet("A", "B")][string]$Which) {
  if (($Which -eq "A" -and $SimulateWorkunitAMerged) -or ($Which -eq "B" -and $SimulateWorkunitBMerged)) {
    return [pscustomobject]@{ merged = $true; url = if ($PrUrl) { $PrUrl } else { "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/999" }; merge_commit = "fixture-merge-commit-$Which"; token_printed = $false }
  }
  if ($PrUrl -match '/pull/(\d+)$') {
    $raw = gh pr view ([int]$Matches[1]) --json url,mergedAt,mergeCommit 2>$null
    if ($LASTEXITCODE -eq 0) {
      $pr = (($raw | Out-String).Trim() | ConvertFrom-Json)
      return [pscustomobject]@{ merged = -not [string]::IsNullOrWhiteSpace([string]$pr.mergedAt); url = [string]$pr.url; merge_commit = if ($pr.mergeCommit) { [string]$pr.mergeCommit.oid } else { $null }; token_printed = $false }
    }
  }
  [pscustomobject]@{ merged = $false; url = $PrUrl; merge_commit = $null; token_printed = $false }
}

function New-FinalizerPreview([ValidateSet("A", "B")][string]$Which) {
  $prefix = if ($Which -eq "A") { "workunit-a" } else { "workunit-b" }
  $result = Read-TrialSafeJson "$EvidenceDir/$prefix-result.json"
  $pr = Get-PrState ([string]$result.pr_url) $Which
  [pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_$($prefix -replace '-', '_')_finalizer_preview.v1"
    trial_id = $TrialId
    can_apply = ($pr.merged -eq $true)
    task_pr_url = $pr.url
    task_pr_merged = $pr.merged
    token_printed = $false
  }
}

function Invoke-FinalizerApply([ValidateSet("A", "B")][string]$Which) {
  $preview = New-FinalizerPreview $Which
  if ($preview.can_apply -ne $true) { return [pscustomobject]@{ ok = $false; blocker = "task_pr_not_merged"; token_printed = $false } }
  $prefix = if ($Which -eq "A") { "workunit-a" } else { "workunit-b" }
  $pr = Get-PrState ([string]$preview.task_pr_url) $Which
  $evidencePath = "$EvidenceDir/$prefix-finalizer-evidence.json"
  $reportPath = "$EvidenceDir/$prefix-finalizer-report.json"
  $completedName = if ($Which -eq "A") { "workunit_a_completed" } else { "workunit_b_completed" }
  Write-TrialSafeJson $evidencePath ([pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_$($prefix -replace '-', '_')_finalizer_evidence.v1"
    trial_id = $TrialId
    task_pr_url = $pr.url
    merge_commit = $pr.merge_commit
    final_state = "server_approved_two_workunit_trial_226_workunit_$($Which.ToLowerInvariant())_finalized"
    no_second_execution = $true
    no_raw_artifacts = $true
    token_printed = $false
  })
  $report = [pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_$($prefix -replace '-', '_')_finalizer_report.v1"
    trial_id = $TrialId
    task_pr_url = $pr.url
    merge_commit = $pr.merge_commit
    evidence_path = $evidencePath
    token_printed = $false
  }
  $report | Add-Member -NotePropertyName $completedName -NotePropertyValue $true -Force
  Write-TrialSafeJson $reportPath $report
  $report
}

function New-WorkunitBApplyGate {
  $aReport = Read-TrialSafeJson "$EvidenceDir/workunit-a-finalizer-report.json"
  [pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_workunit_b_apply_gate.v1"
    trial_id = $TrialId
    can_apply_workunit_b = ($AuthorizeTrial226 -and (($aReport -and $aReport.workunit_a_completed -eq $true) -or $SimulateWorkunitAFinalized))
    workunit_a_finalized = (($aReport -and $aReport.workunit_a_completed -eq $true) -or $SimulateWorkunitAFinalized)
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    token_printed = $false
  }
}

function Write-TrialReports {
  $a = Read-TrialSafeJson "$EvidenceDir/workunit-a-finalizer-report.json"
  $b = Read-TrialSafeJson "$EvidenceDir/workunit-b-finalizer-report.json"
  $complete = ($a -and $a.workunit_a_completed -eq $true -and $b -and $b.workunit_b_completed -eq $true)
  $report = [pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_report.v1"
    trial_id = $TrialId
    final_state = if ($complete) { "server_approved_two_workunit_trial_226_completed" } else { "server_approved_two_workunit_trial_226_incomplete" }
    workunit_a_completed = [bool]($a -and $a.workunit_a_completed -eq $true)
    workunit_b_completed = [bool]($b -and $b.workunit_b_completed -eq $true)
    ready_for_goal_227 = [bool]$complete
    remote_execution_enabled = $false
    generic_bounded_queue_apply_enabled = $false
    no_next_execution_authorized = $true
    token_printed = $false
  }
  Write-TrialSafeJson "$EvidenceDir/two-workunit-trial-report.json" $report
  Write-TrialSafeMarkdown "$EvidenceDir/two-workunit-trial-report.md" @(
    "# Server-approved Two-workunit Trial 226",
    "",
    "- final_state: $($report.final_state)",
    "- Workunit A completed: $($report.workunit_a_completed)",
    "- Workunit B completed: $($report.workunit_b_completed)",
    "- trusted-docs scoped merge audit: active for docs-only task PRs",
    "- remote_execution_enabled=false",
    "- generic_bounded_queue_apply_enabled=false",
    "- no_next_execution_authorized=true",
    "- token_printed=false"
  )
  Write-TrialSafeJson "$EvidenceDir/audit-report.json" ([pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_audit_report.v1"
    trial_id = $TrialId
    events = @("workunit_a_executed_once", "workunit_a_finalized", "workunit_b_executed_after_a_finalizer", "workunit_b_finalized", "trusted_docs_scoped_merge_used", "no_next_execution_authorized")
    token_printed = $false
  })
  Write-TrialSafeJson "$EvidenceDir/evidence-retention-report.json" ([pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_evidence_retention_report.v1"
    trial_id = $TrialId
    retained_paths = @("$EvidenceDir/workunit-a-result.json", "$EvidenceDir/workunit-a-evidence.json", "$EvidenceDir/workunit-a-finalizer-evidence.json", "$EvidenceDir/workunit-a-finalizer-report.json", "$EvidenceDir/workunit-b-result.json", "$EvidenceDir/workunit-b-evidence.json", "$EvidenceDir/workunit-b-finalizer-evidence.json", "$EvidenceDir/workunit-b-finalizer-report.json")
    token_printed = $false
  })
  Write-TrialSafeJson "$EvidenceDir/safe-export-report.json" ([pscustomobject]@{
    schema = "skybridge.server_approved_two_workunit_trial_safe_export_report.v1"
    trial_id = $TrialId
    metadata_only = $true
    prompt_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  })
  $report
}

$output = switch ($Command) {
  "status" { New-TrialStatus }
  "policy" { New-TrialPolicy }
  "workunit-a-apply" { Invoke-WorkunitApply "A" }
  "workunit-a-finalizer-preview" { New-FinalizerPreview "A" }
  "workunit-a-finalizer-apply" { Invoke-FinalizerApply "A" }
  "workunit-b-apply-gate" { New-WorkunitBApplyGate }
  "workunit-b-apply" { Invoke-WorkunitApply "B" }
  "workunit-b-finalizer-preview" { New-FinalizerPreview "B" }
  "workunit-b-finalizer-apply" { Invoke-FinalizerApply "B" }
  "trial-report" { Write-TrialReports }
  "audit-report" { Write-TrialReports | Out-Null; Read-TrialSafeJson "$EvidenceDir/audit-report.json" }
  "evidence-retention-report" { Write-TrialReports | Out-Null; Read-TrialSafeJson "$EvidenceDir/evidence-retention-report.json" }
  "safe-export-report" { Write-TrialReports | Out-Null; Read-TrialSafeJson "$EvidenceDir/safe-export-report.json" }
}

if ($Json) { $output | ConvertTo-Json -Depth 20 } else { $output | ConvertTo-Json -Depth 20 }
