$ErrorActionPreference = "Stop"

function Get-SkyBridgeRoot {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Read-SkyBridgeFile([string]$RelativePath) {
  return Get-Content -Raw -LiteralPath (Join-Path (Get-SkyBridgeRoot) $RelativePath)
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if ($Text -notmatch [regex]::Escape($Needle)) { throw $Message }
}

function Invoke-TrialJson([string[]]$Arguments) {
  $script = Join-Path $PSScriptRoot "skybridge-boinc-v1-controlled-trial.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments
  if ($LASTEXITCODE -ne 0) { throw "controlled trial command failed." }
  ($raw | Out-String).Trim() | ConvertFrom-Json
}

function Invoke-TrustedDocsJson([string[]]$Arguments) {
  $script = Join-Path $PSScriptRoot "skybridge-trusted-docs-auto-merge.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments
  if ($LASTEXITCODE -ne 0) { throw "trusted-docs command failed." }
  ($raw | Out-String).Trim() | ConvertFrom-Json
}

function Assert-NoUnsafeGoal221G222CText {
  $root = Get-SkyBridgeRoot
  $paths = @(
    ".agent/tmp/boinc-v1-controlled-trial-221",
    ".agent/tmp/trusted-docs-auto-merge",
    "docs/boinc-v1-controlled-trial-221.md",
    "docs/dev/CONTROLLED_TRIAL_221_COMPLETION_REPORT.md",
    "docs/dev/POSTRELEASE_CONTROLLED_TRIAL_STATUS.md",
    "docs/dev/TRUSTED_DOCS_AUTO_MERGE_PREVIEW.md",
    "docs/dev/TRUSTED_DOCS_AUTO_MERGE_RISK_MODEL.md",
    "docs/dev/TRUSTED_DOCS_AUTO_MERGE_DISABLED_BY_DEFAULT.md"
  )
  foreach ($path in $paths) {
    $full = Join-Path $root $path
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $files = if (Test-Path -LiteralPath $full -PathType Container) { Get-ChildItem -LiteralPath $full -File -Recurse } else { @(Get-Item -LiteralPath $full) }
    foreach ($file in $files) {
      $text = Get-Content -Raw -LiteralPath $file.FullName
      if ($text -match 'token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true|raw_prompt(?!_persisted)|raw_transcript(?!_persisted)|raw_stdout(?!_persisted)|raw_stderr(?!_persisted)|raw_worker_log|raw_codex_transcript|raw_ci_log|authorization\s*[:=]\s*bearer|Bearer\s+[A-Za-z0-9_.-]{12,}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----') {
        throw "Unsafe marker found in $($file.FullName)"
      }
    }
  }
}

function Invoke-Goal221G222CSmoke([string]$Scenario) {
  Assert-NoUnsafeGoal221G222CText
  $root = Get-SkyBridgeRoot
  switch ($Scenario) {
    "finalizer-pr-merged" {
      $preview = Invoke-TrialJson @("-Command", "trial-finalizer-preview")
      if ($preview.task_pr_merged -ne $true -or $preview.codex_execution_count -ne 1 -or $preview.task_pr_count -ne 1) { throw "Finalizer preview unsafe." }
    }
    "finalizer-evidence-safe" {
      foreach ($path in @("trial-finalizer-evidence.json", "trial-finalizer-report.json")) {
        if (-not (Test-Path -LiteralPath (Join-Path $root ".agent/tmp/boinc-v1-controlled-trial-221/$path"))) { throw "Missing $path" }
      }
      $report = Get-Content -Raw -LiteralPath (Join-Path $root ".agent/tmp/boinc-v1-controlled-trial-221/trial-finalizer-report.json") | ConvertFrom-Json
      if ($report.final_state -ne "boinc_v1_controlled_trial_221_completed" -or $report.human_review_confirmed -ne $true) { throw "Finalizer report mismatch." }
    }
    "completed-state" {
      $report = Invoke-TrialJson @("-Command", "trial-finalizer-report")
      if ($report.final_state -ne "boinc_v1_controlled_trial_221_completed" -or $report.ready_for_goal_222 -ne $true) { throw "Controlled trial not completed." }
    }
    "blocks-rerun" {
      $script = Join-Path $PSScriptRoot "skybridge-boinc-v1-controlled-trial.ps1"
      $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command trial-finalizer-apply 2>&1
      if ($LASTEXITCODE -eq 0 -or (($raw | Out-String) -notmatch "already applied")) { throw "Duplicate finalizer apply was not blocked." }
    }
    "post-trial-readiness" {
      $report = Invoke-TrialJson @("-Command", "post-trial-readiness")
      if ($report.controlled_trial_221_completed -ne $true -or $report.no_next_execution_authorized -ne $true) { throw "Post-trial readiness unsafe." }
    }
    "trusted-policy-disabled" {
      $policy = Invoke-TrustedDocsJson @("-Command", "policy")
      if ($policy.trusted_docs_auto_merge_enabled -ne $false -or $policy.auto_merge_apply_enabled -ne $false) { throw "Trusted docs policy enabled." }
    }
    "trusted-gate-contract" {
      $gate = Invoke-TrustedDocsJson @("-Command", "gate", "-Fixture", "eligible-docs-only")
      if ($gate.schema -ne "skybridge.trusted_docs_auto_merge_gate.v1" -or $gate.auto_merge_allowed -ne $false -or $gate.platform_auto_merge_enabled -ne $false) { throw "Trusted docs gate unsafe." }
    }
    "trusted-eligible-disabled" {
      $decision = Invoke-TrustedDocsJson @("-Command", "decision", "-Fixture", "eligible-docs-only")
      if ($decision.decision -ne "eligible_docs_only_but_disabled" -or $decision.auto_merge_allowed -ne $false) { throw "Eligible fixture not disabled." }
    }
    "trusted-blocks-multiple-files" {
      $decision = Invoke-TrustedDocsJson @("-Command", "decision", "-Fixture", "multiple-files")
      if (@($decision.blockers) -notcontains "blocked_by_multiple_files") { throw "Multiple files not blocked." }
    }
    "trusted-blocks-deletions" {
      $decision = Invoke-TrustedDocsJson @("-Command", "decision", "-Fixture", "deletion")
      if (@($decision.blockers) -notcontains "blocked_by_deletions") { throw "Deletion not blocked." }
    }
    "trusted-blocks-disallowed-path" {
      $decision = Invoke-TrustedDocsJson @("-Command", "decision", "-Fixture", "disallowed-script")
      if (@($decision.blockers) -notcontains "blocked_by_disallowed_path") { throw "Disallowed path not blocked." }
    }
    "trusted-blocks-token-content" {
      $decision = Invoke-TrustedDocsJson @("-Command", "decision", "-Fixture", "token-content")
      if (@($decision.blockers) -notcontains "blocked_by_secret_scan") { throw "Token-looking content not blocked." }
    }
    "trusted-never-calls-merge" {
      $scriptText = Read-SkyBridgeFile "scripts/powershell/skybridge-trusted-docs-auto-merge.ps1"
      if ($scriptText -match 'gh\s+pr\s+merge|enablePullRequestAutoMerge|autoMergeRequest\s*=') { throw "Trusted docs gate contains merge-enabling call." }
    }
    "desktop-trusted-panel" {
      $desktop = Read-SkyBridgeFile "apps/desktop/src/main.tsx"
      Assert-Contains $desktop "TrustedDocsAutoMergePanel" "Desktop trusted docs panel missing."
      Assert-Contains $desktop "trusted_docs_auto_merge_enabled=false" "Desktop disabled status missing."
    }
    "web-trusted-panel" {
      $web = Read-SkyBridgeFile "apps/web/src/main.tsx"
      Assert-Contains $web "TrustedDocsAutoMergePanel" "Web trusted docs panel missing."
      Assert-Contains $web "Auto-merge disabled" "Web disabled status missing."
    }
    "trusted-token-false" {
      Assert-NoUnsafeGoal221G222CText
      $gate = Invoke-TrustedDocsJson @("-Command", "gate")
      if ($gate.token_printed -ne $false) { throw "Trusted docs token_printed must be false." }
    }
    default { throw "Unknown smoke scenario: $Scenario" }
  }
  [pscustomobject]@{
    ok = $true
    scenario = $Scenario
    trusted_docs_auto_merge_enabled = $false
    auto_merge_apply_enabled = $false
    token_printed = $false
  } | ConvertTo-Json -Compress
}
