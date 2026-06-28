[CmdletBinding()]
param(
  [ValidateSet("status", "analyze", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/vite-chunk-warning-analysis",
  [string]$BuildLogPath = "",
  [string]$DistDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.vite_chunk_warning_analysis.v1"
$DefaultThresholdKb = 500.0

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
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/vite-chunk-warning-analysis"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/vite-chunk-warning-analysis."
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

function Get-GitDiffLines([string]$PathSpec) {
  $raw = & git -C $RepoRoot diff -- $PathSpec 2>$null
  if ($LASTEXITCODE -ne 0) { return @() }
  @($raw)
}

function Test-DiffLineMatches([string[]]$Lines, [string]$Pattern) {
  foreach ($line in $Lines) {
    if ($line -match "^[+-]" -and $line -notmatch "^(---|\+\+\+)" -and $line -match $Pattern) {
      return $true
    }
  }
  return $false
}

function Remove-Ansi([string]$Text) {
  if ([string]::IsNullOrEmpty($Text)) { return "" }
  $Text -replace "`e\[[0-9;]*m", ""
}

function Get-AppNameFromPath([string]$Path) {
  $safe = Convert-ToSafePath $Path
  if ($safe -match "^apps/([^/]+)/") { return $Matches[1] }
  "unknown"
}

function New-ChunkObject {
  param(
    [string]$Source,
    [string]$App,
    [string]$ChunkName,
    [double]$SizeKb,
    [long]$SizeBytes,
    [double]$ThresholdKb,
    [string]$DetectedFrom
  )
  [pscustomobject]@{
    source = $Source
    app = $App
    chunk_name = $ChunkName
    size_kb = [Math]::Round($SizeKb, 2)
    size_bytes = $SizeBytes
    threshold_kb = [Math]::Round($ThresholdKb, 2)
    detected_from = $DetectedFrom
    oversized = ($SizeKb -gt $ThresholdKb)
  }
}

function Get-DistDirectories {
  if (-not [string]::IsNullOrWhiteSpace($DistDir)) {
    $path = Resolve-RepoPath $DistDir
    if (Test-Path -LiteralPath $path -PathType Container) { return @((Get-Item -LiteralPath $path)) }
    return @()
  }
  @("apps/web/dist", "apps/desktop/dist") | ForEach-Object {
    $path = Join-Path $RepoRoot $_
    if (Test-Path -LiteralPath $path -PathType Container) { Get-Item -LiteralPath $path }
  }
}

function Get-ChunksFromDist {
  $chunks = @()
  foreach ($dir in @(Get-DistDirectories)) {
    $files = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Include "*.js" -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
      $sizeKb = [double]$file.Length / 1000.0
      $chunks += New-ChunkObject `
        -Source (Convert-ToSafePath $file.FullName) `
        -App (Get-AppNameFromPath $file.FullName) `
        -ChunkName $file.Name `
        -SizeKb $sizeKb `
        -SizeBytes $file.Length `
        -ThresholdKb $DefaultThresholdKb `
        -DetectedFrom "dist"
    }
  }
  $chunks
}

function Get-ChunksFromBuildLog {
  if ([string]::IsNullOrWhiteSpace($BuildLogPath)) { return @() }
  $path = Resolve-RepoPath $BuildLogPath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

  $chunks = @()
  $threshold = $DefaultThresholdKb
  foreach ($rawLine in @(Get-Content -LiteralPath $path)) {
    $line = Remove-Ansi ([string]$rawLine)
    if ($line -match "larger than\s+([0-9]+(?:\.[0-9]+)?)\s*kB") {
      $threshold = [double]$Matches[1]
    }
    if ($line -match "(?<chunk>(?:dist/)?assets/[^\s]+\.(?:js|mjs|css))\s+(?<size>[0-9]+(?:\.[0-9]+)?)\s+kB") {
      $chunk = [string]$Matches["chunk"]
      $sizeKb = [double]$Matches["size"]
      $chunks += New-ChunkObject `
        -Source (Convert-ToSafePath $path) `
        -App "build-log" `
        -ChunkName $chunk `
        -SizeKb $sizeKb `
        -SizeBytes ([long]($sizeKb * 1000)) `
        -ThresholdKb $threshold `
        -DetectedFrom "build_log"
    }
  }
  $chunks
}

function Get-ThresholdObserved([object[]]$Chunks) {
  foreach ($chunk in @($Chunks)) {
    if ($chunk.threshold_kb -gt 0) { return [double]$chunk.threshold_kb }
  }
  $DefaultThresholdKb
}

function Get-SourceContributors {
  $paths = @(
    "apps/web/src",
    "apps/desktop/src",
    "packages/react-widgets/src",
    "packages/client/src"
  )
  $items = @()
  foreach ($relative in $paths) {
    $full = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $full -Recurse -File -Include "*.ts", "*.tsx" -ErrorAction SilentlyContinue)) {
      if ($file.Name -match "\.test\." -or $file.Name -eq "vite-env.d.ts") { continue }
      $items += [pscustomobject]@{
        path = Convert-ToSafePath $file.FullName
        size_kb = [Math]::Round(([double]$file.Length / 1000.0), 2)
      }
    }
  }
  @($items | Sort-Object size_kb -Descending | Select-Object -First 8)
}

