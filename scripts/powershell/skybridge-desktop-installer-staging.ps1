param(
  [ValidateSet("status", "preview", "build", "artifact-check", "checksum", "stage", "audit", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/desktop-installer-staging",
  [switch]$SkipBuild,
  [switch]$CleanBeforeBuild,
  [string]$FixtureArtifactDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

$DesktopRoot = Join-Path $RepoRoot "apps\desktop"
$BundleRoot = Join-Path $DesktopRoot "src-tauri\target\release\bundle"
$StagingRoot = Join-Path $RepoRoot $OutputDir
$ArtifactStagingRoot = Join-Path $StagingRoot "artifacts"
$ChecksumRoot = Join-Path $StagingRoot "checksums"
$LogRoot = Join-Path $StagingRoot "logs"
$BuildCommand = "corepack pnpm -C apps/desktop build"
$PackageCommand = "corepack pnpm -C apps/desktop tauri:build"
$Schema = "skybridge.desktop_installer_staging.v1"

function Convert-ToRepoRelative([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  $resolved = $Path
  if (Test-Path -LiteralPath $Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
  } elseif (-not [System.IO.Path]::IsPathRooted($Path)) {
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
  }
  if ($resolved.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $resolved.Substring($RepoRoot.Length).TrimStart("\", "/").Replace("\", "/")
  }
  return $resolved.Replace("\", "/")
}

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function Invoke-GitText([string[]]$Arguments) {
  $output = & git @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed." }
  return (($output | Out-String).Trim())
}

function Get-GitState([ref]$Blockers, [ref]$Warnings, [bool]$StrictClean) {
  $commit = Invoke-GitText @("rev-parse", "HEAD")
  $branch = Invoke-GitText @("branch", "--show-current")
  $status = Invoke-GitText @("status", "--porcelain")
  $mainRef = ""
  $originMainRef = ""
  try { $mainRef = Invoke-GitText @("rev-parse", "main") } catch {}
  try { $originMainRef = Invoke-GitText @("rev-parse", "origin/main") } catch {}
  $mainAligned = (-not [string]::IsNullOrWhiteSpace($mainRef) -and $mainRef -eq $originMainRef)
  $clean = [string]::IsNullOrWhiteSpace($status)

  if ($StrictClean -and -not $clean) {
    Add-Finding $Blockers "git_worktree_dirty"
  }
  if ($branch -ne "main") {
    Add-Finding $Warnings "not_on_main"
  }
  if (-not $mainAligned) {
    Add-Finding $Warnings "main_not_aligned_with_origin_main"
  }
  if ($StrictClean -and $branch -eq "main" -and -not $mainAligned) {
    Add-Finding $Blockers "main_not_aligned_with_origin_main"
  }

  [pscustomobject]@{
    commit = $commit
    branch = $branch
    clean = $clean
    main_aligned_with_origin_main = $mainAligned
  }
}

function Get-Readiness([ref]$Blockers, [ref]$Warnings) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-desktop-packaging-readiness.ps1") -Command audit -Json
  if ($LASTEXITCODE -ne 0) {
    Add-Finding $Blockers "desktop_packaging_readiness_failed"
    return $null
  }
  $result = (($raw | Out-String).Trim() | ConvertFrom-Json)
  if (-not $result.ok) { Add-Finding $Blockers "desktop_packaging_readiness_failed" }
  foreach ($warning in @($result.warnings)) {
    if ($warning -eq "desktop_safety_static_scan_only" -or $warning -like "desktop_disabled_surface_mentions:*") {
      Add-Finding $Warnings $warning
    }
  }
  return $result
}

function Assert-PathUnderRoot([string]$Path, [string]$AllowedRoot, [string]$Name) {
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
  if (-not $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Name path is outside the allowed root."
  }
}

function Clear-ScopedBuildOutputs([ref]$Warnings) {
  $targets = @(
    (Join-Path $DesktopRoot "dist"),
    $BundleRoot,
    $StagingRoot
  )
  foreach ($target in $targets) {
    $fullTarget = [System.IO.Path]::GetFullPath($target)
    if ($target -eq $StagingRoot) {
      Assert-PathUnderRoot -Path $fullTarget -AllowedRoot (Join-Path $RepoRoot ".agent\tmp") -Name "OutputDir"
    } else {
      Assert-PathUnderRoot -Path $fullTarget -AllowedRoot $DesktopRoot -Name "Desktop build output"
    }
    if (Test-Path -LiteralPath $fullTarget) {
      Remove-Item -LiteralPath $fullTarget -Recurse -Force
    }
  }
  Add-Finding $Warnings "clean_before_build_scoped_to_desktop_outputs"
}

function Test-CommandAvailable([string]$Name) {
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-LocalPrerequisites([ref]$Blockers) {
  if (-not (Test-CommandAvailable "corepack")) {
    Add-Finding $Blockers "node_dependency_missing"
  }
  if (-not (Test-CommandAvailable "rustc")) {
    Add-Finding $Blockers "rust_missing"
  }
  if (-not (Test-CommandAvailable "cargo")) {
    Add-Finding $Blockers "cargo_missing"
  }
  $tauriBinCandidates = @(
    (Join-Path $DesktopRoot "node_modules\.bin\tauri.cmd"),
    (Join-Path $DesktopRoot "node_modules\.bin\tauri"),
    (Join-Path $RepoRoot "node_modules\.bin\tauri.cmd"),
    (Join-Path $RepoRoot "node_modules\.bin\tauri")
  )
  if (-not ($tauriBinCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)) {
    Add-Finding $Blockers "tauri_cli_missing"
  }
}

function Get-LogFailureCategory([string]$DefaultCategory, [string[]]$LogPaths) {
  $text = ""
  foreach ($path in $LogPaths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $text += "`n"
      $text += (Get-Content -Raw -LiteralPath $path)
    }
  }
  if ($text -match "(?i)webview2") { return "webview2_missing" }
  if ($text -match "(?i)windows sdk") { return "windows_sdk_missing" }
  if ($text -match "(?i)\bwix\b|wix toolset|light\.exe|candle\.exe") { return "wix_missing" }
  if ($text -match "(?i)\bnsis\b|makensis") { return "nsis_missing" }
  if ($text -match "(?i)tauri") { return "tauri_package_failed" }
  return $DefaultCategory
}

function Invoke-LoggedProcess([string]$Name, [string[]]$Arguments, [string]$FailureCategory, [ref]$Warnings) {
  New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
  $stdoutPath = Join-Path $LogRoot "$Name.stdout.log"
  $stderrPath = Join-Path $LogRoot "$Name.stderr.log"
  $corepack = (Get-Command "corepack" -ErrorAction Stop).Source
  $process = Start-Process -FilePath $corepack -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  if (-not $process.WaitForExit(1800000)) {
    try { $process.Kill() } catch {}
    Add-Finding $Warnings "build_logs_written_under_ignored_temp_path"
    return [pscustomobject]@{ attempted = $true; ok = $false; exit_code = $null; failure_category = "$FailureCategory`_timeout" }
  }
  Add-Finding $Warnings "build_logs_written_under_ignored_temp_path"
  if ($process.ExitCode -ne 0) {
    $category = Get-LogFailureCategory -DefaultCategory $FailureCategory -LogPaths @($stdoutPath, $stderrPath)
    return [pscustomobject]@{ attempted = $true; ok = $false; exit_code = $process.ExitCode; failure_category = $category }
  }
  return [pscustomobject]@{ attempted = $true; ok = $true; exit_code = 0; failure_category = $null }
}

function Get-ArtifactType([string]$Path) {
  $name = [System.IO.Path]::GetFileName($Path)
  if ($Path -match "(?i)\.msi$") { return "msi" }
  if ($Path -match "(?i)[\\/]nsis[\\/]" -or $name -match "(?i)setup.*\.exe$") { return "nsis" }
  if ($Path -match "(?i)\.exe$") { return "exe" }
  return "other"
}

function Get-SigningStatus([string]$Path) {
  try {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -eq "Valid") { return "signed" }
    if ($signature.Status -eq "NotSigned") { return "unsigned" }
    return "unknown"
  } catch {
    return "unknown"
  }
}

function Get-ArtifactInventory([datetime]$FreshSinceUtc, [bool]$RequireFresh, [string]$FixtureDir, [ref]$Warnings) {
  $sourceRoot = $BundleRoot
  $fixtureMode = -not [string]::IsNullOrWhiteSpace($FixtureDir)
  if ($fixtureMode) {
    $sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $FixtureDir))
    Assert-PathUnderRoot -Path $sourceRoot -AllowedRoot (Join-Path $RepoRoot ".agent\tmp") -Name "FixtureArtifactDir"
    Add-Finding $Warnings "fixture_artifact_mode"
  }

  if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { return @() }
  $candidates = @(
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File |
      Where-Object {
        $_.Extension -in @(".msi", ".exe", ".zip", ".msix", ".appx") -and
        ($fixtureMode -or $_.FullName.StartsWith($BundleRoot, [System.StringComparison]::OrdinalIgnoreCase))
      }
  )
  if ($RequireFresh) {
    $candidates = @($candidates | Where-Object { $_.LastWriteTimeUtc -ge $FreshSinceUtc.AddSeconds(-5) })
  }
  return @($candidates | Sort-Object FullName)
}

function Stage-Artifacts($Files, [string]$Commit, [ref]$Warnings) {
  New-Item -ItemType Directory -Force -Path $ArtifactStagingRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $ChecksumRoot | Out-Null
  Assert-PathUnderRoot -Path $ArtifactStagingRoot -AllowedRoot $StagingRoot -Name "Artifact staging"
  Assert-PathUnderRoot -Path $ChecksumRoot -AllowedRoot $StagingRoot -Name "Checksum staging"

  $artifactRecords = @()
  $checksumRecords = @()
  $sumLines = @()
  foreach ($file in @($Files)) {
    if ($file.Length -le 0) {
      Add-Finding $Warnings "artifact_size_zero:$($file.Name)"
      continue
    }
    $type = Get-ArtifactType -Path $file.FullName
    if ($type -eq "other") {
      Add-Finding $Warnings "unexpected_artifact_extension:$($file.Name)"
      continue
    }
    $destination = Join-Path $ArtifactStagingRoot $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    $hash = Get-FileHash -LiteralPath $destination -Algorithm SHA256
    $relativeDestination = Convert-ToRepoRelative $destination
    $sumLines += "$($hash.Hash.ToLowerInvariant())  $relativeDestination"
    $signing = Get-SigningStatus -Path $destination
    $record = [pscustomobject]@{
      file_name = $file.Name
      source_path = (Convert-ToRepoRelative $file.FullName)
      staged_path = $relativeDestination
      size_bytes = [int64]$file.Length
      sha256 = $hash.Hash.ToLowerInvariant()
      produced_by_commit = $Commit
      signing_status = $signing
      artifact_type = $type
      safe_to_upload_later = $true
      upload_now = $false
    }
    $artifactRecords += $record
    $checksumRecords += [pscustomobject]@{
      file_name = $file.Name
      staged_path = $relativeDestination
      sha256 = $hash.Hash.ToLowerInvariant()
    }
  }

  $shaPath = Join-Path $ChecksumRoot "SHA256SUMS.txt"
  $sumLines | Set-Content -LiteralPath $shaPath -Encoding UTF8

  [pscustomobject]@{
    artifacts = $artifactRecords
    checksums = $checksumRecords
    checksum_path = (Convert-ToRepoRelative $shaPath)
  }
}

function Write-StagingReports($Result) {
  New-Item -ItemType Directory -Force -Path $StagingRoot | Out-Null
  $manifestPath = Join-Path $StagingRoot "manifest.json"
  $reportPath = Join-Path $StagingRoot "desktop-installer-staging.md"
  $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

  $lines = @(
    "# Desktop Installer Staging",
    "",
    "- schema: $Schema",
    "- status: $($Result.status)",
    "- ok: $($Result.ok)",
    "- commit: $($Result.commit)",
    "- desktop_root: $($Result.desktop_root)",
    "- build_attempted: $($Result.build_attempted)",
    "- build_ok: $($Result.build_ok)",
    "- package_attempted: $($Result.package_attempted)",
    "- package_ok: $($Result.package_ok)",
    "- artifacts_found: $($Result.artifacts_found)",
    "- signing_status: $($Result.signing_status)",
    "- unsigned_installer_expected: $($Result.unsigned_installer_expected)",
    "- release_created: false",
    "- github_release_updated: false",
    "- tag_created: false",
    "- tag_moved: false",
    "- installer_uploaded: false",
    "- binary_uploaded: false",
    "- task_created: false",
    "- task_claimed: false",
    "- execution_started: false",
    "- codex_run_called: false",
    "- matlab_run_called: false",
    "- worker_loop_started: false",
    "- project_control_unpaused: false",
    "- token_printed: false",
    "",
    "## Staged Artifacts",
    ""
  )
  if (@($Result.staged_artifacts).Count -eq 0) {
    $lines += "- none"
  } else {
    foreach ($artifact in @($Result.staged_artifacts)) {
      $lines += "- $($artifact.file_name): $($artifact.staged_path) ($($artifact.size_bytes) bytes, sha256=$($artifact.sha256))"
    }
  }
  $lines += @("", "## Blockers", "")
  if (@($Result.blockers).Count -eq 0) {
    $lines += "- none"
  } else {
    foreach ($item in @($Result.blockers)) { $lines += "- $item" }
  }
  $lines += @("", "## Warnings", "")
  if (@($Result.warnings).Count -eq 0) {
    $lines += "- none"
  } else {
    foreach ($item in @($Result.warnings)) { $lines += "- $item" }
  }
  $lines | Set-Content -LiteralPath $reportPath -Encoding UTF8

  [pscustomobject]@{
    manifest = (Convert-ToRepoRelative $manifestPath)
    report = (Convert-ToRepoRelative $reportPath)
  }
}

function New-StagingResult {
  $blockers = @()
  $warnings = @()
  $doBuild = ($Command -eq "build" -and -not $SkipBuild)
  $doStage = ($Command -in @("build", "stage", "checksum"))
  $doChecksum = ($Command -in @("build", "stage", "checksum"))
  if ($Command -eq "build" -and $SkipBuild) {
    Add-Finding ([ref]$warnings) "build_skipped_by_flag"
  }

  $gitState = Get-GitState ([ref]$blockers) ([ref]$warnings) $doBuild
  $readiness = Get-Readiness ([ref]$blockers) ([ref]$warnings)

  if ($CleanBeforeBuild -and $doBuild) {
    Clear-ScopedBuildOutputs ([ref]$warnings)
  }

  $buildResult = [pscustomobject]@{ attempted = $false; ok = $false; exit_code = $null; failure_category = $null }
  $packageResult = [pscustomobject]@{ attempted = $false; ok = $false; exit_code = $null; failure_category = $null }
  $buildStartedAt = (Get-Date).ToUniversalTime()

  if ($doBuild) {
    Test-LocalPrerequisites ([ref]$blockers)
    if (@($blockers).Count -eq 0) {
      $buildResult = Invoke-LoggedProcess -Name "desktop-build" -Arguments @("pnpm", "-C", "apps/desktop", "build") -FailureCategory "build_script_failed" -Warnings ([ref]$warnings)
      if ($buildResult.ok) {
        $packageResult = Invoke-LoggedProcess -Name "desktop-package" -Arguments @("pnpm", "-C", "apps/desktop", "tauri:build") -FailureCategory "tauri_package_failed" -Warnings ([ref]$warnings)
      }
      if (-not $buildResult.ok) { Add-Finding ([ref]$blockers) $buildResult.failure_category }
      if ($buildResult.ok -and -not $packageResult.ok) { Add-Finding ([ref]$blockers) $packageResult.failure_category }
    }
  }

  $requireFreshArtifacts = ($Command -eq "build" -and $packageResult.ok)
  $artifactFiles = @(Get-ArtifactInventory -FreshSinceUtc $buildStartedAt -RequireFresh $requireFreshArtifacts -FixtureDir $FixtureArtifactDir -Warnings ([ref]$warnings))
  if ($Command -eq "build" -and $packageResult.ok -and @($artifactFiles).Count -eq 0) {
    Add-Finding ([ref]$blockers) "artifact_missing_after_build"
  }
  if ($Command -eq "artifact-check" -and @($artifactFiles).Count -eq 0) {
    Add-Finding ([ref]$warnings) "no_installer_artifacts_found"
  }
  if ($doStage -and @($artifactFiles).Count -eq 0) {
    Add-Finding ([ref]$warnings) "no_artifacts_to_stage"
  }

  $stage = [pscustomobject]@{ artifacts = @(); checksums = @(); checksum_path = "" }
  if ($doStage -and @($artifactFiles).Count -gt 0) {
    $stage = Stage-Artifacts -Files $artifactFiles -Commit $gitState.commit -Warnings ([ref]$warnings)
  }

  $signingStatus = "unknown"
  if (@($stage.artifacts).Count -gt 0) {
    $statuses = @($stage.artifacts | ForEach-Object { $_.signing_status } | Sort-Object -Unique)
    if ($statuses -contains "signed") {
      $signingStatus = if (@($statuses).Count -eq 1) { "signed" } else { "mixed" }
    } elseif ($statuses -contains "unsigned") {
      $signingStatus = "unsigned"
    }
  } elseif ($readiness -and $readiness.signing_config_present -eq $false) {
    $signingStatus = "unsigned"
  }

  $ok = (@($blockers).Count -eq 0)
  $status = if (-not $ok) { "blocked" } elseif (@($warnings).Count -gt 0) { "warning" } else { "pass" }
  $result = [pscustomobject]@{
    schema = $Schema
    command = $Command
    ok = $ok
    status = $status
    commit = $gitState.commit
    branch = $gitState.branch
    git_clean = $gitState.clean
    main_aligned_with_origin_main = $gitState.main_aligned_with_origin_main
    desktop_root = "apps/desktop"
    framework = if ($readiness) { $readiness.framework } else { "unknown" }
    app_name = if ($readiness) { $readiness.app_name } else { "" }
    app_identifier = if ($readiness) { $readiness.app_identifier } else { "" }
    app_version = if ($readiness) { $readiness.app_version } else { "" }
    build_command = $BuildCommand
    package_command = $PackageCommand
    clean_before_build = [bool]$CleanBeforeBuild
    build_attempted = [bool]$buildResult.attempted
    build_ok = [bool]$buildResult.ok
    build_exit_code = $buildResult.exit_code
    build_failure_category = $buildResult.failure_category
    package_attempted = [bool]$packageResult.attempted
    package_ok = [bool]$packageResult.ok
    package_exit_code = $packageResult.exit_code
    package_failure_category = $packageResult.failure_category
    artifacts_found = (@($artifactFiles).Count -gt 0)
    artifacts = @($artifactFiles | ForEach-Object {
      [pscustomobject]@{
        file_name = $_.Name
        source_path = (Convert-ToRepoRelative $_.FullName)
        size_bytes = [int64]$_.Length
        last_write_time_utc = $_.LastWriteTimeUtc.ToString("o")
        artifact_type = (Get-ArtifactType -Path $_.FullName)
      }
    })
    staged_artifacts = @($stage.artifacts)
    checksums = @($stage.checksums)
    checksum_path = $stage.checksum_path
    manifest_path = ""
    report_path = ""
    signing_status = $signingStatus
    unsigned_installer_expected = if ($readiness) { [bool]$readiness.unsigned_installer_expected } else { $true }
    blockers = @($blockers)
    warnings = @($warnings)
    release_created = $false
    github_release_updated = $false
    tag_created = $false
    tag_moved = $false
    installer_uploaded = $false
    binary_uploaded = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  }

  if ($WriteReport -or $Command -in @("build", "stage", "checksum")) {
    $paths = Write-StagingReports $result
    $result.manifest_path = $paths.manifest
    $result.report_path = $paths.report
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $RepoRoot $result.manifest_path) -Encoding UTF8
  }

  return $result
}

$result = New-StagingResult
$result | ConvertTo-Json -Depth 10
if (-not $result.ok) { exit 1 }
