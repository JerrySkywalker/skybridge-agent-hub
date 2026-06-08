[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("queue", "approve-requires-reason", "reject-requires-reason", "risk-gating", "edit-hash", "import-preview", "import-apply-approved-only", "import-no-execution", "import-manifest-validation", "import-dependency-validation", "attention", "no-secrets", "clean-worktree")]
  [string]$Scenario,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal-draft-review-" + [Guid]::NewGuid().ToString("n"))
$proposedDir = Join-Path $tempRoot "goals\proposed"
$reviewedDir = Join-Path $tempRoot "goals\reviewed"
$statePath = Join-Path $tempRoot "review-state.json"
$script = Join-Path $PSScriptRoot "skybridge-goal-draft-review.ps1"

function Invoke-Review {
  param([string[]]$Arguments, [switch]$ExpectFailure)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    if ($ExpectFailure) { return [pscustomobject]@{ failed = $true; output = ($output -join "`n") } }
    throw ($output -join "`n")
  }
  if ($ExpectFailure) { throw "Expected command to fail: $($Arguments -join ' ')" }
  return ($output | ConvertFrom-Json)
}

function Copy-Fixtures {
  New-Item -ItemType Directory -Path $proposedDir -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot "goals\proposed\proposed-goal-201-local-readme-refresh.md") -Destination (Join-Path $proposedDir "proposed-goal-201-local-readme-refresh.md") -Force
  $unsafe = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-goal-draft.ps1") -Command goal-draft-generate-preview -Fixture unsafe -Json | ConvertFrom-Json
  $unsafe.markdown_preview | Set-Content -LiteralPath (Join-Path $proposedDir "proposed-unsafe-production-deploy.md") -Encoding UTF8
}

function BaseArgs {
  @("-ProposedDir", $proposedDir, "-ReviewStatePath", $statePath, "-ImportRoot", $reviewedDir)
}

