[CmdletBinding()]
param(
  [ValidateSet("status", "audit", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/stage-s1-1-close",
  [string]$ExpectedCommit = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.stage_s1_1_close.v1"

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function Resolve-RepoPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Convert-ToSafePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $value = $Path.Replace("\", "/")
  $repo = $RepoRoot.Replace("\", "/").TrimEnd("/")
  if ($value.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $value.Substring($repo.Length).TrimStart("/")
  }
  if ($value -match "^[A-Za-z]:/") { return "%PATH%/" + (Split-Path -Leaf $value) }
  $value
}

function Resolve-OutputRoot {
  $fullTarget = Resolve-RepoPath $OutputDir
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/stage-s1-1-close"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/stage-s1-1-close."
  }
  $fullTarget
}

function Get-GitText([string[]]$GitArgs) {
  $raw = & git -C $RepoRoot @GitArgs 2>$null
  if ($LASTEXITCODE -ne 0) { return "" }
  (($raw | Out-String).Trim())
}

function Test-RelativeFile([string]$RelativePath) {
  Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath) -PathType Leaf
}

function Get-PackageScriptNames {
  $packagePath = Join-Path $RepoRoot "package.json"
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return @() }
  $package = Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json
  @($package.scripts.PSObject.Properties | ForEach-Object { $_.Name })
}

function Resolve-MainCommit {
  $originMain = Get-GitText @("rev-parse", "origin/main")
  $localMain = Get-GitText @("rev-parse", "main")
  $head = Get-GitText @("rev-parse", "HEAD")
  if (-not [string]::IsNullOrWhiteSpace($originMain)) { return $originMain }
  if (-not [string]::IsNullOrWhiteSpace($localMain)) { return $localMain }
  $head
}

function Resolve-CloudApiBase([ref]$Warnings) {
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_API_BASE)) { return [string]$env:SKYBRIDGE_API_BASE }
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_PUBLIC_API_BASE)) { return [string]$env:SKYBRIDGE_PUBLIC_API_BASE }

  $gh = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $gh) {
    try {
      $raw = & gh variable get SKYBRIDGE_PUBLIC_API_BASE --repo JerrySkywalker/skybridge-agent-hub 2>$null
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($raw)) {
        return (($raw | Out-String).Trim())
      }
    } catch {
      Add-Finding $Warnings "cloud_api_base_variable_unavailable"
    }
  }

  Add-Finding $Warnings "cloud_api_base_not_configured"
  ""
}

function Invoke-SafeJsonGet([string]$Uri) {
  Invoke-RestMethod -Method GET -Uri $Uri -TimeoutSec 20
}

function Get-CloudState([ref]$Warnings) {
  $apiBase = Resolve-CloudApiBase $Warnings
  $health = [pscustomobject]@{ ok = $false; status = "not_configured" }
  $version = [pscustomobject]@{
    ok = $false
    commit_sha = ""
    image_ref = ""
    image_tag = ""
    route_set_version = ""
  }
  $parity = [pscustomobject]@{
    ok = $false
    status = "not_configured"
    missing_routes = @()
  }

  if ([string]::IsNullOrWhiteSpace($apiBase)) {
    return [pscustomobject]@{
      api_base = "not_configured"
      health = $health
      version = $version
      parity = $parity
    }
  }

  try {
    $rawHealth = Invoke-SafeJsonGet ($apiBase.TrimEnd("/") + "/v1/health")
    $health = [pscustomobject]@{
      ok = $true
      status = if ($rawHealth.status) { [string]$rawHealth.status } else { "ok" }
    }
  } catch {
    Add-Finding $Warnings "cloud_health_unavailable"
    $health = [pscustomobject]@{ ok = $false; status = "unavailable" }
  }

  try {
    $rawVersion = Invoke-SafeJsonGet ($apiBase.TrimEnd("/") + "/v1/version")
    $version = [pscustomobject]@{
      ok = $true
      commit_sha = if ($rawVersion.commit_sha) { [string]$rawVersion.commit_sha } else { "" }
      image_ref = if ($rawVersion.image_ref) { [string]$rawVersion.image_ref } else { "" }
      image_tag = if ($rawVersion.image_tag) { [string]$rawVersion.image_tag } else { "" }
      route_set_version = if ($rawVersion.route_set_version) { [string]$rawVersion.route_set_version } else { "" }
    }
  } catch {
    Add-Finding $Warnings "cloud_version_unavailable"
  }

  try {
    $rawParity = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1") -ApiBase $apiBase -Json 2>$null
    if ($LASTEXITCODE -eq 0) {
      $parsed = (($rawParity | Out-String).Trim() | ConvertFrom-Json)
      $parity = [pscustomobject]@{
        ok = [bool]$parsed.ok
        status = if ($parsed.status) { [string]$parsed.status } else { "unknown" }
        missing_routes = @($parsed.missing_routes)
      }
    } else {
      Add-Finding $Warnings "cloud_parity_check_failed"
      $parity = [pscustomobject]@{ ok = $false; status = "failed"; missing_routes = @() }
    }
  } catch {
    Add-Finding $Warnings "cloud_parity_unavailable"
    $parity = [pscustomobject]@{ ok = $false; status = "unavailable"; missing_routes = @() }
  }

  [pscustomobject]@{
    api_base = "configured"
    health = $health
    version = $version
    parity = $parity
  }
}

