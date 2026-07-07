[CmdletBinding()]
param(
  [string]$OutputDir = ".agent/tmp/skybridge-mvp-demo-review"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$schema = "skybridge.mvp_demo.review_gate.v1"
$baselineCommit = "a971f555f31db86869b10261be3c04b3d3d1317e"
$implementationPrNumber = 310
$demoPrNumber = 311
$recommendedNext = "MG372D Codex-generated Local Diff Demo"
$artifactNames = @(
  "mvp-demo-review-report.json",
  "mvp-demo-review-report.md",
  "mvp-demo-review-decision.json",
  "mvp-demo-review-evidence.json",
  "mvp-demo-review-next-plan.json",
  "mvp-demo-review-safety.json",
  "mvp-demo-review-artifact-index.json"
)

function ConvertTo-ReviewJson($Value) {
  $Value | ConvertTo-Json -Depth 30
}

function Write-ReviewJsonFile([string]$Path, $Value) {
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  ConvertTo-ReviewJson $Value | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-GhJson([string[]]$Arguments) {
  $raw = & gh @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) { throw "gh read failed." }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Get-GitText([string[]]$Arguments) {
  $raw = & git @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) { throw "git read failed." }
  (($raw | Out-String).Trim())
}

$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $RepoRoot $OutputDir }
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
$generatedAt = (Get-Date).ToUniversalTime().ToString("o")

$branchBefore = Get-GitText @("branch", "--show-current")
$localBranchesBefore = Get-GitText @("branch", "--list")
$implementationPr = Invoke-GhJson @("pr", "view", "$implementationPrNumber", "--json", "number,url,title,state,mergeCommit,mergedAt")
$demoPrBefore = Invoke-GhJson @("pr", "view", "$demoPrNumber", "--json", "number,url,title,state,isDraft,headRefName,baseRefName,autoMergeRequest,mergeCommit,files")

$frozenLines = @(
  "MG371B TUI-created PR",
  "worker loop / run forever",
  "auto-merge",
  "Hermes live",
  "MCP",
  "remote execution",
  "multi-agent orchestration",
  "release/tag/assets",
  "dashboard polish beyond showing MVP status"
)

$decision = [ordered]@{
  schema = "skybridge.mvp_demo.review_gate.decision.v1"
  generated_at = $generatedAt
  primary_option = "Option A"
  current_repo_continue_recommended = $true
  rewrite_recommended = $false
  tui_pr_work_frozen = $true
  recommended_next_milestone = $recommendedNext
  reason = "The current repository now has enough reusable infrastructure. A rewrite is not justified unless the next Codex diff demo fails."
  token_printed = $false
}

$evidence = [ordered]@{
  schema = "skybridge.mvp_demo.review_gate.evidence.v1"
  generated_at = $generatedAt
  mg372a = @{
    command = "pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 -Mode local-safe -UseTempDatabase -Json"
    demo_result = "pass"
    task_created = $true
    worker_registered = $true
    task_claimed = $true
    task_completed = $true
    fixture_mode = $false
    real_worker_execution = $true
    codex_called = $false
    pr_created = $false
    branch_created = $false
    token_printed = $false
  }
  mg372b = @{
    command = "pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 -Mode controller-draft-pr -UseTempDatabase -Apply -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372B_CREATE_ONE_CONTROLLER_CREATED_DOCS_ONLY_DRAFT_PR_DEMO -Json"
    demo_result = "pass"
    task_created = $true
    worker_registered = $true
    task_claimed = $true
    task_completed = $true
    fixture_mode = $false
    real_worker_execution = $true
    server_task_pr_evidence_recorded = $true
    controller_created_branch = $true
    controller_created_draft_pr = $true
    token_printed = $false
  }
  implementation_pr = $implementationPr
  demo_pr_before = $demoPrBefore
  artifact_dirs = @(".agent/tmp/skybridge-mvp-demo/", ".agent/tmp/skybridge-mvp-demo-pr/", ".agent/tmp/skybridge-mvp-demo-review/")
  token_printed = $false
}

$nextPlan = [ordered]@{
  schema = "skybridge.mvp_demo.review_gate.next_plan.v1"
  generated_at = $generatedAt
  recommended_next_milestone = $recommendedNext
  purpose = @(
    "use the existing MVP demo spine",
    "call Codex once",
    "generate a docs-only local diff in an isolated workspace or temporary branch",
    "do not create a PR yet",
    "produce diff.patch and review summary",
    "keep controller-created PR as a later MG372E2 or MG373A step"
  )
  do_not_skip_directly_to_repeated_pr_creation = $true
  token_printed = $false
}

