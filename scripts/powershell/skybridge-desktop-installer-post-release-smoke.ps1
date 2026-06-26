param(
  [ValidateSet("status", "download", "verify-checksum", "checklist", "preinstall-audit", "launch-installer", "postinstall-audit", "launch-app", "uninstall-checklist", "safe-summary")]
  [string]$Command = "status",
  [string]$ReleaseTag = "v0.1.0-bootstrap-alpha-desktop-rc1",
  [string]$ReleaseUrl = "https://github.com/JerrySkywalker/skybridge-agent-hub/releases/tag/v0.1.0-bootstrap-alpha-desktop-rc1",
  [string]$DownloadDir = ".agent/tmp/desktop-installer-post-release-smoke/downloads",
  [switch]$Json,
  [switch]$WriteReport,
  [ValidateSet("msi", "nsis")]
  [string]$InstallerType = "nsis",
  [string]$Confirm = "",
  [switch]$FixtureMode,
  [string]$InstallCompletedOperatorReport = "not_reported",
  [string]$SmartScreenObservedOperatorReport = "not_reported",
  [string]$UacObservedOperatorReport = "not_reported",
  [string]$AppLaunchOperatorReport = "not_reported",
  [string]$DesktopSafetyOperatorReport = "not_reported",
  [string]$UninstallDecision = "not_reported"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot

$Schema = "skybridge.desktop_installer_post_release_smoke.v1"
$ReportRoot = Join-Path $RepoRoot ".agent/tmp/desktop-installer-post-release-smoke"
$DownloadRoot = Join-Path $RepoRoot $DownloadDir
$ExpectedInstallerConfirm = "I_UNDERSTAND_OPEN_UNSIGNED_INSTALLER_UI_MANUAL_STEPS_REQUIRED"
$ExpectedLaunchConfirm = "I_UNDERSTAND_LAUNCH_DESKTOP_APP_FOR_MANUAL_SMOKE_ONLY"
$ExpectedUninstallConfirm = "I_UNDERSTAND_MANUAL_UNINSTALL_CHECKLIST_ONLY"

$ExpectedAssets = @(
  [pscustomobject]@{
    name = "SkyBridge.Desktop_0.1.0_x64_en-US.msi"
    type = "msi"
    sha256 = "2a19f5b93c104bce508560c6c888287c1df6c8204fd6b47b8d43cc4efcb98352"
    size = 3186688
    executable = $true
  },
  [pscustomobject]@{
    name = "SkyBridge.Desktop_0.1.0_x64-setup.exe"
    type = "nsis"
    sha256 = "35cbd415e621828d8263546e4b69f5691c7fb542e5e0064785239cbbebb9fc71"
    size = 2154253
    executable = $true
  },
  [pscustomobject]@{
    name = "SHA256SUMS.txt"
    type = "checksum"
    sha256 = ""
    size = 0
    executable = $false
  },
  [pscustomobject]@{
    name = "manifest.json"
    type = "manifest"
    sha256 = ""
    size = 0
    executable = $false
  }
)

function Convert-ToRepoRelative([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
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

function Assert-UnderAgentTmp([string]$Path, [string]$Name) {
  $full = [System.IO.Path]::GetFullPath($Path)
  $agentTmp = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  if (-not $full.StartsWith($agentTmp, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Name must be under .agent/tmp."
  }
}

function Get-DownloadUrl([string]$AssetName) {
  $escaped = [System.Uri]::EscapeDataString($AssetName)
  return "https://github.com/JerrySkywalker/skybridge-agent-hub/releases/download/$ReleaseTag/$escaped"
}

function Get-ReleaseAssetMetadata([ref]$Warnings) {
  if ($FixtureMode) { return @{} }
  $gh = Get-Command "gh" -ErrorAction SilentlyContinue
  if ($null -eq $gh) {
    Add-Finding $Warnings "github_cli_unavailable_release_asset_metadata_skipped"
    return @{}
  }
  try {
    $release = (& gh release view $ReleaseTag --json tagName,name,url,isPrerelease,isDraft,assets,targetCommitish 2>$null | Out-String).Trim() | ConvertFrom-Json
    $map = @{}
    foreach ($asset in @($release.assets)) {
      $map[$asset.name] = $asset
    }
    return $map
  } catch {
    Add-Finding $Warnings "release_asset_metadata_unavailable"
    return @{}
  }
}

function Get-ExpectedAssetByName([string]$Name) {
  @($ExpectedAssets | Where-Object { $_.name -eq $Name } | Select-Object -First 1)[0]
}

function Read-ChecksumFile([string]$Path) {
  $map = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $map }
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -match "^\s*([a-fA-F0-9]{64})\s+\*?(.+?)\s*$") {
      $map[$matches[2]] = $matches[1].ToLowerInvariant()
    }
  }
  return $map
}

function Get-DownloadedAssetRecords([ref]$Blockers, [ref]$Warnings, [bool]$Verify) {
  $records = @()
  $metadata = Get-ReleaseAssetMetadata $Warnings
  $checksumPath = Join-Path $DownloadRoot "SHA256SUMS.txt"
  $checksumMap = Read-ChecksumFile $checksumPath

  foreach ($asset in $ExpectedAssets) {
    $path = Join-Path $DownloadRoot $asset.name
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $size = if ($exists) { (Get-Item -LiteralPath $path).Length } else { 0 }
    $sha = if ($exists) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() } else { "" }
    if ($Verify) {
      if (-not $exists) {
        Add-Finding $Blockers "asset_missing:$($asset.name)"
      } elseif ($size -le 0) {
        Add-Finding $Blockers "asset_empty:$($asset.name)"
      }
      if (-not $FixtureMode -and $asset.size -gt 0 -and $size -ne $asset.size) {
        Add-Finding $Blockers "asset_size_mismatch:$($asset.name)"
      }
      if ($metadata.ContainsKey($asset.name) -and $size -ne [int64]$metadata[$asset.name].size) {
        Add-Finding $Blockers "release_metadata_size_mismatch:$($asset.name)"
      }
      if (-not $FixtureMode -and -not [string]::IsNullOrWhiteSpace($asset.sha256) -and $sha -ne $asset.sha256) {
        Add-Finding $Blockers "sha256_mismatch:$($asset.name)"
      }
      if ($checksumMap.ContainsKey($asset.name) -and $sha -ne $checksumMap[$asset.name]) {
        Add-Finding $Blockers "sha256sums_file_mismatch:$($asset.name)"
      }
    }
    $records += [pscustomobject]@{
      name = $asset.name
      type = $asset.type
      path = if ($exists) { Convert-ToRepoRelative $path } else { "" }
      exists = [bool]$exists
      size_bytes = [int64]$size
      sha256 = $sha
      release_size_bytes = if ($metadata.ContainsKey($asset.name)) { [int64]$metadata[$asset.name].size } else { $null }
      expected_sha256 = $asset.sha256
    }
  }

  if ($Verify -and (Test-Path -LiteralPath $DownloadRoot -PathType Container)) {
    $allowedNames = @($ExpectedAssets | ForEach-Object { $_.name })
    $unexpected = @(
      Get-ChildItem -LiteralPath $DownloadRoot -File |
        Where-Object { $_.Extension -in @(".exe", ".msi") -and -not ($allowedNames -contains $_.Name) }
    )
    foreach ($file in $unexpected) {
      Add-Finding $Blockers "unexpected_executable_asset:$($file.Name)"
    }
  }

  return $records
}

