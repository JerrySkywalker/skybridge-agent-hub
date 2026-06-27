param(
  [ValidateSet("status", "inspect", "launch-check", "package-launch-check", "console-window-check", "process-check", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$AppPath = "",
  [int]$TimeoutSeconds = 10,
  [switch]$AllowLaunch,
  [int]$MaxAttempts = 1
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$DesktopRoot = Join-Path $RepoRoot "apps\desktop"
$TauriMainPath = Join-Path $DesktopRoot "src-tauri\src\main.rs"
$TauriLibPath = Join-Path $DesktopRoot "src-tauri\src\lib.rs"
$TauriConfigPath = Join-Path $DesktopRoot "src-tauri\tauri.conf.json"
$ReleaseExePath = Join-Path $DesktopRoot "src-tauri\target\release\skybridge-desktop.exe"
$InstalledExePath = Join-Path $env:LOCALAPPDATA "SkyBridge Desktop\skybridge-desktop.exe"
$DiagnosticsRoot = Join-Path $RepoRoot ".agent\tmp\desktop-launch-diagnostics"
$FixStagingRoot = Join-Path $RepoRoot ".agent\tmp\desktop-launch-fix-staging"
$Schema = "skybridge.desktop_launch_diagnostics.v1"

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

function Read-TextOrEmpty([string]$Path) {
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    return Get-Content -Raw -LiteralPath $Path
  }
  return ""
}

function Get-ResolvedAppPath {
  if (-not [string]::IsNullOrWhiteSpace($AppPath)) {
    if ([System.IO.Path]::IsPathRooted($AppPath)) {
      return [System.IO.Path]::GetFullPath($AppPath)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $AppPath))
  }
  if ($Command -eq "package-launch-check" -and (Test-Path -LiteralPath $ReleaseExePath -PathType Leaf)) {
    return $ReleaseExePath
  }
  if (Test-Path -LiteralPath $InstalledExePath -PathType Leaf) {
    return $InstalledExePath
  }
  return $ReleaseExePath
}

function Get-AppVersion([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
  try {
    $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    if (-not [string]::IsNullOrWhiteSpace($info.ProductVersion)) { return $info.ProductVersion }
    if (-not [string]::IsNullOrWhiteSpace($info.FileVersion)) { return $info.FileVersion }
  } catch {}
  return ""
}

function Get-ProcessSnapshot {
  $names = @("cmd", "powershell", "pwsh", "matlab", "codex")
  $snapshot = @{}
  foreach ($name in $names) {
    $snapshot[$name] = @(Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
      [pscustomobject]@{
        id = $_.Id
        name = $_.ProcessName
        has_window = ($_.MainWindowHandle -ne [IntPtr]::Zero -or -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle))
      }
    })
  }
  return $snapshot
}

function Test-NewProcessWindow($Before, [string[]]$Names) {
  $found = $false
  foreach ($name in $Names) {
    $beforeIds = @($Before[$name] | ForEach-Object { [int]$_.id })
    $current = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    foreach ($process in $current) {
      if ($beforeIds -contains $process.Id) { continue }
      if ($process.MainWindowHandle -ne [IntPtr]::Zero -or -not [string]::IsNullOrWhiteSpace($process.MainWindowTitle)) {
        $found = $true
      }
    }
  }
  return $found
}

function Test-NewProcessAny($Before, [string[]]$Names) {
  foreach ($name in $Names) {
    $beforeIds = @($Before[$name] | ForEach-Object { [int]$_.id })
    $current = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    foreach ($process in $current) {
      if ($beforeIds -notcontains $process.Id) { return $true }
    }
  }
  return $false
}

function Test-SkyBridgeServiceInstalled {
  try {
    $service = Get-Service -Name "SkyBridgeWorkerService" -ErrorAction SilentlyContinue
    return ($null -ne $service)
  } catch {
    return $false
  }
}