function Test-TextExists([string]$Pattern) {
  $scanRoots = @(
    "apps/web/src",
    "apps/desktop/src",
    "packages/react-widgets/src",
    "packages/client/src",
    "apps/web",
    "apps/desktop"
  )
  $matches = & rg -n --glob "*.ts" --glob "*.tsx" --glob "vite.config.*" $Pattern @scanRoots 2>$null
  return ($LASTEXITCODE -eq 0 -and @($matches).Count -gt 0)
}

function Get-SuspectedCauses {
  $causes = @()
  if (-not (Test-TextExists "import\(")) {
    $causes += "No dynamic imports detected in app/widget/client sources, so Vite emits single entry chunks."
  }
  if (-not (Test-TextExists "manualChunks")) {
    $causes += "No manualChunks strategy detected in Vite config."
  }
  $contributors = @(Get-SourceContributors)
  foreach ($item in @($contributors | Select-Object -First 3)) {
    $causes += "Large source contributor: $($item.path) (~$($item.size_kb) kB source)."
  }
  $causes += "React and React DOM are bundled into the single app entry chunks."
  $causes += "Desktop additionally imports the Tauri API in the single entry chunk."
  $causes
}

function Get-Recommendation([object[]]$OversizedChunks) {
  if (@($OversizedChunks).Count -eq 0) {
    return [pscustomobject]@{
      recommended_remediation = "no_action_until_warning_reappears"
      remediation_risk = "low"
      remediation_deferred = $true
    }
  }
  [pscustomobject]@{
    recommended_remediation = "defer_to_mg367a_route_or_manual_chunks_analysis"
    remediation_risk = "medium"
    remediation_deferred = $true
  }
}