function Test-ManifestAgreement([ref]$Blockers, [ref]$Warnings) {
  $manifestPath = Join-Path $DownloadRoot "manifest.json"
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Add-Finding $Blockers "manifest_missing"
    return
  }
  try {
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    foreach ($expected in @($ExpectedAssets | Where-Object { $_.executable })) {
      $artifact = @($manifest.artifacts | Where-Object { $_.file_name -eq $expected.name } | Select-Object -First 1)
      if (@($artifact).Count -eq 0) {
        Add-Finding $Warnings "manifest_asset_missing:$($expected.name)"
        continue
      }
      if (-not $FixtureMode -and $artifact[0].sha256 -ne $expected.sha256) {
        Add-Finding $Blockers "manifest_sha256_mismatch:$($expected.name)"
      }
    }
  } catch {
    Add-Finding $Blockers "manifest_unreadable"
  }
}

function Invoke-Download([ref]$Blockers, [ref]$Warnings) {
  Assert-UnderAgentTmp -Path $DownloadRoot -Name "DownloadDir"
  New-Item -ItemType Directory -Force -Path $DownloadRoot | Out-Null
  if ($FixtureMode) {
    Add-Finding $Warnings "fixture_mode_download_skipped"
    return
  }
  foreach ($asset in $ExpectedAssets) {
    $destination = Join-Path $DownloadRoot $asset.name
    $uri = Get-DownloadUrl $asset.name
    try {
      Invoke-WebRequest -Uri $uri -OutFile $destination -UseBasicParsing -ErrorAction Stop | Out-Null
    } catch {
      Add-Finding $Blockers "asset_download_failed:$($asset.name)"
    }
  }
}