function Inspect-DesktopLaunchSurface([ref]$Blockers, [ref]$Warnings) {
  $mainText = Read-TextOrEmpty $TauriMainPath
  $libText = Read-TextOrEmpty $TauriLibPath
  $configText = Read-TextOrEmpty $TauriConfigPath

  if ([string]::IsNullOrWhiteSpace($mainText)) {
    Add-Finding $Blockers "tauri_main_missing"
  }
  if ([string]::IsNullOrWhiteSpace($libText)) {
    Add-Finding $Blockers "tauri_lib_missing"
  }
  if ([string]::IsNullOrWhiteSpace($configText)) {
    Add-Finding $Blockers "tauri_config_missing"
  }

  $windowsSubsystemConfigured = ($mainText -match 'cfg_attr\(not\(debug_assertions\),\s*windows_subsystem\s*=\s*"windows"\)')
  $hiddenPowerShellConfigured = (
    $libText -match 'CommandExt' -and
    $libText -match 'CREATE_NO_WINDOW' -and
    $libText -match 'creation_flags\(CREATE_NO_WINDOW\)'
  )
  $statusFailuresNonFatal = (
    $libText -match 'fn bridge_value' -and
    $libText -match 'warnings\.push\(warning\.clone\(\)\)' -and
    $libText -match 'Value::Null' -and
    $libText -match 'ok: !token_printed && !campaign_report\.is_null\(\)'
  )

  if (-not $windowsSubsystemConfigured) {
    Add-Finding $Blockers "windows_subsystem_missing"
  }
  if (-not $hiddenPowerShellConfigured) {
    Add-Finding $Blockers "visible_status_bridge_shell"
  }
  if (-not $statusFailuresNonFatal) {
    Add-Finding $Blockers "status_bridge_failure_may_be_fatal"
  }

  [pscustomobject]@{
    windows_subsystem_configured = [bool]$windowsSubsystemConfigured
    hidden_powershell_configured = [bool]$hiddenPowerShellConfigured
    status_failures_nonfatal = [bool]$statusFailuresNonFatal
  }
}

function Invoke-LaunchCheck([string]$Path, [int]$Timeout, [int]$Attempts, [ref]$Warnings, [ref]$Blockers) {
  $attempts = [Math]::Max(1, [Math]::Min(3, $Attempts))
  $timeoutClamped = [Math]::Max(5, [Math]::Min(60, $Timeout))
  $result = [pscustomobject]@{
    attempted = $false
    attempt_count = 0
    process_started = $false
    process_alive_after_timeout = $false
    process_exit_code_if_available = $null
    window_detected = $false
    window_title_detected = ""
    unexpected_console_window_detected = $false
    cmd_process_detected = $false
    powershell_process_detected = $false
    matlab_process_detected = $false
    codex_process_detected = $false
    failure_category = $null
    failure_summary = ""
  }

  if (-not $AllowLaunch) {
    Add-Finding $Warnings "launch_requires_allow_launch"
    $result.failure_category = "launch_not_allowed_without_flag"
    $result.failure_summary = "Launch diagnostics are read-only unless -AllowLaunch is provided."
    return $result
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Add-Finding $Blockers "app_missing"
    $result.failure_category = "app_missing"
    $result.failure_summary = "The app executable was not found."
    return $result
  }

  $result.attempted = $true
  for ($i = 1; $i -le $attempts; $i++) {
    $result.attempt_count = $i
    $before = Get-ProcessSnapshot
    $process = $null
    try {
      $psi = [System.Diagnostics.ProcessStartInfo]::new()
      $psi.FileName = $Path
      $psi.WorkingDirectory = Split-Path -Parent $Path
      $psi.UseShellExecute = $false
      $process = [System.Diagnostics.Process]::Start($psi)
    } catch {
      $result.failure_category = "launch_start_failed"
      $result.failure_summary = "Failed to start the app process."
      Add-Finding $Blockers "launch_start_failed"
      continue
    }

    if ($null -eq $process) {
      $result.failure_category = "launch_start_failed"
      $result.failure_summary = "The app process did not start."
      Add-Finding $Blockers "launch_start_failed"
      continue
    }

    $result.process_started = $true
    $deadline = (Get-Date).AddSeconds($timeoutClamped)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 250
      try { $process.Refresh() } catch {}
      if (-not $process.HasExited) {
        if ($process.MainWindowHandle -ne [IntPtr]::Zero -or -not [string]::IsNullOrWhiteSpace($process.MainWindowTitle)) {
          $result.window_detected = $true
          $result.window_title_detected = $process.MainWindowTitle
        }
      }
      if (Test-NewProcessWindow $before @("cmd")) { $result.cmd_process_detected = $true }
      if (Test-NewProcessWindow $before @("powershell", "pwsh")) { $result.powershell_process_detected = $true }
      if (Test-NewProcessAny $before @("matlab")) { $result.matlab_process_detected = $true }
      if (Test-NewProcessAny $before @("codex")) { $result.codex_process_detected = $true }
      if ($process.HasExited) { break }
    }

    try { $process.Refresh() } catch {}
    if ($process.HasExited) {
      $result.process_exit_code_if_available = $process.ExitCode
      $result.failure_category = "process_exited_before_timeout"
      $result.failure_summary = "The app process exited before the bounded timeout."
    } else {
      $result.process_alive_after_timeout = $true
      if (-not $result.window_detected) {
        try {
          $process.Refresh()
          if ($process.MainWindowHandle -ne [IntPtr]::Zero -or -not [string]::IsNullOrWhiteSpace($process.MainWindowTitle)) {
            $result.window_detected = $true
            $result.window_title_detected = $process.MainWindowTitle
          }
        } catch {}
      }
      try { $process.CloseMainWindow() | Out-Null } catch {}
      Start-Sleep -Milliseconds 500
      try {
        $process.Refresh()
        if (-not $process.HasExited) {
          $process.Kill()
        }
      } catch {}
    }

    $result.unexpected_console_window_detected = [bool]($result.cmd_process_detected -or $result.powershell_process_detected)
    if ($result.process_alive_after_timeout -and $result.window_detected -and -not $result.unexpected_console_window_detected -and -not $result.matlab_process_detected -and -not $result.codex_process_detected) {
      $result.failure_category = $null
      $result.failure_summary = ""
      break
    }
  }

  if ($result.unexpected_console_window_detected) {
    Add-Finding $Blockers "unexpected_console_window_detected"
    $result.failure_category = "unexpected_console_window_detected"
    $result.failure_summary = "A visible cmd or PowerShell window was detected during launch."
  }
  if ($result.matlab_process_detected) {
    Add-Finding $Blockers "matlab_process_detected"
  }
  if ($result.codex_process_detected) {
    Add-Finding $Blockers "codex_process_detected"
  }
  if ($result.attempted -and -not $result.process_alive_after_timeout) {
    Add-Finding $Blockers "process_exited_before_timeout"
  }
  if ($result.attempted -and -not $result.window_detected) {
    Add-Finding $Blockers "window_not_detected"
    if ([string]::IsNullOrWhiteSpace($result.failure_category)) {
      $result.failure_category = "window_not_detected"
      $result.failure_summary = "The app window was not detected during the bounded launch smoke."
    }
  }

  return $result
}