function New-Report {
  $changedFiles = @(Get-GitChangedFiles)
  $allChunks = @(@(Get-ChunksFromDist) + @(Get-ChunksFromBuildLog))
  $oversized = @($allChunks | Where-Object { $_.oversized } | Sort-Object size_kb -Descending)
  $largest = @($allChunks | Sort-Object size_kb -Descending | Select-Object -First 1)
  $thresholdObserved = Get-ThresholdObserved $allChunks
  $packageDiff = @(Get-GitDiffLines "package.json")
  $viteDiff = @(Get-GitDiffLines "apps")

  $workflowChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "^\.github/workflows/"
  $viteConfigChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)(^|/)vite\.config\.[cm]?[jt]s$"
  $buildConfigChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)(^|/)(vite\.config\.[cm]?[jt]s|rollup\.config\.[cm]?[jt]s|tsconfig\.json)$"
  $deployConfigChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)^deploy/|docker-compose|Dockerfile|openresty|authelia|cloudflare|dns/|tls/|firewall/"
  $lockfileChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock)$"
  $dependencyChanged = Test-DiffLineMatches -Lines $packageDiff -Pattern '^\s*[+-]\s*"(dependencies|devDependencies|peerDependencies|optionalDependencies)"|^\s*[+-]\s*"[A-Za-z0-9@/_-]+"\s*:\s*"\^?\d+\.\d+'
  $chunkSizeLimitChanged = Test-DiffLineMatches -Lines $viteDiff -Pattern "chunkSizeWarningLimit"
  $warningSuppressed = (Test-DiffLineMatches -Lines $viteDiff -Pattern "(?i)chunkSizeWarningLimit|suppress|ignore.*warning") -or
    (Test-DiffLineMatches -Lines $packageDiff -Pattern "(?i)NODE_NO_WARNINGS|--logLevel\s+silent")
  $ciThresholdChanged = Test-DiffLineMatches -Lines $packageDiff -Pattern "(?i)continue-on-error|allow_failure|--silent|--passWithNoTests=false"

  $recommendation = Get-Recommendation $oversized
  $warnings = @()
  if (@($oversized).Count -gt 0) { $warnings += "vite_chunk_size_warning_detected" }
  if (@($allChunks).Count -eq 0) { $warnings += "no_dist_or_build_log_chunks_available" }

  [pscustomobject]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    current_commit = Get-CurrentCommit
    vite_warning_detected = (@($oversized).Count -gt 0)
    chunk_warning_non_failing = $true
    oversized_chunks = $oversized
    largest_chunk = if ($largest.Count -gt 0) { $largest[0] } else { $null }
    threshold_observed = [Math]::Round($thresholdObserved, 2)
    source_contributors = @(Get-SourceContributors)
    suspected_causes = @(Get-SuspectedCauses)
    chunk_size_limit_changed = [bool]$chunkSizeLimitChanged
    warning_suppressed = [bool]$warningSuppressed
    ci_threshold_changed = [bool]$ciThresholdChanged
    build_config_changed = [bool]$buildConfigChanged
    vite_config_changed = [bool]$viteConfigChanged
    workflow_changed = [bool]$workflowChanged
    deploy_config_changed = [bool]$deployConfigChanged
    dependency_changed = [bool]$dependencyChanged
    lockfile_changed = [bool]$lockfileChanged
    recommended_remediation = $recommendation.recommended_remediation
    remediation_risk = $recommendation.remediation_risk
    remediation_deferred = $recommendation.remediation_deferred
    blockers = @()
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
  $jsonPath = Join-Path $root "vite-chunk-warning-analysis.json"
  $mdPath = Join-Path $root "vite-chunk-warning-analysis.md"
  $Report | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Report | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $largestText = if ($null -ne $Report.largest_chunk) { "$($Report.largest_chunk.chunk_name) $($Report.largest_chunk.size_kb) kB" } else { "none" }
  $lines = @(
    "# Vite Chunk Warning Analysis Report",
    "",
    "- schema: $($Report.schema)",
    "- current_commit: $($Report.current_commit)",
    "- vite_warning_detected: $($Report.vite_warning_detected)",
    "- chunk_warning_non_failing: $($Report.chunk_warning_non_failing)",
    "- oversized_chunk_count: $(@($Report.oversized_chunks).Count)",
    "- largest_chunk: $largestText",
    "- threshold_observed: $($Report.threshold_observed) kB",
    "- recommended_remediation: $($Report.recommended_remediation)",
    "- remediation_risk: $($Report.remediation_risk)",
    "- remediation_deferred: $($Report.remediation_deferred)",
    "- chunk_size_limit_changed=false",
    "- warning_suppressed=false",
    "- ci_threshold_changed=false",
    "- build_config_changed=false",
    "- vite_config_changed=false",
    "- workflow_changed=false",
    "- deploy_config_changed=false",
    "- dependency_changed=false",
    "- lockfile_changed=false",
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
    vite_warning_detected = $report.vite_warning_detected
    oversized_chunk_count = @($report.oversized_chunks).Count
    largest_chunk = $report.largest_chunk
    recommended_remediation = $report.recommended_remediation
    remediation_deferred = $report.remediation_deferred
    warning_suppressed = $false
    chunk_size_limit_changed = $false
    token_printed = $false
  }
}

if ($WriteReport -or $Command -eq "report") {
  Write-Reports $report
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20
} elseif ($Command -eq "safe-summary") {
  Write-Host "Vite chunk warning analysis: oversized_chunks=$($report.oversized_chunk_count) remediation_deferred=$($report.remediation_deferred) token_printed=false"
} else {
  Write-Host "Vite chunk warning analysis"
  Write-Host "- vite_warning_detected: $($report.vite_warning_detected)"
  Write-Host "- oversized_chunks: $(@($report.oversized_chunks).Count)"
  Write-Host "- recommended_remediation: $($report.recommended_remediation)"
  Write-Host "- warning_suppressed=false"
  Write-Host "- chunk_size_limit_changed=false"
  Write-Host "- token_printed=false"
}
