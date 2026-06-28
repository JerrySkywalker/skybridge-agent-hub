[CmdletBinding()]
param(
  [ValidateSet("status", "audit", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/managed-dev-e2e-handoff",
  [string]$ExpectedCommit = "961b492fabdcc7a737043e83d906d6c8d3f4bf38",
  [string]$ExpectedCloudImage = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-961b492fabdcc7a737043e83d906d6c8d3f4bf38"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.managed_dev_e2e_handoff.v1"

Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.ApiBase.psm1") -Force

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
  if ($value -match "^[A-Za-z]:/") {
    return "%PATH%/" + (Split-Path -Leaf $value)
  }
  $value
}

function Resolve-OutputRoot {
  $fullTarget = Resolve-RepoPath $OutputDir
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/managed-dev-e2e-handoff"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/managed-dev-e2e-handoff."
  }
  $fullTarget
}

function Test-RelativeFile([string]$RelativePath) {
  Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath) -PathType Leaf
}

function Get-GitText([string[]]$GitArgs) {
  $raw = & git @GitArgs 2>$null
  if ($LASTEXITCODE -ne 0) { return "" }
  (($raw | Out-String).Trim())
}

function Get-PackageScriptNames {
  $packagePath = Join-Path $RepoRoot "package.json"
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return @() }
  $package = Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json
  @($package.scripts.PSObject.Properties | ForEach-Object { $_.Name })
}