function Get-ArtifactType([string]$Path) {
  if ($Path -match "(?i)\.msi$") { return "msi" }
  if ($Path -match "(?i)[\\/]nsis[\\/]" -or ([IO.Path]::GetFileName($Path) -match "(?i)setup.*\.exe$")) { return "nsis" }
  if ($Path -match "(?i)\.exe$") { return "exe" }
  return "other"
}

function Stage-LaunchFixArtifacts($Result) {
  if (-not $Result.launch_attempted -or -not $Result.process_alive_after_timeout -or -not $Result.window_detected -or $Result.unexpected_console_window_detected) {
    return [pscustomobject]@{ manifest_path = ""; report_path = ""; checksum_path = ""; artifacts = @(); checksums = @() }
  }

  $bundleRoot = Join-Path $DesktopRoot "src-tauri\target\release\bundle"
  if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) {
    return [pscustomobject]@{ manifest_path = ""; report_path = ""; checksum_path = ""; artifacts = @(); checksums = @() }
  }

  $artifactRoot = Join-Path $FixStagingRoot "artifacts"
  $checksumRoot = Join-Path $FixStagingRoot "checksums"
  New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $checksumRoot | Out-Null

  $files = @(Get-ChildItem -LiteralPath $bundleRoot -Recurse -File |
    Where-Object { $_.Extension -in @(".msi", ".exe") } |
    Where-Object { (Get-ArtifactType $_.FullName) -in @("msi", "nsis") } |
    Sort-Object FullName)

  $artifacts = @()
  $checksums = @()
  $sumLines = @()
  foreach ($file in $files) {
    if ($file.Length -le 0) { continue }
    $destination = Join-Path $artifactRoot $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    $hash = Get-FileHash -LiteralPath $destination -Algorithm SHA256
    $relativeDestination = Convert-ToRepoRelative $destination
    $sumLines += "$($hash.Hash.ToLowerInvariant())  $relativeDestination"
    $artifact = [pscustomobject]@{
      file_name = $file.Name
      artifact_type = (Get-ArtifactType $file.FullName)
      source_path = (Convert-ToRepoRelative $file.FullName)
      staged_path = $relativeDestination
      size_bytes = [int64]$file.Length
      sha256 = $hash.Hash.ToLowerInvariant()
      signing_status = "unsigned"
      upload_now = $false
    }
    $artifacts += $artifact
    $checksums += [pscustomobject]@{
      file_name = $file.Name
      staged_path = $relativeDestination
      sha256 = $hash.Hash.ToLowerInvariant()
    }
  }

  $checksumPath = Join-Path $checksumRoot "SHA256SUMS.txt"
  $sumLines | Set-Content -LiteralPath $checksumPath -Encoding UTF8

  $manifest = [pscustomobject]@{
    schema = "skybridge.desktop_launch_fix_manifest.v1"
    source_commit = $Result.commit
    app_name = "SkyBridge Desktop"
    app_identifier = "space.jerryskywalker.skybridge.desktop"
    app_version = $Result.app_version
    build_ok = $true
    package_ok = $true
    launch_smoke_ok = [bool]($Result.process_alive_after_timeout -and $Result.window_detected -and -not $Result.unexpected_console_window_detected)
    unexpected_console_window_detected = [bool]$Result.unexpected_console_window_detected
    process_alive_after_timeout = [bool]$Result.process_alive_after_timeout
    window_detected = [bool]$Result.window_detected
    artifacts = @($artifacts)
    checksums = @($checksums)
    token_printed = $false
  }
  $manifestPath = Join-Path $FixStagingRoot "manifest.json"
  $reportJsonPath = Join-Path $FixStagingRoot "desktop-launch-fix-report.json"
  $reportMdPath = Join-Path $FixStagingRoot "desktop-launch-fix-report.md"
  $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
  $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportJsonPath -Encoding UTF8
  @(
    "# Desktop Launch Fix Report",
    "",
    "- schema: skybridge.desktop_launch_fix_manifest.v1",
    "- source_commit: $($manifest.source_commit)",
    "- app_version: $($manifest.app_version)",
    "- launch_smoke_ok: $($manifest.launch_smoke_ok)",
    "- unexpected_console_window_detected: $($manifest.unexpected_console_window_detected)",
    "- process_alive_after_timeout: $($manifest.process_alive_after_timeout)",
    "- window_detected: $($manifest.window_detected)",
    "- release_created: false",
    "- tag_created: false",
    "- installer_uploaded: false",
    "- task_claimed: false",
    "- codex_run_called: false",
    "- matlab_run_called: false",
    "- worker_loop_started: false",
    "- project_control_unpaused: false",
    "- token_printed: false",
    "",
    "## Artifacts",
    ""
  ) + @($artifacts | ForEach-Object { "- $($_.file_name): $($_.staged_path) ($($_.size_bytes) bytes, sha256=$($_.sha256))" }) |
    Set-Content -LiteralPath $reportMdPath -Encoding UTF8

  [pscustomobject]@{
    manifest_path = (Convert-ToRepoRelative $manifestPath)
    report_path = (Convert-ToRepoRelative $reportMdPath)
    checksum_path = (Convert-ToRepoRelative $checksumPath)
    artifacts = @($artifacts)
    checksums = @($checksums)
  }
}