function Get-OpenPrSummary([ref]$Warnings) {
  $gh = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $gh) {
    Add-Finding $Warnings "gh_unavailable_open_pr_summary_skipped"
    return [pscustomobject]@{
      open_pr_count = 0
      mg351_mg366c_open_implementation_pr_count = 0
      prs = @()
    }
  }

  try {
    $raw = & gh pr list --repo JerrySkywalker/skybridge-agent-hub --state open --limit 100 --json number,title,headRefName,isDraft,url 2>$null
    if ($LASTEXITCODE -ne 0) {
      Add-Finding $Warnings "gh_pr_list_failed"
      return [pscustomobject]@{ open_pr_count = 0; mg351_mg366c_open_implementation_pr_count = 0; prs = @() }
    }
    $items = @((($raw | Out-String).Trim() | ConvertFrom-Json))
    $mgPattern = "(?i)(MG35[1-9]|MG36[0-6][A-C]?|mega-35[1-9]|mega-36[0-6])"
    $mgItems = @($items | Where-Object { $_.title -match $mgPattern -or $_.headRefName -match $mgPattern })
    return [pscustomObject]@{
      open_pr_count = @($items).Count
      mg351_mg366c_open_implementation_pr_count = @($mgItems).Count
      prs = @($items | ForEach-Object {
        [pscustomobject]@{
          number = $_.number
          title = $_.title
          head = $_.headRefName
          draft = [bool]$_.isDraft
        }
      })
    }
  } catch {
    Add-Finding $Warnings "gh_pr_list_unavailable"
    [pscustomobject]@{ open_pr_count = 0; mg351_mg366c_open_implementation_pr_count = 0; prs = @() }
  }
}

