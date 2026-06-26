param(
  [ValidateSet("status", "inventory", "build-preview", "build-local", "artifact-check", "audit", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [switch]$SkipBuild,
  [string]$OutputDir = ".agent/tmp/desktop-packaging"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$DesktopRoot = Join-Path $RepoRoot "apps\desktop"
$DesktopPackagePath = Join-Path $DesktopRoot "package.json"
$TauriConfigPath = Join-Path $DesktopRoot "src-tauri\tauri.conf.json"
$CargoTomlPath = Join-Path $DesktopRoot "src-tauri\Cargo.toml"

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

function Read-JsonFile([string]$Path) {
  (Get-Content -Raw -LiteralPath $Path) | ConvertFrom-Json
}

function Get-Prop($Object, [string]$Name, $Default = $null) {
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function Test-CommandAvailable([string]$Name) {
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ArtifactInventory {
  $bundleRoot = Join-Path $DesktopRoot "src-tauri\target\release\bundle"
  $artifactPaths = @()
  if (Test-Path -LiteralPath $bundleRoot -PathType Container) {
    $artifactPaths = @(
      Get-ChildItem -LiteralPath $bundleRoot -Recurse -File |
        Where-Object {
          $_.Extension -in @(".msi", ".exe", ".zip", ".msix", ".appx") -or
          $_.FullName -match "\\bundle\\nsis\\|\\bundle\\msi\\"
        } |
        ForEach-Object { Convert-ToRepoRelative $_.FullName } |
        Sort-Object -Unique
    )
  }

  $installer = $false
  $portable = $false
  foreach ($path in $artifactPaths) {
    if ($path -match "(?i)\.msi$|setup.*\.exe$|/bundle/nsis/|/bundle/msi/") {
      $installer = $true
    }
    if (($path -match "(?i)portable.*\.zip$") -or (($path -match "(?i)\.exe$") -and ($path -notmatch "(?i)setup.*\.exe$|/bundle/nsis/|/bundle/msi/"))) {
      $portable = $true
    }
  }

  [pscustomobject]@{
    artifact_paths = $artifactPaths
    artifact_count = @($artifactPaths).Count
    installer_artifact_found = $installer
    portable_artifact_found = $portable
  }
}

function Test-DesktopSafety([ref]$Blockers, [ref]$Warnings) {
  $sourceRoots = @(
    (Join-Path $DesktopRoot "src"),
    (Join-Path $DesktopRoot "src-tauri\src")
  )

  $sourceText = ""
  $backendText = ""
  foreach ($root in $sourceRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $files = Get-ChildItem -LiteralPath $root -Recurse -File |
      Where-Object { $_.Extension -in @(".ts", ".tsx", ".rs", ".json", ".css") }
    foreach ($file in $files) {
      $content = Get-Content -Raw -LiteralPath $file.FullName
      $sourceText += "`n"
      $sourceText += $content
      if ($file.FullName.StartsWith((Join-Path $DesktopRoot "src-tauri\src"), [System.StringComparison]::OrdinalIgnoreCase)) {
        $backendText += "`n"
        $backendText += $content
      }
    }
  }

  if ([string]::IsNullOrWhiteSpace($sourceText)) {
    Add-Finding $Blockers "desktop_source_missing"
    return $false
  }

  $forbiddenRuntimeMarkers = @(
    "run-until-hold",
    "run-until-complete",
    "skybridge-worker-template-runner.ps1",
    "skybridge-live-safe-task-pilot.ps1",
    "skybridge-live-matlab-golden",
    "skybridge-live-codex-analysis",
    "project_control_unpaused=true",
    "worker_loop_started=true",
    "codex_run_called=true",
    "matlab_run_called=true",
    "pr_created=true"
  )

  foreach ($marker in $forbiddenRuntimeMarkers) {
    if ($backendText -like "*$marker*") {
      Add-Finding $Blockers "desktop_forbidden_runtime_marker:$marker"
    } elseif ($sourceText -like "*$marker*") {
      Add-Finding $Warnings "desktop_disabled_surface_mentions:$marker"
    }
  }

  $requiredDisabledMarkers = @(
    "Claim task disabled",
    "Execute task disabled",
    "Worker loop unavailable",
    "Codex execution disabled",
    "MATLAB execution disabled",
    "PR creation disabled",
    "apply unavailable in Desktop",
    "token_printed=false"
  )

  foreach ($marker in $requiredDisabledMarkers) {
    if ($sourceText -notlike "*$marker*") {
      Add-Finding $Blockers "desktop_disabled_marker_missing:$marker"
    }
  }

  Add-Finding $Warnings "desktop_safety_static_scan_only"
  return (@($Blockers.Value | Where-Object { $_ -like "desktop_*" }).Count -eq 0)
}

function Invoke-LocalBuild([ref]$Blockers, [ref]$Warnings) {
  if (-not (Test-CommandAvailable "corepack")) {
    Add-Finding $Blockers "package_manager_missing"
    return [pscustomobject]@{ attempted = $false; ok = $false; exit_code = $null; failure_category = "package_manager_missing" }
  }

  if (-not (Test-Path -LiteralPath (Join-Path $DesktopRoot "node_modules") -PathType Container)) {
    Add-Finding $Blockers "node_dependency_missing"
    return [pscustomobject]@{ attempted = $false; ok = $false; exit_code = $null; failure_category = "node_dependency_missing" }
  }

  if (-not (Test-CommandAvailable "rustc")) {
    Add-Finding $Blockers "rust_missing"
    return [pscustomobject]@{ attempted = $false; ok = $false; exit_code = $null; failure_category = "rust_missing" }
  }

  New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot $OutputDir) | Out-Null
  $stdoutPath = Join-Path $RepoRoot (Join-Path $OutputDir "desktop-build.stdout.log")
  $stderrPath = Join-Path $RepoRoot (Join-Path $OutputDir "desktop-build.stderr.log")
  $corepack = (Get-Command "corepack" -ErrorAction Stop).Source
  $process = Start-Process -FilePath $corepack -ArgumentList @("pnpm", "-C", "apps/desktop", "tauri:build") -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  if (-not $process.WaitForExit(1800000)) {
    try { $process.Kill() } catch {}
    Add-Finding $Blockers "desktop_package_build_timeout"
    return [pscustomobject]@{ attempted = $true; ok = $false; exit_code = $null; failure_category = "desktop_package_build_timeout" }
  }

  if ($process.ExitCode -ne 0) {
    Add-Finding $Blockers "desktop_package_build_failed"
    Add-Finding $Warnings "build_logs_written_under_ignored_temp_path"
    return [pscustomobject]@{ attempted = $true; ok = $false; exit_code = $process.ExitCode; failure_category = "desktop_package_build_failed" }
  }

  Add-Finding $Warnings "build_logs_written_under_ignored_temp_path"
  return [pscustomobject]@{ attempted = $true; ok = $true; exit_code = 0; failure_category = $null }
}

function New-ReadinessResult {
  $blockers = @()
  $warnings = @()
  $rootPackage = $null
  $desktopPackage = $null
  $tauriConfig = $null

  if (-not (Test-Path -LiteralPath $DesktopRoot -PathType Container)) {
    Add-Finding ([ref]$blockers) "desktop_root_missing"
  }
  if (Test-Path -LiteralPath (Join-Path $RepoRoot "package.json") -PathType Leaf) {
    $rootPackage = Read-JsonFile (Join-Path $RepoRoot "package.json")
  } else {
    Add-Finding ([ref]$blockers) "root_package_json_missing"
  }
  if (Test-Path -LiteralPath $DesktopPackagePath -PathType Leaf) {
    $desktopPackage = Read-JsonFile $DesktopPackagePath
  } else {
    Add-Finding ([ref]$blockers) "desktop_package_json_missing"
  }
  if (Test-Path -LiteralPath $TauriConfigPath -PathType Leaf) {
    $tauriConfig = Read-JsonFile $TauriConfigPath
  } else {
    Add-Finding ([ref]$blockers) "desktop_package_config_missing"
  }
  if (-not (Test-Path -LiteralPath $CargoTomlPath -PathType Leaf)) {
    Add-Finding ([ref]$blockers) "desktop_cargo_manifest_missing"
  }

  $rootPackageManager = [string](Get-Prop $rootPackage "packageManager" "")
  $packageManager = if ($rootPackageManager -match "^pnpm") { "pnpm" } elseif ($rootPackageManager) { $rootPackageManager } else { "unknown" }
  $scripts = Get-Prop $desktopPackage "scripts"
  $buildScript = [string](Get-Prop $scripts "build" "")
  $packageScript = [string](Get-Prop $scripts "tauri:build" "")
  $buildCommand = if ($buildScript) { "corepack pnpm -C apps/desktop build" } else { $null }
  $packageCommand = if ($packageScript) { "corepack pnpm -C apps/desktop tauri:build" } else { $null }
  if (-not $buildCommand) { Add-Finding ([ref]$blockers) "desktop_build_script_missing" }
  if (-not $packageCommand) { Add-Finding ([ref]$blockers) "desktop_package_script_missing" }

  $framework = "unknown"
  $desktopDeps = Get-Prop $desktopPackage "dependencies"
  $desktopDevDeps = Get-Prop $desktopPackage "devDependencies"
  $hasTauriApi = $null -ne (Get-Prop $desktopDeps "@tauri-apps/api")
  $hasTauriCli = $null -ne (Get-Prop $desktopDevDeps "@tauri-apps/cli")
  $hasReact = $null -ne (Get-Prop $desktopDeps "react")
  $schema = [string](Get-Prop $tauriConfig '$schema' "")
  if ($hasTauriApi -and $hasTauriCli -and ($schema -match "tauri")) {
    $framework = if ($hasReact) { "Tauri v2 + React/Vite" } else { "Tauri v2" }
  }

  $productName = [string](Get-Prop $tauriConfig "productName" "")
  $appIdentifier = [string](Get-Prop $tauriConfig "identifier" "")
  $tauriVersion = [string](Get-Prop $tauriConfig "version" "")
  $packageVersion = [string](Get-Prop $desktopPackage "version" "")
  $appVersion = if ($tauriVersion) { $tauriVersion } else { $packageVersion }
  if ($packageVersion -and $tauriVersion -and $packageVersion -ne $tauriVersion) {
    Add-Finding ([ref]$warnings) "desktop_package_version_mismatch"
  }
  if (-not $productName) { Add-Finding ([ref]$blockers) "app_name_missing" }
  if (-not $appIdentifier) { Add-Finding ([ref]$blockers) "app_identifier_missing" }
  if (-not $appVersion) { Add-Finding ([ref]$blockers) "app_version_missing" }

  $bundle = Get-Prop $tauriConfig "bundle"
  $bundleActive = [bool](Get-Prop $bundle "active" $false)
  $bundleTargets = Get-Prop $bundle "targets" ""
  $targetText = (($bundleTargets | ConvertTo-Json -Compress -Depth 4) + "")
  $icons = @()
  $bundleIcons = Get-Prop $bundle "icon"
  if ($bundleIcons) { $icons += @($bundleIcons) }
  $app = Get-Prop $tauriConfig "app"
  $trayIcon = Get-Prop $app "trayIcon" $null
  if ($trayIcon) { $icons += $trayIcon }

  $iconFilesPresent = $true
  foreach ($icon in $icons) {
    $iconValue = if ($icon -is [string]) { $icon } else { [string](Get-Prop $icon "iconPath" "") }
    if ([string]::IsNullOrWhiteSpace($iconValue)) {
      $iconFilesPresent = $false
      Add-Finding ([ref]$blockers) "icon_config_unreadable"
      continue
    }
    $iconPath = Join-Path (Join-Path $DesktopRoot "src-tauri") $iconValue
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
      $iconFilesPresent = $false
      Add-Finding ([ref]$blockers) "icon_file_missing:$iconValue"
    }
  }
  $iconConfigPresent = (@($icons).Count -gt 0 -and $iconFilesPresent)
  $iconText = (($icons | ForEach-Object { if ($_ -is [string]) { $_ } else { [string](Get-Prop $_ "iconPath" "") } }) -join " ")
  $windowsPackagingConfigPresent = ($bundleActive -and ($targetText -match "(?i)all|msi|nsis|appx") -and ($iconText -match "(?i)\.ico"))
  if (-not $windowsPackagingConfigPresent) {
    Add-Finding ([ref]$blockers) "windows_packaging_config_missing"
  }

  $tauriConfigRaw = if (Test-Path -LiteralPath $TauriConfigPath -PathType Leaf) { Get-Content -Raw -LiteralPath $TauriConfigPath } else { "" }
  $signingConfigPresent = ($tauriConfigRaw -match "(?i)certificateThumbprint|certificateFile|signCommand|privateKey|signing")
  if (-not $signingConfigPresent) {
    Add-Finding ([ref]$warnings) "signing_not_configured"
    Add-Finding ([ref]$warnings) "unsigned_installer_expected"
  }

  Test-DesktopSafety ([ref]$blockers) ([ref]$warnings) | Out-Null

  $localBuild = [pscustomobject]@{ attempted = $false; ok = $false; exit_code = $null; failure_category = $null }
  if ($Command -eq "build-local") {
    if ($SkipBuild) {
      Add-Finding ([ref]$warnings) "build_local_skipped_by_flag"
      $localBuild = [pscustomobject]@{ attempted = $false; ok = $false; exit_code = $null; failure_category = "build_local_skipped_by_flag" }
    } else {
      $localBuild = Invoke-LocalBuild ([ref]$blockers) ([ref]$warnings)
    }
  } elseif ($Command -ne "artifact-check") {
    Add-Finding ([ref]$warnings) "local_build_not_attempted"
  }

  $artifacts = Get-ArtifactInventory
  if ($Command -eq "artifact-check" -and $artifacts.artifact_count -eq 0) {
    Add-Finding ([ref]$warnings) "no_local_packaging_artifacts_found"
  }

  $buildPreviewOk = ($buildCommand -and $packageCommand -and $windowsPackagingConfigPresent -and $iconConfigPresent -and ($framework -ne "unknown"))
  $ok = (@($blockers).Count -eq 0)
  $status = if (-not $ok) { "blocked" } elseif (@($warnings).Count -gt 0) { "warning" } else { "pass" }

  [pscustomobject]@{
    schema = "skybridge.desktop_packaging_readiness.v1"
    command = $Command
    ok = $ok
    status = $status
    desktop_root = (Convert-ToRepoRelative $DesktopRoot)
    framework = $framework
    package_manager = $packageManager
    build_command_detected = $buildCommand
    package_command_detected = $packageCommand
    app_name = $productName
    app_identifier = $appIdentifier
    app_version = $appVersion
    windows_packaging_config_present = [bool]$windowsPackagingConfigPresent
    icon_config_present = [bool]$iconConfigPresent
    signing_config_present = [bool]$signingConfigPresent
    unsigned_installer_expected = [bool](-not $signingConfigPresent)
    build_preview_ok = [bool]$buildPreviewOk
    local_build_attempted = [bool]$localBuild.attempted
    local_build_ok = [bool]$localBuild.ok
    local_build_exit_code = $localBuild.exit_code
    local_build_failure_category = $localBuild.failure_category
    artifact_paths = $artifacts.artifact_paths
    artifact_count = $artifacts.artifact_count
    installer_artifact_found = [bool]$artifacts.installer_artifact_found
    portable_artifact_found = [bool]$artifacts.portable_artifact_found
    blockers = @($blockers)
    warnings = @($warnings)
    next_recommended_goal = "v0.1.0-bootstrap-alpha-desktop-rc1 installer RC packaging"
    release_created = $false
    tag_created = $false
    tag_moved = $false
    github_release_updated = $false
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
}

function Write-ReadinessReport($Result) {
  $outputPath = Join-Path $RepoRoot $OutputDir
  New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
  $jsonPath = Join-Path $outputPath "desktop-packaging-readiness.json"
  $mdPath = Join-Path $outputPath "desktop-packaging-readiness.md"

  $Result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $lines = @(
    "# Desktop Packaging Readiness",
    "",
    "- schema: skybridge.desktop_packaging_readiness.v1",
    "- status: $($Result.status)",
    "- ok: $($Result.ok)",
    "- desktop_root: $($Result.desktop_root)",
    "- framework: $($Result.framework)",
    "- build_command_detected: $($Result.build_command_detected)",
    "- package_command_detected: $($Result.package_command_detected)",
    "- app_name: $($Result.app_name)",
    "- app_identifier: $($Result.app_identifier)",
    "- app_version: $($Result.app_version)",
    "- windows_packaging_config_present: $($Result.windows_packaging_config_present)",
    "- signing_config_present: $($Result.signing_config_present)",
    "- unsigned_installer_expected: $($Result.unsigned_installer_expected)",
    "- artifact_count: $($Result.artifact_count)",
    "- installer_artifact_found: $($Result.installer_artifact_found)",
    "- portable_artifact_found: $($Result.portable_artifact_found)",
    "- release_created: false",
    "- tag_created: false",
    "- github_release_updated: false",
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
    "## Blockers",
    ""
  )
  if (@($Result.blockers).Count -eq 0) {
    $lines += "- none"
  } else {
    foreach ($item in $Result.blockers) { $lines += "- $item" }
  }
  $lines += @("", "## Warnings", "")
  if (@($Result.warnings).Count -eq 0) {
    $lines += "- none"
  } else {
    foreach ($item in $Result.warnings) { $lines += "- $item" }
  }
  $lines += @("", "## Artifacts", "")
  if (@($Result.artifact_paths).Count -eq 0) {
    $lines += "- none"
  } else {
    foreach ($item in $Result.artifact_paths) { $lines += "- $item" }
  }

  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8

  [pscustomobject]@{
    markdown = (Convert-ToRepoRelative $mdPath)
    json = (Convert-ToRepoRelative $jsonPath)
  }
}

$result = New-ReadinessResult
if ($WriteReport) {
  $paths = Write-ReadinessReport $result
  $result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue $paths.markdown -Force
  $result | Add-Member -NotePropertyName report_json_path -NotePropertyValue $paths.json -Force
}

$result | ConvertTo-Json -Depth 8
if (-not $result.ok) { exit 1 }