function Write-DiagnosticReport($Result) {
  New-Item -ItemType Directory -Force -Path $DiagnosticsRoot | Out-Null
  $jsonPath = Join-Path $DiagnosticsRoot "desktop-launch-diagnostics.json"
  $mdPath = Join-Path $DiagnosticsRoot "desktop-launch-diagnostics.md"
  $Result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $lines = @(
    "# Desktop Launch Diagnostics",
    "",
    "- schema: $Schema",
    "- status: $($Result.status)",
    "- ok: $($Result.ok)",
    "- app_path: $($Result.app_path)",
    "- app_exists: $($Result.app_exists)",
    "- app_version: $($Result.app_version)",
    "- launch_attempted: $($Result.launch_attempted)",
    "- launch_attempt_count: $($Result.launch_attempt_count)",
    "- process_started: $($Result.process_started)",
    "- process_alive_after_timeout: $($Result.process_alive_after_timeout)",
    "- window_detected: $($Result.window_detected)",
    "- window_title_detected: $($Result.window_title_detected)",
    "- unexpected_console_window_detected: $($Result.unexpected_console_window_detected)",
    "- cmd_process_detected: $($Result.cmd_process_detected)",
    "- powershell_process_detected: $($Result.powershell_process_detected)",
    "- matlab_process_detected: $($Result.matlab_process_detected)",
    "- codex_process_detected: $($Result.codex_process_detected)",
    "- service_installed: $($Result.service_installed)",
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
    foreach ($item in @($Result.blockers)) { $lines += "- $item" }
  }
  $lines += @("", "## Warnings", "")
  if (@($Result.warnings).Count -eq 0) {
    $lines += "- none"
  } else {
    foreach ($item in @($Result.warnings)) { $lines += "- $item" }
  }
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8

  [pscustomobject]@{
    json = (Convert-ToRepoRelative $jsonPath)
    markdown = (Convert-ToRepoRelative $mdPath)
  }
}