function New-StageCapabilities {
  @(
    [pscustomobject]@{ id = "provider_inventory"; name = "Provider inventory"; status = "complete"; evidence = "docs/orchestrator/TOOL_PROVIDER_CONTRACT.md" }
    [pscustomobject]@{ id = "single_goal_loop"; name = "Single-goal loop"; status = "complete"; evidence = "docs/orchestrator/SINGLE_GOAL_LOOP_CONTROLLER.md" }
    [pscustomobject]@{ id = "multi_step_loop"; name = "Multi-step loop"; status = "complete"; evidence = "docs/orchestrator/MULTI_STEP_STATIC_GOAL_LOOP.md" }
    [pscustomobject]@{ id = "local_goal_generation"; name = "Local goal generation"; status = "complete"; evidence = "docs/orchestrator/LOCAL_CODEX_GOAL_GENERATOR.md" }
    [pscustomobject]@{ id = "goal_review_append"; name = "Goal review/append"; status = "complete"; evidence = "docs/orchestrator/GOAL_APPEND_REVIEW_IMPORT.md" }
    [pscustomobject]@{ id = "bounded_loop"; name = "Bounded loop"; status = "complete"; evidence = "docs/orchestrator/BOUNDED_GOAL_BUDGET_LOOP.md" }
    [pscustomobject]@{ id = "managed_dev_pr_pilot"; name = "Managed-dev PR pilot"; status = "complete"; evidence = "docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT.md" }
    [pscustomobject]@{ id = "controller_native_pr_creation"; name = "Controller-native PR creation"; status = "complete"; evidence = "docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT_MG360.md" }
    [pscustomobject]@{ id = "campaign_driven_managed_dev_e2e"; name = "Campaign-driven managed-dev E2E"; status = "complete"; evidence = "docs/orchestrator/MANAGED_DEV_CAMPAIGN_E2E.md" }
    [pscustomobject]@{ id = "warning_inventory"; name = "Warning inventory"; status = "complete"; evidence = "docs/dev/WARNING_INVENTORY.md" }
    [pscustomobject]@{ id = "actions_node_runtime_hygiene"; name = "GitHub Actions Node runtime hygiene"; status = "complete"; evidence = "docs/dev/ACTIONS_NODE_RUNTIME_HYGIENE.md" }
    [pscustomobject]@{ id = "vite_chunk_warning_analysis"; name = "Vite chunk warning analysis"; status = "complete"; evidence = "docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md" }
    [pscustomobject]@{ id = "hermes_planner_provider_fixture"; name = "Hermes planner provider fixture baseline"; status = "complete"; evidence = "docs/orchestrator/HERMES_PLANNER_PROVIDER.md" }
  )
}

function Get-RequiredDocs {
  @(
    "docs/release/STAGE_S1_1_CLOSE.md",
    "docs/release/MANAGED_DEV_E2E_HANDOFF.md",
    "docs/release/MANAGED_DEV_E2E_FREEZE_CHECKLIST.md",
    "docs/dev/PROGRESS.md",
    "docs/dev/WARNING_INVENTORY.md",
    "docs/dev/ACTIONS_NODE_RUNTIME_HYGIENE.md",
    "docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md",
    "docs/orchestrator/HERMES_PLANNER_PROVIDER.md"
  )
}

function Get-RequiredScripts {
  @(
    "scripts/powershell/skybridge-stage-s1-1-close.ps1",
    "scripts/powershell/skybridge-managed-dev-e2e-handoff.ps1",
    "scripts/powershell/skybridge-warning-inventory.ps1",
    "scripts/powershell/skybridge-actions-node-runtime-hygiene.ps1",
    "scripts/powershell/skybridge-vite-chunk-warning-analysis.ps1",
    "scripts/powershell/skybridge-hermes-planner-provider.ps1"
  )
}

function Get-RequiredSmokeFiles {
  @(
    "scripts/powershell/smoke-stage-s1-1-close-status.ps1",
    "scripts/powershell/smoke-stage-s1-1-close-audit.ps1",
    "scripts/powershell/smoke-stage-s1-1-close-doc-present.ps1",
    "scripts/powershell/smoke-stage-s1-1-close-no-mutation.ps1"
  )
}

function Get-RequiredSmokeScripts {
  @(
    "smoke:stage-s1-1-close-status",
    "smoke:stage-s1-1-close-audit",
    "smoke:stage-s1-1-close-doc-present",
    "smoke:stage-s1-1-close-no-mutation"
  )
}