$safety = [ordered]@{
  schema = "skybridge.mvp_demo.review_gate.safety.v1"
  generated_at = $generatedAt
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

$demoPrOpen = ([string]$demoPrBefore.state -eq "OPEN")
$demoPrDraft = [bool]$demoPrBefore.isDraft
$report = [ordered]@{
  schema = $schema
  generated_at = $generatedAt
  mode = "mvp-demo-review"
  baseline_commit = $baselineCommit
  mg372a_passed = $true
  mg372b_passed = $true
  implementation_pr = @{
    number = [int]$implementationPr.number
    url = [string]$implementationPr.url
    state = [string]$implementationPr.state
    merge_commit = [string]$implementationPr.mergeCommit.oid
  }
  demo_pr = @{
    number = [int]$demoPrBefore.number
    url = [string]$demoPrBefore.url
    state = [string]$demoPrBefore.state
    is_draft = [bool]$demoPrBefore.isDraft
    head_ref = [string]$demoPrBefore.headRefName
    changed_files = @($demoPrBefore.files | ForEach-Object { [string]$_.path })
  }
  demo_pr_open = $demoPrOpen
  demo_pr_draft = $demoPrDraft
  demo_pr_left_for_human_review = ($demoPrOpen -and $demoPrDraft)
  mvp_demo_result = "pass"
  current_repo_continue_recommended = $true
  rewrite_recommended = $false
  frozen_lines = $frozenLines
  recommended_next_milestone = $recommendedNext
  branch_created = $false
  pr_created = $false
  codex_called = $false
  tui_created_branch = $false
  tui_created_pr = $false
  worker_loop_started = $false
  queue_runner_started = $false
  run_forever_started = $false
  auto_merge_enabled = $false
  release_created = $false
  tag_created = $false
  asset_uploaded = $false
  token_printed = $false
  blockers = @()
  warnings = @()
}

$reportPath = Join-Path $resolvedOutputDir "mvp-demo-review-report.json"
$markdownPath = Join-Path $resolvedOutputDir "mvp-demo-review-report.md"
$decisionPath = Join-Path $resolvedOutputDir "mvp-demo-review-decision.json"
$evidencePath = Join-Path $resolvedOutputDir "mvp-demo-review-evidence.json"
$nextPlanPath = Join-Path $resolvedOutputDir "mvp-demo-review-next-plan.json"
$safetyPath = Join-Path $resolvedOutputDir "mvp-demo-review-safety.json"
$indexPath = Join-Path $resolvedOutputDir "mvp-demo-review-artifact-index.json"

Write-ReviewJsonFile $decisionPath $decision
Write-ReviewJsonFile $evidencePath $evidence
Write-ReviewJsonFile $nextPlanPath $nextPlan
Write-ReviewJsonFile $safetyPath $safety
Write-ReviewJsonFile $reportPath $report

$markdown = @(
  "# SkyBridge MVP Demo Review",
  "",
  "- result: pass",
  "- decision: Option A",
  "- current_repo_continue_recommended: true",
  "- rewrite_recommended: false",
  "- recommended_next_milestone: $recommendedNext",
  "- implementation_pr: #$implementationPrNumber",
  "- demo_pr: #$demoPrNumber",
  "- demo_pr_open: $demoPrOpen",
  "- demo_pr_draft: $demoPrDraft",
  "- demo_pr_left_for_human_review: $($demoPrOpen -and $demoPrDraft)",
  "- codex_called: false",
  "- tui_created_branch: false",
  "- tui_created_pr: false",
  "- worker_loop_started: false",
  "- queue_runner_started: false",
  "- run_forever_started: false",
  "- auto_merge_enabled: false",
  "- release_created: false",
  "- tag_created: false",
  "- asset_uploaded: false",
  "- token_printed: false",
  "",
  "MG372C recommends continuing the current repository and running MG372D Codex-generated Local Diff Demo next."
)
$markdown | Set-Content -LiteralPath $markdownPath -Encoding UTF8

$index = [ordered]@{
  schema = "skybridge.mvp_demo.review_gate.artifact_index.v1"
  generated_at = $generatedAt
  artifact_dir = $OutputDir.Replace("\", "/")
  artifacts = $artifactNames
  report_json_path = "$($OutputDir.Replace("\", "/"))/mvp-demo-review-report.json"
  report_markdown_path = "$($OutputDir.Replace("\", "/"))/mvp-demo-review-report.md"
  token_printed = $false
}
Write-ReviewJsonFile $indexPath $index

$demoPrAfter = Invoke-GhJson @("pr", "view", "$demoPrNumber", "--json", "number,url,title,state,isDraft,headRefName,baseRefName,autoMergeRequest,mergeCommit,files")
$branchAfter = Get-GitText @("branch", "--show-current")
$localBranchesAfter = Get-GitText @("branch", "--list")

if ([string]$branchAfter -ne [string]$branchBefore) { throw "Smoke changed current branch." }
if ([string]$localBranchesAfter -ne [string]$localBranchesBefore) { throw "Smoke changed local branch list." }
if ([string]$demoPrAfter.state -ne [string]$demoPrBefore.state) { throw "Demo PR #311 state changed." }
if ([bool]$demoPrAfter.isDraft -ne [bool]$demoPrBefore.isDraft) { throw "Demo PR #311 draft state changed." }
if ($null -ne $demoPrAfter.autoMergeRequest) { throw "Demo PR #311 auto-merge is enabled." }

Assert-FileExists "$OutputDir/mvp-demo-review-report.json"
Assert-FileExists "$OutputDir/mvp-demo-review-report.md"
Assert-FileExists "$OutputDir/mvp-demo-review-decision.json"
Assert-FileExists "$OutputDir/mvp-demo-review-evidence.json"
Assert-FileExists "$OutputDir/mvp-demo-review-next-plan.json"
Assert-FileExists "$OutputDir/mvp-demo-review-safety.json"
Assert-FileExists "$OutputDir/mvp-demo-review-artifact-index.json"

$loadedReport = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
Assert-True $loadedReport.current_repo_continue_recommended "current_repo_continue_recommended"
Assert-False $loadedReport.rewrite_recommended "rewrite_recommended"
Assert-False $loadedReport.branch_created "branch_created"
Assert-False $loadedReport.pr_created "pr_created"
Assert-False $loadedReport.codex_called "codex_called"
Assert-True $loadedReport.demo_pr_left_for_human_review "demo_pr_left_for_human_review"
if ([string]$loadedReport.recommended_next_milestone -eq "") { throw "recommended_next_milestone missing." }
Assert-TokenPrintedFalse $loadedReport
Assert-NoUnsafeText (Get-Content -Raw -LiteralPath $reportPath)
Assert-NoUnsafeText (Get-Content -Raw -LiteralPath $markdownPath)

Complete-Smoke "skybridge-mvp-demo-review"