function Get-SelectedInstallerPath([ref]$Blockers) {
  $asset = @($ExpectedAssets | Where-Object { $_.type -eq $InstallerType } | Select-Object -First 1)[0]
  $path = Join-Path $DownloadRoot $asset.name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Add-Finding $Blockers "selected_installer_missing:$InstallerType"
    return ""
  }
  return $path
}

function Get-PostInstallState([ref]$Warnings) {
  $localApp = [Environment]::GetFolderPath("LocalApplicationData")
  $programFiles = [Environment]::GetFolderPath("ProgramFiles")
  $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
  $startMenu = [Environment]::GetFolderPath("StartMenu")
  $commonStartMenu = [Environment]::GetFolderPath("CommonStartMenu")
  $candidateDirs = @(
    (Join-Path $localApp "SkyBridge Desktop"),
    (Join-Path $programFiles "SkyBridge Desktop"),
    (Join-Path $programFilesX86 "SkyBridge Desktop")
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  $installDirs = @($candidateDirs | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
  $exeCandidates = @()
  foreach ($dir in $installDirs) {
    $exeCandidates += @(Get-ChildItem -LiteralPath $dir -Filter "*.exe" -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "SkyBridge*" })
  }
  $shortcutRoots = @((Join-Path $startMenu "Programs"), (Join-Path $commonStartMenu "Programs")) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
  $shortcuts = @()
  foreach ($root in $shortcutRoots) {
    $shortcuts += @(Get-ChildItem -LiteralPath $root -Filter "SkyBridge*.lnk" -Recurse -File -ErrorAction SilentlyContinue)
  }
  $skybridgeProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "SkyBridge*" })
  $codexProcesses = @(Get-Process -Name "codex" -ErrorAction SilentlyContinue)
  $matlabProcesses = @(Get-Process -Name "MATLAB" -ErrorAction SilentlyContinue)
  if (@($codexProcesses).Count -gt 0) { Add-Finding $Warnings "codex_process_origin_not_attributable" }
  if (@($matlabProcesses).Count -gt 0) { Add-Finding $Warnings "matlab_process_origin_not_attributable" }

  [pscustomobject]@{
    install_directory_exists = (@($installDirs).Count -gt 0)
    install_directories = @($installDirs | ForEach-Object { Convert-ToRepoRelative $_ })
    executable_exists = (@($exeCandidates).Count -gt 0)
    executable_paths = @($exeCandidates | ForEach-Object { Convert-ToRepoRelative $_.FullName })
    start_menu_shortcut_exists = (@($shortcuts).Count -gt 0)
    start_menu_shortcuts = @($shortcuts | ForEach-Object { Convert-ToRepoRelative $_.FullName })
    app_process_running = (@($skybridgeProcesses).Count -gt 0)
    app_process_names = @($skybridgeProcesses | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
    codex_process_detected = (@($codexProcesses).Count -gt 0)
    matlab_process_detected = (@($matlabProcesses).Count -gt 0)
    service_or_daemon_discovery = "not_checked_registry_or_services"
  }
}