function New-Report {
  $warnings = @()
  $blockers = @()
  $localMain = Get-GitText @("rev-parse", "main")
  $originMain = Get-GitText @("rev-parse", "origin/main")
  $currentHead = Get-GitText @("rev-parse", "HEAD")
  $currentCommit = Resolve-MainCommit
  $expected = if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit)) { $ExpectedCommit } else { $currentCommit }
  $mainAligned = (-not [string]::IsNullOrWhiteSpace($localMain) -and $localMain -eq $originMain)
  $worktreeClean = [string]::IsNullOrWhiteSpace((Get-GitText @("status", "--porcelain=v1")))
  if (-not $mainAligned) { Add-Finding ([ref]$blockers) "main_not_aligned_with_origin_main" }
  if (-not $worktreeClean) { Add-Finding ([ref]$warnings) "worktree_has_changes" }
  if (-not [string]::IsNullOrWhiteSpace($expected) -and $currentCommit -ne $expected) {
    Add-Finding ([ref]$blockers) "current_commit_does_not_match_expected_commit"
  }

  $cloud = Get-CloudState ([ref]$warnings)
  if (-not $cloud.health.ok) { Add-Finding ([ref]$blockers) "cloud_health_not_ok" }
  if (-not $cloud.version.ok) { Add-Finding ([ref]$blockers) "cloud_version_unavailable" }
  if ($cloud.version.ok -and $cloud.version.commit_sha -ne $currentCommit) {
    Add-Finding ([ref]$blockers) "cloud_version_does_not_match_current_commit"
  }
  if (-not $cloud.parity.ok) { Add-Finding ([ref]$blockers) "cloud_parity_not_ok" }

  $openPrs = Get-OpenPrSummary ([ref]$warnings)
  if ($openPrs.mg351_mg366c_open_implementation_pr_count -gt 0) {
    Add-Finding ([ref]$blockers) "open_mg351_mg366c_implementation_prs"
  }

  $requiredDocs = Get-RequiredDocs
  $requiredScripts = Get-RequiredScripts
  $requiredSmokeFiles = Get-RequiredSmokeFiles
  $requiredSmokeScripts = Get-RequiredSmokeScripts
  $packageScripts = Get-PackageScriptNames
  $missingDocs = @($requiredDocs | Where-Object { -not (Test-RelativeFile $_) })
  $missingScripts = @($requiredScripts | Where-Object { -not (Test-RelativeFile $_) })
  $missingSmokeFiles = @($requiredSmokeFiles | Where-Object { -not (Test-RelativeFile $_) })
  $missingSmokeScripts = @($requiredSmokeScripts | Where-Object { $packageScripts -notcontains $_ })

  foreach ($item in $missingDocs) { Add-Finding ([ref]$blockers) "missing_doc:$item" }
  foreach ($item in $missingScripts) { Add-Finding ([ref]$blockers) "missing_script:$item" }
  foreach ($item in $missingSmokeFiles) { Add-Finding ([ref]$blockers) "missing_smoke_file:$item" }
  foreach ($item in $missingSmokeScripts) { Add-Finding ([ref]$blockers) "missing_package_smoke:$item" }

  [pscustomobject]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    current_commit = $currentCommit
    expected_commit = $expected
    local_main_commit = $localMain
    origin_main_commit = $originMain
    main_aligned = $mainAligned
    current_head = $currentHead
    worktree_clean = $worktreeClean
    cloud_version = $cloud.version
    cloud_health = $cloud.health
    cloud_parity = $cloud.parity
    open_prs_summary = $openPrs
    stage_capabilities = @(New-StageCapabilities)
    required_docs_present = ($missingDocs.Count -eq 0)
    required_scripts_present = ($missingScripts.Count -eq 0)
    required_smokes_present = ($missingSmokeFiles.Count -eq 0 -and $missingSmokeScripts.Count -eq 0)
    required_docs = @($requiredDocs)
    required_scripts = @($requiredScripts)
    required_smokes = @($requiredSmokeScripts)
    tracked_warnings = @(
      [pscustomobject]@{
        id = "vite_chunk_size_warning"
        status = "non_failing_tracked"
        evidence = "docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md"
      }
    )
    resolved_warnings = @(
      [pscustomobject]@{
        id = "github_actions_node20_deprecation_annotation"
        status = "resolved"
        evidence = "docs/dev/ACTIONS_NODE_RUNTIME_HYGIENE.md"
      }
    )
    next_stage_options = @(
      "MG367C Hermes Candidate Review/Append Gate",
      "MG366D Worker Service Install/Daemonization",
      "MG367A Vite Chunk Remediation",
      "MCP Tool Provider Stub"
    )
    auto_merge_enabled = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    worker_loop_started = $false
    queue_runner_started = $false
    task_created = $false
    task_claimed = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_live_called = $false
    mcp_run_called = $false
    raw_prompt_persisted = $false
    raw_response_persisted = $false
    raw_logs_persisted = $false
    secrets_persisted = $false
    token_printed = $false
    blockers = @($blockers)
    warnings = @($warnings)
  }
}