function New-SafetyFlags {
  [pscustomobject]@{
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    auto_merge_enabled = $false
    worker_loop_started = $false
    queue_runner_started = $false
    task_created = $false
    task_claimed = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Get-CapabilityMatrix {
  @(
    [pscustomobject]@{
      milestone = "M1"
      name = "Tool Provider Inventory"
      status = "complete"
      manual_script = "scripts/powershell/manual-tool-provider-check.ps1"
      evidence_summary = "Direct provider inventory exists; Codex and MATLAB can be detected; Hermes is optional; MCP remains future."
    }
    [pscustomobject]@{
      milestone = "M2"
      name = "Single Goal Loop"
      status = "complete"
      manual_script = "scripts/powershell/manual-single-goal-loop-test.ps1"
      evidence_summary = "Fixture passed and the live safe-local-smoke path passed after heartbeat apply."
    }
    [pscustomobject]@{
      milestone = "M3"
      name = "Static Multi-Step Campaign"
      status = "complete"
      manual_script = "scripts/powershell/manual-multi-goal-loop-test.ps1"
      evidence_summary = "Fixture completed safe-local-smoke, MATLAB golden and Codex report steps with evidence."
    }
    [pscustomobject]@{
      milestone = "M4"
      name = "Local Codex Goal Markdown Generator"
      status = "complete"
      manual_script = "scripts/powershell/manual-local-goal-generate-test.ps1"
      evidence_summary = "Fixture and local Codex generate-one passed; generated candidate validation held before import."
    }
    [pscustomobject]@{
      milestone = "M5"
      name = "Goal Append Review/Import"
      status = "complete"
      manual_script = "scripts/powershell/manual-goal-append-review-test.ps1"
      evidence_summary = "Generated goal review, approve and metadata append passed without execution."
    }
    [pscustomobject]@{
      milestone = "M6"
      name = "Bounded Goal Budget Loop"
      status = "complete"
      manual_script = "scripts/powershell/manual-bounded-goal-loop-test.ps1"
      evidence_summary = "One-action policy proved ready-step, reviewed append, proposed generation and budget-exhausted hold cases."
    }
    [pscustomobject]@{
      milestone = "M7"
      name = "Managed Development PR Pilot"
      status = "complete"
      manual_script = "scripts/powershell/manual-managed-dev-pr-pilot.ps1"
      evidence_summary = "Controller-native Git/GH path created a draft PR and observed CI with human review hold."
    }
    [pscustomobject]@{
      milestone = "M8"
      name = "Campaign-Driven Managed Dev E2E"
      status = "complete"
      manual_script = "scripts/powershell/manual-managed-dev-campaign-test.ps1"
      evidence_summary = "Reviewed goal to campaign step to bounded action to controller-native draft PR to merge gate was proven."
    }
  )
}

function Get-RequiredDocs {
  @(
    "docs/release/MANAGED_DEV_E2E_HANDOFF.md",
    "docs/release/MANAGED_DEV_E2E_FREEZE_CHECKLIST.md",
    "docs/orchestrator/TOOL_PROVIDER_CONTRACT.md",
    "docs/orchestrator/SINGLE_GOAL_LOOP_CONTROLLER.md",
    "docs/orchestrator/MULTI_STEP_STATIC_GOAL_LOOP.md",
    "docs/orchestrator/LOCAL_CODEX_GOAL_GENERATOR.md",
    "docs/orchestrator/GOAL_APPEND_REVIEW_IMPORT.md",
    "docs/orchestrator/BOUNDED_GOAL_BUDGET_LOOP.md",
    "docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT.md",
    "docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT_MG360.md",
    "docs/orchestrator/MANAGED_DEV_CAMPAIGN_E2E.md",
    "docs/orchestrator/CAMPAIGN_DRIVEN_MANAGED_DEV_MG362.md"
  )
}

function Get-RequiredScripts {
  @(
    "scripts/powershell/skybridge-managed-dev-e2e-handoff.ps1",
    "scripts/powershell/skybridge-tool-provider.ps1",
    "scripts/powershell/manual-tool-provider-check.ps1",
    "scripts/powershell/skybridge-goal-loop.ps1",
    "scripts/powershell/manual-single-goal-loop-test.ps1",
    "scripts/powershell/skybridge-multi-goal-loop.ps1",
    "scripts/powershell/manual-multi-goal-loop-test.ps1",
    "scripts/powershell/skybridge-local-goal-generator.ps1",
    "scripts/powershell/manual-local-goal-generate-test.ps1",
    "scripts/powershell/skybridge-goal-append.ps1",
    "scripts/powershell/manual-goal-append-review-test.ps1",
    "scripts/powershell/skybridge-bounded-goal-loop.ps1",
    "scripts/powershell/manual-bounded-goal-loop-test.ps1",
    "scripts/powershell/skybridge-managed-dev-pilot.ps1",
    "scripts/powershell/manual-managed-dev-pr-pilot.ps1",
    "scripts/powershell/skybridge-managed-dev-campaign.ps1",
    "scripts/powershell/manual-managed-dev-campaign-test.ps1"
  )
}

function Get-RequiredSmokeScripts {
  @(
    "smoke:managed-dev-e2e-handoff-status",
    "smoke:managed-dev-e2e-handoff-audit",
    "smoke:managed-dev-e2e-freeze-checklist",
    "smoke:managed-dev-e2e-required-artifacts",
    "smoke:managed-dev-e2e-no-mutation",
    "smoke:manual-managed-dev-e2e-handoff-fixture"
  )
}

function Read-ConfigValue {
  param([string]$Path, [string[]]$Keys)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
  $text = Get-Content -Raw -LiteralPath $Path
  foreach ($key in $Keys) {
    $pattern = '(?m)^\s*(?:\$env:)?' + [regex]::Escape($key) + '\s*=\s*[''"]?([^''"`]+)'
    $match = [regex]::Match($text, $pattern)
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
  }
  ""
}

function Resolve-HandoffApiBase {
  $apiBase = Resolve-SkybridgeApiBase -ApiBase "" -ParameterWasBound $false
  if (-not (Test-SkybridgeApiBaseInvalid -ApiBase $apiBase)) { return $apiBase }
  $homeConfig = Join-Path $HOME ".skybridge\skybridge.env.ps1"
  $fromFile = Read-ConfigValue -Path $homeConfig -Keys @("SKYBRIDGE_API_BASE", "SKYBRIDGE_REMOTE_API_BASE")
  if (-not [string]::IsNullOrWhiteSpace($fromFile)) { return $fromFile }
  $apiBase
}

function Get-CloudStatus([ref]$Warnings) {
  $result = [ordered]@{
    health = "not_configured"
    version = "not_configured"
    parity = "not_configured"
  }

  $apiBase = Resolve-HandoffApiBase
  if (Test-SkybridgeApiBaseInvalid -ApiBase $apiBase) {
    Add-Finding $Warnings "cloud_api_base_not_configured"
    return [pscustomobject]$result
  }

  try {
    $health = Invoke-RestMethod -Uri ($apiBase.TrimEnd("/") + "/v1/health") -Method GET -TimeoutSec 15
    if ($health.status) { $result.health = [string]$health.status } else { $result.health = "ok" }
  } catch {
    $result.health = "unavailable"
    Add-Finding $Warnings ("cloud_health_unavailable:" + (ConvertTo-SkybridgeSafeText -Text $_.Exception.Message -MaxLength 120))
  }

  try {
    $version = Invoke-RestMethod -Uri ($apiBase.TrimEnd("/") + "/v1/version") -Method GET -TimeoutSec 15
    if ($version.commit_sha) {
      $result.version = [string]$version.commit_sha
    } elseif ($version.commit) {
      $result.version = [string]$version.commit
    } else {
      $result.version = "unknown"
    }
  } catch {
    $result.version = "unavailable"
    Add-Finding $Warnings ("cloud_version_unavailable:" + (ConvertTo-SkybridgeSafeText -Text $_.Exception.Message -MaxLength 120))
  }

  try {
    $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1") -ApiBase $apiBase -Json 2>$null
    if ($LASTEXITCODE -eq 0) {
      $parity = (($raw | Out-String).Trim() | ConvertFrom-Json)
      if ($parity.status) { $result.parity = [string]$parity.status } else { $result.parity = "unknown" }
    } else {
      $result.parity = "unavailable"
      Add-Finding $Warnings "cloud_parity_check_failed"
    }
  } catch {
    $result.parity = "unavailable"
    Add-Finding $Warnings ("cloud_parity_unavailable:" + (ConvertTo-SkybridgeSafeText -Text $_.Exception.Message -MaxLength 120))
  }

  [pscustomobject]$result
}

function Get-OpenPrSummary([ref]$Warnings) {
  $gh = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $gh) {
    Add-Finding $Warnings "gh_unavailable_open_pr_summary_skipped"
    return @()
  }

  try {
    $raw = & gh pr list --state open --limit 20 --json number,title,isDraft,headRefName,baseRefName,url 2>$null
    if ($LASTEXITCODE -ne 0) {
      Add-Finding $Warnings "gh_pr_list_failed"
      return @()
    }
    $items = (($raw | Out-String).Trim() | ConvertFrom-Json)
    @($items | ForEach-Object {
      "#$($_.number) draft=$($_.isDraft) head=$($_.headRefName) base=$($_.baseRefName)"
    })
  } catch {
    Add-Finding $Warnings ("gh_pr_list_unavailable:" + (ConvertTo-SkybridgeSafeText -Text $_.Exception.Message -MaxLength 120))
    @()
  }
}

function New-Report {
  $warnings = @()
  $blockers = @()

  $currentBranch = Get-GitText -GitArgs @("rev-parse", "--abbrev-ref", "HEAD")
  if ([string]::IsNullOrWhiteSpace($currentBranch)) {
    $currentBranch = "unknown"
    Add-Finding ([ref]$warnings) "git_branch_unavailable"
  }

  $statusText = Get-GitText -GitArgs @("status", "--porcelain")
  $gitClean = [string]::IsNullOrWhiteSpace($statusText)
  $head = Get-GitText -GitArgs @("rev-parse", "HEAD")
  $originMain = Get-GitText -GitArgs @("rev-parse", "origin/main")
  $gitAligned = (-not [string]::IsNullOrWhiteSpace($head) -and $head -eq $originMain)
  if (-not $gitClean) { Add-Finding ([ref]$warnings) "git_worktree_has_changes" }
  if (-not $gitAligned) { Add-Finding ([ref]$warnings) "head_not_equal_existing_origin_main_ref" }

  $requiredDocs = Get-RequiredDocs
  $requiredScripts = Get-RequiredScripts
  $requiredSmokeNames = Get-RequiredSmokeScripts
  $packageScripts = Get-PackageScriptNames
  $requiredSmokeFiles = @(
    "scripts/powershell/smoke-managed-dev-e2e-handoff-status.ps1",
    "scripts/powershell/smoke-managed-dev-e2e-handoff-audit.ps1",
    "scripts/powershell/smoke-managed-dev-e2e-freeze-checklist.ps1",
    "scripts/powershell/smoke-managed-dev-e2e-required-artifacts.ps1",
    "scripts/powershell/smoke-managed-dev-e2e-no-mutation.ps1",
    "scripts/powershell/smoke-manual-managed-dev-e2e-handoff-fixture.ps1"
  )

  $missingDocs = @($requiredDocs | Where-Object { -not (Test-RelativeFile $_) })
  $missingScripts = @($requiredScripts | Where-Object { -not (Test-RelativeFile $_) })
  $missingSmokeFiles = @($requiredSmokeFiles | Where-Object { -not (Test-RelativeFile $_) })
  $missingSmokePackageScripts = @($requiredSmokeNames | Where-Object { $packageScripts -notcontains $_ })
  foreach ($item in $missingDocs) { Add-Finding ([ref]$blockers) "missing_doc:$item" }
  foreach ($item in $missingScripts) { Add-Finding ([ref]$blockers) "missing_script:$item" }
  foreach ($item in $missingSmokeFiles) { Add-Finding ([ref]$blockers) "missing_smoke_file:$item" }
  foreach ($item in $missingSmokePackageScripts) { Add-Finding ([ref]$blockers) "missing_package_smoke:$item" }

  $cloud = Get-CloudStatus ([ref]$warnings)
  if ($cloud.version -notin @("not_configured", "unavailable", "unknown") -and $cloud.version -ne $ExpectedCommit) {
    Add-Finding ([ref]$warnings) "cloud_version_differs_from_expected_commit"
  }

  $flags = New-SafetyFlags
  $report = [pscustomobject]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    expected_commit = $ExpectedCommit
    expected_cloud_image = $ExpectedCloudImage
    current_branch = $currentBranch
    git_clean = $gitClean
    git_aligned = $gitAligned
    cloud_health = [string]$cloud.health
    cloud_version = [string]$cloud.version
    cloud_parity = [string]$cloud.parity
    capability_matrix = @(Get-CapabilityMatrix)
    required_docs_present = ($missingDocs.Count -eq 0)
    required_scripts_present = ($missingScripts.Count -eq 0)
    required_smokes_present = ($missingSmokeFiles.Count -eq 0 -and $missingSmokePackageScripts.Count -eq 0)
    open_pr_summary = @(Get-OpenPrSummary ([ref]$warnings))
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    auto_merge_enabled = $false
    worker_loop_started = $false
    queue_runner_started = $false
    task_created = $false
    task_claimed = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    project_control_unpaused = $false
    token_printed = $false
    safety_flags = $flags
    blockers = @($blockers)
    warnings = @($warnings)
  }

  $report
}