function Write-SmokeReport($Result) {
  New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
  $jsonPath = Join-Path $ReportRoot "post-release-install-smoke.json"
  $mdPath = Join-Path $ReportRoot "post-release-install-smoke.md"
  $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $lines = @(
    "# Desktop Installer Post-Release Smoke",
    "",
    "- schema: $Schema",
    "- ok: $($Result.ok)",
    "- status: $($Result.status)",
    "- release_tag: $($Result.release_tag)",
    "- release_url: $($Result.release_url)",
    "- selected_installer: $($Result.selected_installer)",
    "- installer_opened: $($Result.installer_opened)",
    "- checksums_verified: $($Result.checksums_verified)",
    "- install_manual_steps_required: true",
    "- app_launch_attempted: $($Result.app_launch_attempted)",
    "- uninstall_decision: $($Result.uninstall_decision)",
    "- release_created: false",
    "- release_updated: false",
    "- tag_created: false",
    "- tag_moved: false",
    "- asset_uploaded: false",
    "- silent_install_used: false",
    "- windows_security_bypass: false",
    "- task_created: false",
    "- task_claimed: false",
    "- execution_started: false",
    "- codex_run_called: false",
    "- matlab_run_called: false",
    "- worker_loop_started: false",
    "- project_control_unpaused: false",
    "- token_printed: false",
    "",
    "## Assets",
    ""
  )
  foreach ($asset in @($Result.assets_downloaded)) {
    $lines += "- $($asset.name): exists=$($asset.exists), size=$($asset.size_bytes), sha256=$($asset.sha256)"
  }
  $lines += @("", "## Blockers", "")
  if (@($Result.blockers).Count -eq 0) { $lines += "- none" } else { foreach ($item in @($Result.blockers)) { $lines += "- $item" } }
  $lines += @("", "## Warnings", "")
  if (@($Result.warnings).Count -eq 0) { $lines += "- none" } else { foreach ($item in @($Result.warnings)) { $lines += "- $item" } }
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
  [pscustomobject]@{
    json = (Convert-ToRepoRelative $jsonPath)
    markdown = (Convert-ToRepoRelative $mdPath)
  }
}