try {
  Copy-Fixtures
  $safeDraft = Join-Path $proposedDir "proposed-goal-201-local-readme-refresh.md"
  $unsafeDraft = Join-Path $proposedDir "proposed-unsafe-production-deploy.md"
  $result = $null

  switch ($Scenario) {
    "queue" {
      $queue = Invoke-Review -Arguments (@("-Command", "review-queue", "-Json") + (BaseArgs))
      if ($queue.proposed_goal_count -ne 2 -or $queue.pending_review_count -lt 2) { throw "Expected two pending review drafts." }
      foreach ($field in @("draft_id", "proposed_goal_id", "proposed_markdown_path", "review_status", "reviewer", "decision", "decision_reason", "risk_level", "safety_classification", "original_hash", "edited_hash", "import_status", "import_target", "import_preview", "generated_at", "reviewed_at", "token_printed")) {
        if (-not $queue.reviews[0].PSObject.Properties[$field]) { throw "Review model missing $field." }
      }
      $result = @{ queue = "passed" }
    }
    "approve-requires-reason" {
      $failure = Invoke-Review -ExpectFailure -Arguments (@("-Command", "approve-apply", "-DraftPath", $safeDraft, "-Json") + (BaseArgs))
      if ($failure.output -notmatch "requires -Reason") { throw "Approve did not require reason." }
      $result = @{ approve_requires_reason = "passed" }
    }
    "reject-requires-reason" {
      $failure = Invoke-Review -ExpectFailure -Arguments (@("-Command", "reject-apply", "-DraftPath", $safeDraft, "-Json") + (BaseArgs))
      if ($failure.output -notmatch "requires -Reason") { throw "Reject did not require reason." }
      $result = @{ reject_requires_reason = "passed" }
    }
    "risk-gating" {
      $failure = Invoke-Review -ExpectFailure -Arguments (@("-Command", "approve-apply", "-DraftPath", $unsafeDraft, "-Reason", "fixture blocked risk review", "-Json") + (BaseArgs))
      if ($failure.output -notmatch "cannot be approved") { throw "Unsafe draft was not blocked." }
      $preview = Invoke-Review -Arguments (@("-Command", "approve-preview", "-DraftPath", $unsafeDraft, "-Json") + (BaseArgs))
      if ($preview.ok -ne $false -or @($preview.blocked_reasons).Count -eq 0) { throw "Unsafe preview must be blocked." }
      $result = @{ risk_gating = "passed" }
    }
    "edit-hash" {
      $before = Invoke-Review -Arguments (@("-Command", "validate-draft", "-DraftPath", $safeDraft, "-Json") + (BaseArgs))
      $edit = Invoke-Review -Arguments (@("-Command", "edit-apply", "-DraftPath", $safeDraft, "-EditText", "Fixture review edit for hash recompute.", "-Json") + (BaseArgs))
      if ($edit.review.edited_hash -eq $before.validation.original_hash) { throw "Edit did not recompute hash." }
      $result = @{ edit_hash = "passed"; before = $before.validation.original_hash; after = $edit.review.edited_hash }
    }
    "import-preview" {
      Invoke-Review -Arguments (@("-Command", "approve-apply", "-DraftPath", $safeDraft, "-Reason", "low risk docs fixture approved", "-Json") + (BaseArgs)) | Out-Null
      $preview = Invoke-Review -Arguments (@("-Command", "import-preview", "-DraftPath", $safeDraft, "-Json") + (BaseArgs))
      if ($preview.mode -ne "dry-run" -or $preview.task_created -or $preview.worker_loop_started -or $preview.queue_execution_enabled) { throw "Import preview was not safe dry-run." }
      if ($preview.import_target -notmatch "goals/reviewed") { throw "Unexpected import target." }
      $result = @{ import_preview = "passed" }
    }
    "import-apply-approved-only" {
      $failure = Invoke-Review -ExpectFailure -Arguments (@("-Command", "import-apply", "-DraftPath", $safeDraft, "-Reason", "try import before approval", "-Json") + (BaseArgs))
      if ($failure.output -notmatch "requires an approved draft") { throw "Import apply did not require approval." }
      Invoke-Review -Arguments (@("-Command", "approve-apply", "-DraftPath", $safeDraft, "-Reason", "low risk docs fixture approved", "-Json") + (BaseArgs)) | Out-Null
      $apply = Invoke-Review -Arguments (@("-Command", "import-apply", "-DraftPath", $safeDraft, "-Reason", "explicit dry-run-first import apply", "-Json") + (BaseArgs))
      if (-not $apply.imported -or -not $apply.imported_goal_requires_execution_review) { throw "Approved import did not stage review-required goal." }
      $result = @{ import_apply_approved_only = "passed" }
    }
    "import-no-execution" {
      Invoke-Review -Arguments (@("-Command", "approve-apply", "-DraftPath", $safeDraft, "-Reason", "low risk docs fixture approved", "-Json") + (BaseArgs)) | Out-Null
      $apply = Invoke-Review -Arguments (@("-Command", "import-apply", "-DraftPath", $safeDraft, "-Reason", "explicit dry-run-first import apply", "-Json") + (BaseArgs))
      foreach ($field in @("executed", "task_created", "worker_loop_started", "queue_execution_enabled")) {
        if ($apply.$field -ne $false) { throw "$field must be false." }
      }
      $result = @{ import_no_execution = "passed" }
    }
    "import-manifest-validation" {
      Invoke-Review -Arguments (@("-Command", "approve-apply", "-DraftPath", $safeDraft, "-Reason", "low risk docs fixture approved", "-Json") + (BaseArgs)) | Out-Null
      Invoke-Review -Arguments (@("-Command", "import-apply", "-DraftPath", $safeDraft, "-Reason", "first import", "-Json") + (BaseArgs)) | Out-Null
      Invoke-Review -Arguments (@("-Command", "approve-apply", "-DraftPath", $safeDraft, "-Reason", "duplicate import check", "-Json") + (BaseArgs)) | Out-Null
      $preview = Invoke-Review -Arguments (@("-Command", "import-preview", "-DraftPath", $safeDraft, "-Json") + (BaseArgs))
      if (-not $preview.validation.duplicate_goal_id -or -not $preview.validation.duplicate_order) { throw "Expected duplicate goal/order validation." }
      $result = @{ import_manifest_validation = "passed" }
    }
    "import-dependency-validation" {
      $text = Get-Content -Raw -LiteralPath $safeDraft
      $text = $text -replace '"super-200-controlled-goal-draft-review-import"', '"missing-goal-dependency"'
      $text | Set-Content -LiteralPath $safeDraft -Encoding UTF8
      Invoke-Review -Arguments (@("-Command", "approve-apply", "-DraftPath", $safeDraft, "-Reason", "low risk docs fixture approved", "-Json") + (BaseArgs)) | Out-Null
      $preview = Invoke-Review -Arguments (@("-Command", "import-preview", "-DraftPath", $safeDraft, "-Json") + (BaseArgs))
      if (@($preview.validation.missing_dependencies).Count -eq 0) { throw "Expected missing dependency validation." }
      $result = @{ import_dependency_validation = "passed" }
    }
    "attention" {
      $attention = Invoke-Review -Arguments (@("-Command", "attention-events", "-Json") + (BaseArgs))
      foreach ($event in @("proposed_goal_needs_review", "proposed_goal_approved", "proposed_goal_rejected", "proposed_goal_import_preview_ready", "proposed_goal_imported", "imported_goal_requires_execution_review", "unsafe_import_blocked")) {
        if (@($attention.attention_events.event_type) -notcontains $event) { throw "Missing attention event $event." }
      }
      if ($attention.external_notification_sent -ne $false) { throw "Attention smoke must not send external notifications." }
      $result = @{ attention = "passed" }
    }
    "no-secrets" {
      $outputs = @()
      $outputs += (Invoke-Review -Arguments (@("-Command", "review-queue", "-Json") + (BaseArgs)) | ConvertTo-Json -Depth 50 -Compress)
      $outputs += (Invoke-Review -Arguments (@("-Command", "safe-summary", "-Json") + (BaseArgs)) | ConvertTo-Json -Depth 50 -Compress)
      $joined = $outputs -join "`n"
      if ($joined -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|token_printed"\s*:\s*true') { throw "Secret-looking output detected." }
      $result = @{ no_secrets = "passed" }
    }
    "clean-worktree" {
      $before = git -C $repoRoot status --short
      Invoke-Review -Arguments (@("-Command", "import-preview", "-DraftPath", $safeDraft, "-Json") + (BaseArgs)) | Out-Null
      $after = git -C $repoRoot status --short
      if (($before -join "`n") -ne ($after -join "`n")) { throw "Dry-run changed git worktree." }
      $result = @{ clean_worktree = "passed" }
    }
  }

  $summary = [pscustomobject]@{
    ok = $true
    scenario = "goal-draft-review-$Scenario"
    result = $result
    executed = $false
    task_created = $false
    worker_loop_started = $false
    queue_execution_enabled = $false
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 20 -Compress } else { $summary | Format-List }
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