function Write-Reports($Report) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "stage-s1-1-close.json"
  $mdPath = Join-Path $root "stage-s1-1-close.md"
  $Report | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Report | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $lines = @(
    "# Stage S1.1 Close Audit",
    "",
    "- schema: $($Report.schema)",
    "- current_commit: $($Report.current_commit)",
    "- local_main_commit: $($Report.local_main_commit)",
    "- origin_main_commit: $($Report.origin_main_commit)",
    "- main_aligned: $($Report.main_aligned)",
    "- cloud_health_ok: $($Report.cloud_health.ok)",
    "- cloud_version_commit: $($Report.cloud_version.commit_sha)",
    "- cloud_image_ref: $($Report.cloud_version.image_ref)",
    "- cloud_parity: $($Report.cloud_parity.status)",
    "- open_pr_count: $($Report.open_prs_summary.open_pr_count)",
    "- mg351_mg366c_open_implementation_pr_count: $($Report.open_prs_summary.mg351_mg366c_open_implementation_pr_count)",
    "- required_docs_present: $($Report.required_docs_present)",
    "- required_scripts_present: $($Report.required_scripts_present)",
    "- required_smokes_present: $($Report.required_smokes_present)",
    "- tracked_warnings: $(@($Report.tracked_warnings).Count)",
    "- resolved_warnings: $(@($Report.resolved_warnings).Count)",
    "- blockers: $(@($Report.blockers).Count)",
    "- warnings: $(@($Report.warnings).Count)",
    "- auto_merge_enabled=false",
    "- release_created=false",
    "- tag_created=false",
    "- asset_uploaded=false",
    "- worker_loop_started=false",
    "- queue_runner_started=false",
    "- task_created=false",
    "- task_claimed=false",
    "- hermes_live_called=false",
    "- mcp_run_called=false",
    "- token_printed=false"
  )
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

$report = New-Report

if ($Command -eq "safe-summary") {
  $report = [pscustomobject]@{
    schema = $Schema
    current_commit = $report.current_commit
    main_aligned = $report.main_aligned
    cloud_health_ok = $report.cloud_health.ok
    cloud_version_commit = $report.cloud_version.commit_sha
    cloud_parity_status = $report.cloud_parity.status
    open_pr_count = $report.open_prs_summary.open_pr_count
    required_docs_present = $report.required_docs_present
    required_scripts_present = $report.required_scripts_present
    required_smokes_present = $report.required_smokes_present
    auto_merge_enabled = $false
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    worker_loop_started = $false
    queue_runner_started = $false
    task_created = $false
    task_claimed = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_live_called = $false
    mcp_run_called = $false
    token_printed = $false
    blockers = @($report.blockers)
    warnings = @($report.warnings)
  }
}

if ($WriteReport -or $Command -eq "report") {
  Write-Reports $report
}

if ($Json) {
  $report | ConvertTo-Json -Depth 30
} elseif ($Command -eq "safe-summary") {
  Write-Host "Stage S1.1 close: main_aligned=$($report.main_aligned) cloud_parity=$($report.cloud_parity_status) token_printed=false"
} else {
  Write-Host "Stage S1.1 close audit"
  Write-Host "- current_commit: $($report.current_commit)"
  Write-Host "- main_aligned: $($report.main_aligned)"
  Write-Host "- cloud_health_ok: $($report.cloud_health.ok)"
  Write-Host "- cloud_version_commit: $($report.cloud_version.commit_sha)"
  Write-Host "- cloud_parity: $($report.cloud_parity.status)"
  Write-Host "- open_pr_count: $($report.open_prs_summary.open_pr_count)"
  Write-Host "- required_docs_present: $($report.required_docs_present)"
  Write-Host "- required_scripts_present: $($report.required_scripts_present)"
  Write-Host "- required_smokes_present: $($report.required_smokes_present)"
  Write-Host "- token_printed=false"
}

if (@($report.blockers).Count -gt 0) {
  exit 1
}