function New-DiagnosticResult {
  $blockers = @()
  $warnings = @()
  $app = Get-ResolvedAppPath
  $inspect = Inspect-DesktopLaunchSurface ([ref]$blockers) ([ref]$warnings)
  $launchCommands = @("launch-check", "package-launch-check", "console-window-check")
  $launchResult = [pscustomobject]@{
    attempted = $false
    attempt_count = 0
    process_started = $false
    process_alive_after_timeout = $false
    process_exit_code_if_available = $null
    window_detected = $false
    window_title_detected = ""
    unexpected_console_window_detected = $false
    cmd_process_detected = $false
    powershell_process_detected = $false
    matlab_process_detected = $false
    codex_process_detected = $false
    failure_category = $null
    failure_summary = ""
  }

  if ($launchCommands -contains $Command) {
    $launchResult = Invoke-LaunchCheck -Path $app -Timeout $TimeoutSeconds -Attempts $MaxAttempts -Warnings ([ref]$warnings) -Blockers ([ref]$blockers)
  }

  $commit = ""
  try { $commit = ((& git -C $RepoRoot rev-parse HEAD 2>$null) | Out-String).Trim() } catch {}
  $ok = (@($blockers).Count -eq 0)
  $status = if (-not $ok) { "blocked" } elseif (@($warnings).Count -gt 0) { "warning" } else { "pass" }
  $result = [pscustomobject]@{
    schema = $Schema
    command = $Command
    ok = $ok
    status = $status
    commit = $commit
    app_path = (Convert-ToRepoRelative $app)
    app_exists = (Test-Path -LiteralPath $app -PathType Leaf)
    app_version = (Get-AppVersion $app)
    windows_subsystem_configured = [bool]$inspect.windows_subsystem_configured
    hidden_powershell_configured = [bool]$inspect.hidden_powershell_configured
    status_failures_nonfatal = [bool]$inspect.status_failures_nonfatal
    launch_attempted = [bool]$launchResult.attempted
    launch_attempt_count = [int]$launchResult.attempt_count
    process_started = [bool]$launchResult.process_started
    process_alive_after_timeout = [bool]$launchResult.process_alive_after_timeout
    process_exit_code_if_available = $launchResult.process_exit_code_if_available
    window_detected = [bool]$launchResult.window_detected
    window_title_detected = [string]$launchResult.window_title_detected
    unexpected_console_window_detected = [bool]$launchResult.unexpected_console_window_detected
    cmd_process_detected = [bool]$launchResult.cmd_process_detected
    powershell_process_detected = [bool]$launchResult.powershell_process_detected
    matlab_process_detected = [bool]$launchResult.matlab_process_detected
    codex_process_detected = [bool]$launchResult.codex_process_detected
    service_installed = [bool](Test-SkyBridgeServiceInstalled)
    task_claimed = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    failure_category = $launchResult.failure_category
    failure_summary = $launchResult.failure_summary
    blockers = @($blockers)
    warnings = @($warnings)
    release_created = $false
    release_updated = $false
    tag_created = $false
    tag_moved = $false
    installer_uploaded = $false
    binary_uploaded = $false
    token_printed = $false
  }

  if ($WriteReport) {
    $paths = Write-DiagnosticReport $result
    $result | Add-Member -NotePropertyName report_json_path -NotePropertyValue $paths.json -Force
    $result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue $paths.markdown -Force
  }

  if ($Command -eq "package-launch-check" -and $WriteReport -and $result.ok -and $result.launch_attempted) {
    $stage = Stage-LaunchFixArtifacts $result
    $result | Add-Member -NotePropertyName manifest_path -NotePropertyValue $stage.manifest_path -Force
    $result | Add-Member -NotePropertyName launch_fix_report_path -NotePropertyValue $stage.report_path -Force
    $result | Add-Member -NotePropertyName checksum_path -NotePropertyValue $stage.checksum_path -Force
    $result | Add-Member -NotePropertyName staged_artifacts -NotePropertyValue @($stage.artifacts) -Force
    $result | Add-Member -NotePropertyName checksums -NotePropertyValue @($stage.checksums) -Force
  }

  return $result
}

$result = New-DiagnosticResult
$result | ConvertTo-Json -Depth 10
if (-not $result.ok) { exit 1 }
