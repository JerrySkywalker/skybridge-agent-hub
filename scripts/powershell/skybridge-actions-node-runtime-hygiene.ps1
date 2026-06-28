[CmdletBinding()]
param(
  [ValidateSet("status", "audit", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/actions-node-runtime-hygiene",
  [string]$ExpectedCommit = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.actions_node_runtime_hygiene.v1"

$KnownDockerActions = @{
  "docker/metadata-action" = @{
    node20_versions = @("v5")
    node24_candidate = "v6"
    latest_verified = "v6.1.0"
  }
  "docker/login-action" = @{
    node20_versions = @("v3")
    node24_candidate = "v4"
    latest_verified = "v4.2.0"
  }
  "docker/setup-buildx-action" = @{
    node20_versions = @("v3")
    node24_candidate = "v4"
    latest_verified = "v4.1.0"
  }
  "docker/build-push-action" = @{
    node20_versions = @("v6")
    node24_candidate = "v7"
    latest_verified = "v7.2.0"
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
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/actions-node-runtime-hygiene"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/actions-node-runtime-hygiene."
  }
  $fullTarget
}

function Get-CurrentCommit {
  $value = (& git -C $RepoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($value)) { return [string]$value }
  "unknown"
}

function Get-GitChangedFiles {
  $files = @()
  $raw = & git -C $RepoRoot status --porcelain=v1 2>$null
  if ($LASTEXITCODE -ne 0) { return @() }
  foreach ($line in @($raw)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path -match " -> ") { $path = ($path -split " -> ")[-1].Trim() }
    if (-not [string]::IsNullOrWhiteSpace($path)) { $files += $path.Replace("\", "/") }
  }
  $files
}

function Test-AnyPathMatches([string[]]$Paths, [string]$Pattern) {
  foreach ($path in $Paths) {
    if ($path -match $Pattern) { return $true }
  }
  return $false
}

function Get-WorkflowDiffLines {
  $raw = & git -C $RepoRoot diff -- .github/workflows 2>$null
  if ($LASTEXITCODE -ne 0) { return @() }
  @($raw)
}

function Test-DiffLineMatches([string[]]$Lines, [string]$Pattern) {
  foreach ($line in $Lines) {
    if ($line -match '^[+-]' -and $line -notmatch '^(---|\+\+\+)' -and $line -match $Pattern) {
      return $true
    }
  }
  return $false
}

function Get-WorkflowFiles {
  $root = Join-Path $RepoRoot ".github/workflows"
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
  @(Get-ChildItem -LiteralPath $root -File -Include "*.yml", "*.yaml" | Sort-Object FullName)
}

function Get-PinType([string]$Version) {
  if ($Version -match "^[a-f0-9]{40}$") { return "sha" }
  if ($Version -match "^v\d+$") { return "major" }
  if ($Version -match "^v\d+\.\d+(\.\d+)?") { return "tag" }
  "tag"
}

function Get-KnownRuntime([string]$Action, [string]$Version) {
  if (-not $KnownDockerActions.ContainsKey($Action)) { return "unknown" }
  $known = $KnownDockerActions[$Action]
  if (@($known.node20_versions) -contains $Version) { return "node20" }
  if ($Version -eq [string]$known.node24_candidate) { return "node24" }
  "unknown"
}

function Get-ActionsDetected {
  $items = @()
  foreach ($file in Get-WorkflowFiles) {
    $safe = Convert-ToSafePath $file.FullName
    $lines = Get-Content -LiteralPath $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = [string]$lines[$i]
      if ($line -notmatch "^\s*uses:\s*([^#\s]+)") { continue }
      $uses = $Matches[1].Trim("'`"")
      $parts = $uses -split "@", 2
      $action = $parts[0]
      $version = if ($parts.Count -gt 1) { $parts[1] } else { "" }
      $candidate = ""
      $latest = ""
      if ($KnownDockerActions.ContainsKey($action)) {
        $candidate = [string]$KnownDockerActions[$action].node24_candidate
        $latest = [string]$KnownDockerActions[$action].latest_verified
      }
      $runtime = Get-KnownRuntime -Action $action -Version $version
      $items += [pscustomobject]@{
        workflow_file = $safe
        line = $i + 1
        uses = $uses
        action = $action
        version = $version
        pin_type = Get-PinType $version
        known_runtime = $runtime
        node24_candidate = $candidate
        latest_verified = $latest
      }
    }
  }
  $items
}

function Get-VersionUpdatesFromDiff {
  $updates = @()
  $diffLines = Get-WorkflowDiffLines
  $removed = @($diffLines | Where-Object { $_ -match "^-.*uses:\s*docker/[^@\s]+@v\d+" })
  $added = @($diffLines | Where-Object { $_ -match "^\+.*uses:\s*docker/[^@\s]+@v\d+" })
  for ($i = 0; $i -lt [Math]::Min($removed.Count, $added.Count); $i++) {
    $old = ([string]$removed[$i]) -replace "^-.*uses:\s*", ""
    $new = ([string]$added[$i]) -replace "^\+.*uses:\s*", ""
    $oldParts = $old.Trim() -split "@", 2
    $newParts = $new.Trim() -split "@", 2
    if ($oldParts[0] -eq $newParts[0]) {
      $updates += [pscustomobject]@{
        action = $oldParts[0]
        from = $oldParts[1]
        to = $newParts[1]
        from_runtime = Get-KnownRuntime -Action $oldParts[0] -Version $oldParts[1]
        to_runtime = Get-KnownRuntime -Action $newParts[0] -Version $newParts[1]
      }
    }
  }
  $updates
}

function New-Report {
  $changedFiles = @(Get-GitChangedFiles)
  $workflowDiff = @(Get-WorkflowDiffLines)
  $actions = @(Get-ActionsDetected)
  $suspectedCurrent = @($actions | Where-Object { $_.known_runtime -eq "node20" })
  $versionUpdates = @(Get-VersionUpdatesFromDiff)
  $suspectedFromDiff = @($versionUpdates | Where-Object { $_.from_runtime -eq "node20" })
  $updateCandidates = @($actions | Where-Object {
    $_.known_runtime -eq "node20" -and -not [string]::IsNullOrWhiteSpace($_.node24_candidate)
  } | ForEach-Object {
    [pscustomobject]@{
      action = $_.action
      current_version = $_.version
      candidate_version = $_.node24_candidate
      candidate_runtime = "node24"
      workflow_file = $_.workflow_file
    }
  })

  $workflowChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "^\.github/workflows/"
  $triggersChanged = Test-DiffLineMatches -Lines $workflowDiff -Pattern "^\s*[+-]\s*(on:|pull_request:|push:|workflow_dispatch:|workflow_run:|branches:|tags:|types:)"
  $permissionsExpanded = Test-DiffLineMatches -Lines $workflowDiff -Pattern "^\s*[+-]\s*(permissions:|contents:|packages:|actions:|id-token:|deployments:|security-events:)"
  $warningSuppressed = Test-DiffLineMatches -Lines $workflowDiff -Pattern "(?i)continue-on-error|NODE_NO_WARNINGS|ACTIONS_ALLOW_UNSECURE_COMMANDS|chunkSizeWarningLimit|deprecation"
  $ciThresholdChanged = Test-DiffLineMatches -Lines $workflowDiff -Pattern "(?i)continue-on-error|--passWithNoTests=false|allow_failure|fail-fast:\s*false"

  $buildConfigChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)(^|/)(vite\.config\.[cm]?[jt]s|rollup\.config\.[cm]?[jt]s|tsconfig\.json|pnpm-lock\.yaml|package-lock\.json)$"
  $dockerfileChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)(^|/)Dockerfile$|\.Dockerfile$|deploy/dockerfiles/"
  $deployConfigChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)^deploy/(?!dockerfiles/)|docker-compose|openresty|authelia|cloudflare|dns/|tls/|firewall/"
  $secretsChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)(^|/)(secrets|\.env|.*token.*|.*credential.*|.*proxy.*)"

  $remediationStatus = "no_change_needed"
  if ($updateCandidates.Count -gt 0) { $remediationStatus = "update_action_version" }
  elseif ($versionUpdates.Count -gt 0 -and $suspectedCurrent.Count -eq 0) { $remediationStatus = "update_action_version" }
  elseif ($actions.Count -eq 0) { $remediationStatus = "blocked_insufficient_evidence" }

  $blockers = @()
  if ($permissionsExpanded) { $blockers += "permissions_expanded" }
  if ($triggersChanged) { $blockers += "triggers_changed" }
  if ($warningSuppressed) { $blockers += "warning_suppressed" }
  if ($ciThresholdChanged) { $blockers += "ci_threshold_changed" }
  if ($secretsChanged) { $blockers += "secrets_changed" }
  if ($dockerfileChanged) { $blockers += "dockerfile_changed" }
  if ($deployConfigChanged) { $blockers += "deploy_config_changed" }

  $warnings = @()
  if ($suspectedCurrent.Count -gt 0) { $warnings += "current_node20_actions_detected" }

  [pscustomobject]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    current_commit = Get-CurrentCommit
    expected_commit = $ExpectedCommit
    workflow_files_inspected = @(Get-WorkflowFiles | ForEach-Object { Convert-ToSafePath $_.FullName })
    actions_detected = $actions
    suspected_deprecation_sources = @($suspectedCurrent + $suspectedFromDiff | ForEach-Object {
      [pscustomobject]@{
        action = $_.action
        workflow_file = if ($_.workflow_file) { $_.workflow_file } else { "git_diff" }
        version = if ($_.version) { $_.version } else { $_.from }
        runtime = if ($_.known_runtime) { $_.known_runtime } else { $_.from_runtime }
      }
    })
    update_candidates = $updateCandidates
    version_updates_detected = $versionUpdates
    workflow_changed = [bool]$workflowChanged
    build_config_changed = [bool]$buildConfigChanged
    deploy_config_changed = [bool]$deployConfigChanged
    dockerfile_changed = [bool]$dockerfileChanged
    secrets_changed = [bool]$secretsChanged
    permissions_expanded = [bool]$permissionsExpanded
    triggers_changed = [bool]$triggersChanged
    warning_suppressed = [bool]$warningSuppressed
    ci_threshold_changed = [bool]$ciThresholdChanged
    remediation_status = $remediationStatus
    blockers = $blockers
    warnings = $warnings
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
    token_printed = $false
  }
}