function Write-Reports($Report) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "managed-dev-e2e-handoff.json"
  $mdPath = Join-Path $root "managed-dev-e2e-handoff.md"
  $Report | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Report | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Report | ConvertTo-Json -Depth 90 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $lines = @(
    "# Managed Dev E2E Handoff Audit",
    "",
    "- schema: $($Report.schema)",
    "- expected_commit: $($Report.expected_commit)",
    "- expected_cloud_image: $($Report.expected_cloud_image)",
    "- current_branch: $($Report.current_branch)",
    "- git_clean: $($Report.git_clean)",
    "- git_aligned: $($Report.git_aligned)",
    "- cloud_health: $($Report.cloud_health)",
    "- cloud_version: $($Report.cloud_version)",
    "- cloud_parity: $($Report.cloud_parity)",
    "- required_docs_present: $($Report.required_docs_present)",
    "- required_scripts_present: $($Report.required_scripts_present)",
    "- required_smokes_present: $($Report.required_smokes_present)",
    "- open_pr_count: $(@($Report.open_pr_summary).Count)",
    "- blockers: $(@($Report.blockers).Count)",
    "- warnings: $(@($Report.warnings).Count)",
    "- release_created=false",
    "- tag_created=false",
    "- asset_uploaded=false",
    "- auto_merge_enabled=false",
    "- worker_loop_started=false",
    "- token_printed=false"
  )
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