function New-SmokeResult {
  $blockers = @()
  $warnings = @()
  Assert-UnderAgentTmp -Path $DownloadRoot -Name "DownloadDir"
  Assert-UnderAgentTmp -Path $ReportRoot -Name "ReportRoot"

  if ($Command -eq "download") {
    Invoke-Download ([ref]$blockers) ([ref]$warnings)
  }

  $verifyRequested = $Command -in @("download", "verify-checksum", "preinstall-audit", "postinstall-audit")
  $assets = @(Get-DownloadedAssetRecords ([ref]$blockers) ([ref]$warnings) $verifyRequested)
  if ($verifyRequested) {
    Test-ManifestAgreement ([ref]$blockers) ([ref]$warnings)
  }

  $selectedInstaller = ""
  if ($Command -in @("preinstall-audit", "launch-installer")) {
    $selectedInstaller = Convert-ToRepoRelative (Get-SelectedInstallerPath ([ref]$blockers))
  } else {
    $selectedInstaller = $InstallerType
  }

  $installerOpened = $false
  if ($Command -eq "launch-installer") {
    if ($Confirm -ne $ExpectedInstallerConfirm) {
      Add-Finding ([ref]$blockers) "missing_exact_installer_ui_confirmation"
    } else {
      $installerPath = Get-SelectedInstallerPath ([ref]$blockers)
      if (-not [string]::IsNullOrWhiteSpace($installerPath) -and @($blockers).Count -eq 0) {
        Start-Process -FilePath $installerPath
        $installerOpened = $true
        Add-Finding ([ref]$warnings) "operator_manual_installer_steps_pending"
      }
    }
  }

  $postInstallState = $null
  $appLaunchAttempted = $false
  if ($Command -in @("postinstall-audit", "launch-app")) {
    $postInstallState = Get-PostInstallState ([ref]$warnings)
    if (-not $postInstallState.executable_exists) {
      Add-Finding ([ref]$warnings) "installed_executable_not_discovered"
    }
  }

  if ($Command -eq "launch-app") {
    if ($Confirm -ne $ExpectedLaunchConfirm) {
      Add-Finding ([ref]$blockers) "missing_exact_app_launch_confirmation"
    } elseif ($postInstallState -and @($postInstallState.executable_paths).Count -gt 0) {
      $candidateExe = $postInstallState.executable_paths[0]
      $firstExe = if ([System.IO.Path]::IsPathRooted($candidateExe)) {
        [System.IO.Path]::GetFullPath($candidateExe)
      } else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $candidateExe))
      }
      Start-Process -FilePath $firstExe
      $appLaunchAttempted = $true
      Add-Finding ([ref]$warnings) "operator_app_ui_smoke_pending"
    } else {
      Add-Finding ([ref]$blockers) "installed_app_executable_missing"
    }
  }

  if ($Command -eq "uninstall-checklist" -and $Confirm -ne $ExpectedUninstallConfirm) {
    Add-Finding ([ref]$blockers) "missing_exact_uninstall_checklist_confirmation"
  }

  if ($Command -eq "checklist") {
    Add-Finding ([ref]$warnings) "manual_operator_checkpoints_required"
  }

  $checksumsVerified = ($verifyRequested -and @($blockers | Where-Object { $_ -match "asset_|sha256|manifest|unexpected_executable" }).Count -eq 0)
  $ok = (@($blockers).Count -eq 0)
  $status = if (-not $ok) { "blocked" } elseif (@($warnings).Count -gt 0) { "warning" } else { "pass" }

  $result = [pscustomobject]@{
    schema = $Schema
    command = $Command
    ok = $ok
    status = $status
    release_tag = $ReleaseTag
    release_url = $ReleaseUrl
    download_dir = (Convert-ToRepoRelative $DownloadRoot)
    assets_downloaded = @($assets)
    checksums_verified = [bool]$checksumsVerified
    selected_installer = $selectedInstaller
    installer_opened = [bool]$installerOpened
    install_manual_steps_required = $true
    install_completed_operator_report = $InstallCompletedOperatorReport
    smartscreen_observed_operator_report = $SmartScreenObservedOperatorReport
    uac_observed_operator_report = $UacObservedOperatorReport
    postinstall_audit_status = if ($postInstallState) { "completed" } else { "not_run" }
    postinstall_audit = $postInstallState
    app_launch_attempted = [bool]$appLaunchAttempted
    app_launch_operator_report = $AppLaunchOperatorReport
    desktop_safety_operator_report = $DesktopSafetyOperatorReport
    uninstall_decision = $UninstallDecision
    warnings = @($warnings)
    blockers = @($blockers)
    report_json_path = ""
    report_markdown_path = ""
    release_created = $false
    release_updated = $false
    tag_created = $false
    tag_moved = $false
    asset_uploaded = $false
    silent_install_used = $false
    windows_security_bypass = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  }

  if ($WriteReport -or $Command -in @("download", "verify-checksum", "preinstall-audit", "postinstall-audit", "safe-summary")) {
    $paths = Write-SmokeReport $result
    $result.report_json_path = $paths.json
    $result.report_markdown_path = $paths.markdown
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $RepoRoot $result.report_json_path) -Encoding UTF8
  }

  return $result
}

$result = New-SmokeResult
$result | ConvertTo-Json -Depth 12
if (-not $result.ok) { exit 1 }