function Write-Reports($Report) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "actions-node-runtime-hygiene.json"
  $mdPath = Join-Path $root "actions-node-runtime-hygiene.md"
  $Report | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Report | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $lines = @(
    "# Actions Node Runtime Hygiene Report",
    "",
    "- schema: $($Report.schema)",
    "- current_commit: $($Report.current_commit)",
    "- workflow_files_inspected: $(@($Report.workflow_files_inspected).Count)",
    "- actions_detected: $(@($Report.actions_detected).Count)",
    "- suspected_deprecation_sources: $(@($Report.suspected_deprecation_sources).Count)",
    "- version_updates_detected: $(@($Report.version_updates_detected).Count)",
    "- remediation_status: $($Report.remediation_status)",
    "- workflow_changed: $($Report.workflow_changed)",
    "- permissions_expanded=false",
    "- triggers_changed=false",
    "- secrets_changed=false",
    "- warning_suppressed=false",
    "- ci_threshold_changed=false",
    "- build_config_changed=false",
    "- deploy_config_changed=false",
    "- dockerfile_changed=false",
    "- release_created=false",
    "- tag_created=false",
    "- asset_uploaded=false",
    "- worker_loop_started=false",
    "- token_printed=false"
  )
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

$report = New-Report
if ($Command -eq "safe-summary") {
  $report = [pscustomobject]@{
    schema = $Schema
    action_count = @($report.actions_detected).Count
    suspected_deprecation_source_count = @($report.suspected_deprecation_sources).Count
    remediation_status = $report.remediation_status
    permissions_expanded = $false
    triggers_changed = $false
    warning_suppressed = $false
    token_printed = $false
  }
}

if ($WriteReport -or $Command -eq "report") {
  Write-Reports $report
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20
} elseif ($Command -eq "safe-summary") {
  Write-Host "Actions Node runtime hygiene: actions=$($report.action_count) suspected=$($report.suspected_deprecation_source_count) token_printed=false"
} else {
  Write-Host "Actions Node runtime hygiene"
  Write-Host "- actions_detected: $(@($report.actions_detected).Count)"
  Write-Host "- suspected_deprecation_sources: $(@($report.suspected_deprecation_sources).Count)"
  Write-Host "- remediation_status: $($report.remediation_status)"
  Write-Host "- workflow_changed: $($report.workflow_changed)"
  Write-Host "- warning_suppressed=false"
  Write-Host "- token_printed=false"
}