$report = New-Report

if ($Command -eq "safe-summary") {
  $report = [pscustomobject]@{
    schema = $Schema
    current_branch = $report.current_branch
    git_clean = $report.git_clean
    git_aligned = $report.git_aligned
    required_docs_present = $report.required_docs_present
    required_scripts_present = $report.required_scripts_present
    required_smokes_present = $report.required_smokes_present
    cloud_health = $report.cloud_health
    cloud_version = $report.cloud_version
    cloud_parity = $report.cloud_parity
    blockers = @($report.blockers)
    warnings = @($report.warnings)
    token_printed = $false
  }
}

if ($WriteReport -or $Command -eq "report") {
  Write-Reports $report
}

if ($Json) {
  $report | ConvertTo-Json -Depth 90
} elseif ($Command -eq "safe-summary") {
  Write-Host "Managed Dev E2E handoff: docs=$($report.required_docs_present) scripts=$($report.required_scripts_present) smokes=$($report.required_smokes_present) token_printed=false"
} else {
  Write-Host "Managed Dev E2E handoff audit"
  Write-Host "- branch: $($report.current_branch)"
  Write-Host "- git_clean: $($report.git_clean)"
  Write-Host "- git_aligned: $($report.git_aligned)"
  Write-Host "- cloud_health: $($report.cloud_health)"
  Write-Host "- cloud_version: $($report.cloud_version)"
  Write-Host "- cloud_parity: $($report.cloud_parity)"
  Write-Host "- required_docs_present: $($report.required_docs_present)"
  Write-Host "- required_scripts_present: $($report.required_scripts_present)"
  Write-Host "- required_smokes_present: $($report.required_smokes_present)"
  Write-Host "- token_printed=false"
}

if (@($report.blockers).Count -gt 0) {
  exit 1
}
