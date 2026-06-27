param(
  [ValidateSet("status", "inventory", "direct", "hermes", "mcp", "audit", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/tool-provider",
  [string]$HermesEnvFile = "",
  [switch]$NoVersionProbe,
  [switch]$Fixture
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.tool_provider.v1"

function Add-Finding([ref]$List, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if (-not ($List.Value -contains $Value)) {
    $List.Value = @($List.Value) + $Value
  }
}

function Convert-ToSafePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $value = $Path.Replace("\", "/")
  $repo = $RepoRoot.Replace("\", "/").TrimEnd("/")
  if ($value.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $value.Substring($repo.Length).TrimStart("/")
  }
  $homePathSafe = [Environment]::GetFolderPath("UserProfile").Replace("\", "/").TrimEnd("/")
  if (-not [string]::IsNullOrWhiteSpace($homePathSafe) -and $value.StartsWith($homePathSafe, [System.StringComparison]::OrdinalIgnoreCase)) {
    return ("%USERPROFILE%/" + $value.Substring($homePathSafe.Length).TrimStart("/"))
  }
  $localAppDataPathSafe = [Environment]::GetFolderPath("LocalApplicationData").Replace("\", "/").TrimEnd("/")
  if (-not [string]::IsNullOrWhiteSpace($localAppDataPathSafe) -and $value.StartsWith($localAppDataPathSafe, [System.StringComparison]::OrdinalIgnoreCase)) {
    return ("%LOCALAPPDATA%/" + $value.Substring($localAppDataPathSafe.Length).TrimStart("/"))
  }
  $programFiles = [Environment]::GetFolderPath("ProgramFiles").Replace("\", "/").TrimEnd("/")
  if (-not [string]::IsNullOrWhiteSpace($programFiles) -and $value.StartsWith($programFiles, [System.StringComparison]::OrdinalIgnoreCase)) {
    return ("%ProgramFiles%/" + $value.Substring($programFiles.Length).TrimStart("/"))
  }
  $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86").Replace("\", "/").TrimEnd("/")
  if (-not [string]::IsNullOrWhiteSpace($programFilesX86) -and $value.StartsWith($programFilesX86, [System.StringComparison]::OrdinalIgnoreCase)) {
    return ("%ProgramFiles(x86)%/" + $value.Substring($programFilesX86.Length).TrimStart("/"))
  }
  if ($value -match "^[A-Za-z]:/") {
    $leaf = Split-Path -Leaf $value
    return "%PATH%/$leaf"
  }
  return $value
}

function Get-SafeHostName {
  if ($Fixture) { return "host-fixture" }
  $name = [Environment]::MachineName
  if ([string]::IsNullOrWhiteSpace($name)) { return "host-unknown" }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($name.ToLowerInvariant())
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
  "host-$($hash.Substring(0, 12))"
}

function Invoke-VersionProbe([string]$CommandName, [string[]]$Arguments) {
  if ($NoVersionProbe) { return "version_probe_skipped" }
  try {
    $output = & $CommandName @Arguments 2>$null | Select-Object -First 1
    $text = (($output | Out-String).Trim() -replace "\s+", " ")
    if ([string]::IsNullOrWhiteSpace($text)) { return "version_not_reported" }
    if ($text.Length -gt 100) { return $text.Substring(0, 100) }
    return $text
  } catch {
    return "version_probe_failed"
  }
}

function New-ToolRecord {
  param(
    [string]$ToolId,
    [string]$DisplayName,
    [string]$ProviderId,
    [string]$DetectionMethod,
    [string]$ExecutablePathSafe,
    [string]$VersionSummarySafe,
    [ValidateSet("detected", "missing", "disabled", "future", "warning", "blocked")]
    [string]$Status,
    [bool]$CanPreview = $true,
    [string[]]$Warnings = @(),
    [string[]]$Blockers = @()
  )
  [pscustomobject]@{
    tool_id = $ToolId
    display_name = $DisplayName
    provider_id = $ProviderId
    detection_method = $DetectionMethod
    executable_path_safe = $ExecutablePathSafe
    version_summary_safe = $VersionSummarySafe
    status = $Status
    can_preview = [bool]$CanPreview
    can_execute_now = $false
    requires_exact_confirmation = $true
    requires_template = $true
    requires_allowlist = $true
    warnings = @($Warnings)
    blockers = @($Blockers)
  }
}

function Get-FixtureTool([string]$ToolId) {
  $fixture = @{
    powershell = @{ display = "PowerShell"; path = "%PATH%/pwsh.exe"; version = "PowerShell 7.5.0 fixture"; status = "detected" }
    git = @{ display = "Git"; path = "%PATH%/git.exe"; version = "git version 2.fixture"; status = "detected" }
    gh = @{ display = "GitHub CLI"; path = "%PATH%/gh.exe"; version = "gh version fixture"; status = "detected" }
    node = @{ display = "Node.js"; path = "%PATH%/node.exe"; version = "v22.fixture"; status = "detected" }
    pnpm = @{ display = "pnpm"; path = "%PATH%/pnpm.cmd"; version = "10.fixture"; status = "detected" }
    rust = @{ display = "Rust/Cargo"; path = "%PATH%/cargo.exe"; version = "cargo fixture"; status = "detected" }
    tauri = @{ display = "Tauri CLI"; path = "apps/desktop/package.json"; version = "@tauri-apps/cli fixture"; status = "detected" }
    codex = @{ display = "Codex CLI"; path = "%PATH%/codex.cmd"; version = "codex fixture"; status = "detected" }
    matlab = @{ display = "MATLAB"; path = ""; version = "fixture_missing"; status = "missing" }
  }
  $item = $fixture[$ToolId]
  if (-not $item) { return $null }
  $blockers = if ($item.status -eq "missing") { @("tool_missing") } else { @() }
  New-ToolRecord -ToolId $ToolId -DisplayName $item.display -ProviderId "direct-local" -DetectionMethod "fixture" -ExecutablePathSafe $item.path -VersionSummarySafe $item.version -Status $item.status -Blockers $blockers
}

function Find-CommandTool {
  param(
    [string]$ToolId,
    [string]$DisplayName,
    [string[]]$Names,
    [string[]]$VersionArguments = @("--version")
  )
  if ($Fixture) { return Get-FixtureTool $ToolId }
  foreach ($name in $Names) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
      $source = if ($cmd.Source) { $cmd.Source } elseif ($cmd.Path) { $cmd.Path } else { $name }
      return New-ToolRecord -ToolId $ToolId -DisplayName $DisplayName -ProviderId "direct-local" -DetectionMethod "command_path" -ExecutablePathSafe (Convert-ToSafePath $source) -VersionSummarySafe (Invoke-VersionProbe $name $VersionArguments) -Status "detected"
    }
  }
  New-ToolRecord -ToolId $ToolId -DisplayName $DisplayName -ProviderId "direct-local" -DetectionMethod "command_path" -ExecutablePathSafe "" -VersionSummarySafe "not_detected" -Status "missing" -Blockers @("tool_missing")
}

function Find-PnpmTool {
  if ($Fixture) { return Get-FixtureTool "pnpm" }

  $direct = Find-CommandTool -ToolId "pnpm" -DisplayName "pnpm" -Names @("pnpm", "pnpm.cmd") -VersionArguments @("--version")
  if ($direct.status -eq "detected") { return $direct }

  $corepack = Get-Command "corepack" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $corepack) { return $direct }

  $source = if ($corepack.Source) { $corepack.Source } elseif ($corepack.Path) { $corepack.Path } else { "corepack" }
  $version = "version_probe_skipped"
  if (-not $NoVersionProbe) {
    try {
      $output = & "corepack" @("pnpm", "--version") 2>$null | Select-Object -First 1
      $version = (($output | Out-String).Trim() -replace "\s+", " ")
      if ([string]::IsNullOrWhiteSpace($version)) { $version = "version_not_reported" }
      if ($version.Length -gt 100) { $version = $version.Substring(0, 100) }
    } catch {
      $version = "version_probe_failed"
    }
  }

  New-ToolRecord -ToolId "pnpm" -DisplayName "pnpm" -ProviderId "direct-local" -DetectionMethod "corepack_pnpm_version" -ExecutablePathSafe (Convert-ToSafePath $source) -VersionSummarySafe $version -Status "detected" -Warnings @("pnpm_resolved_via_corepack")
}

function Find-TauriTool {
  if ($Fixture) { return Get-FixtureTool "tauri" }
  $packagePath = Join-Path $RepoRoot "apps/desktop/package.json"
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    return New-ToolRecord -ToolId "tauri" -DisplayName "Tauri CLI" -ProviderId "direct-local" -DetectionMethod "desktop_package_json" -ExecutablePathSafe "" -VersionSummarySafe "desktop_package_missing" -Status "missing" -Blockers @("desktop_package_missing")
  }
  try {
    $package = Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json
    $version = ""
    if ($package.devDependencies.PSObject.Properties["@tauri-apps/cli"]) {
      $version = "@tauri-apps/cli " + [string]$package.devDependencies."@tauri-apps/cli"
    }
    if ([string]::IsNullOrWhiteSpace($version)) {
      return New-ToolRecord -ToolId "tauri" -DisplayName "Tauri CLI" -ProviderId "direct-local" -DetectionMethod "desktop_package_json" -ExecutablePathSafe (Convert-ToSafePath $packagePath) -VersionSummarySafe "tauri_cli_not_declared" -Status "missing" -Blockers @("tauri_cli_not_declared")
    }
    New-ToolRecord -ToolId "tauri" -DisplayName "Tauri CLI" -ProviderId "direct-local" -DetectionMethod "desktop_package_json" -ExecutablePathSafe (Convert-ToSafePath $packagePath) -VersionSummarySafe $version -Status "detected"
  } catch {
    New-ToolRecord -ToolId "tauri" -DisplayName "Tauri CLI" -ProviderId "direct-local" -DetectionMethod "desktop_package_json" -ExecutablePathSafe (Convert-ToSafePath $packagePath) -VersionSummarySafe "package_read_failed" -Status "warning" -Warnings @("package_read_failed")
  }
}

function Find-MatlabTool {
  if ($Fixture) { return Get-FixtureTool "matlab" }
  $configured = [Environment]::GetEnvironmentVariable("SKYBRIDGE_MATLAB_EXE", "Process")
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    if (Test-Path -LiteralPath $configured -PathType Leaf) {
      return New-ToolRecord -ToolId "matlab" -DisplayName "MATLAB" -ProviderId "direct-local" -DetectionMethod "SKYBRIDGE_MATLAB_EXE" -ExecutablePathSafe (Convert-ToSafePath $configured) -VersionSummarySafe "configured_path_present_no_computation" -Status "detected"
    }
    return New-ToolRecord -ToolId "matlab" -DisplayName "MATLAB" -ProviderId "direct-local" -DetectionMethod "SKYBRIDGE_MATLAB_EXE" -ExecutablePathSafe (Convert-ToSafePath $configured) -VersionSummarySafe "configured_path_missing" -Status "warning" -Warnings @("configured_matlab_path_missing")
  }
  $cmd = Get-Command "matlab" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) {
    $source = if ($cmd.Source) { $cmd.Source } elseif ($cmd.Path) { $cmd.Path } else { "matlab" }
    return New-ToolRecord -ToolId "matlab" -DisplayName "MATLAB" -ProviderId "direct-local" -DetectionMethod "command_path_no_version_probe" -ExecutablePathSafe (Convert-ToSafePath $source) -VersionSummarySafe "detected_no_version_probe_no_computation" -Status "detected"
  }
  New-ToolRecord -ToolId "matlab" -DisplayName "MATLAB" -ProviderId "direct-local" -DetectionMethod "command_path" -ExecutablePathSafe "" -VersionSummarySafe "not_detected" -Status "missing" -Blockers @("tool_missing")
}

function Get-DirectTools {
  @(
    Find-CommandTool -ToolId "powershell" -DisplayName "PowerShell" -Names @("pwsh", "powershell") -VersionArguments @("--version")
    Find-CommandTool -ToolId "git" -DisplayName "Git" -Names @("git") -VersionArguments @("--version")
    Find-CommandTool -ToolId "gh" -DisplayName "GitHub CLI" -Names @("gh") -VersionArguments @("--version")
    Find-CommandTool -ToolId "node" -DisplayName "Node.js" -Names @("node") -VersionArguments @("--version")
    Find-PnpmTool
    Find-CommandTool -ToolId "rust" -DisplayName "Rust/Cargo" -Names @("cargo", "rustc") -VersionArguments @("--version")
    Find-TauriTool
    Find-CommandTool -ToolId "codex" -DisplayName "Codex CLI" -Names @("codex.cmd", "codex.exe", "codex") -VersionArguments @("--version")
    Find-MatlabTool
  )
}

function Test-HermesConfigured {
  if ($Fixture -and $Command -eq "hermes") {
    return [pscustomobject]@{
      configured = $true
      status = "available"
      warnings = @("fixture_hermes_configured_no_prompt_generation")
      blockers = @()
      detection = "fixture"
    }
  }

  $warnings = @()
  $blockers = @()
  $hasBase = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("HERMES_API_BASE", "Process"))
  $hasKey = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("HERMES_API_KEY", "Process"))
  $hasModel = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("HERMES_MODEL", "Process"))
  $detection = "process_env"

  if (-not [string]::IsNullOrWhiteSpace($HermesEnvFile)) {
    $detection = "env_file_presence"
    if (Test-Path -LiteralPath $HermesEnvFile -PathType Leaf) {
      $text = Get-Content -Raw -LiteralPath $HermesEnvFile
      $hasBase = $hasBase -or ($text -match "HERMES_API_BASE")
      $hasKey = $hasKey -or ($text -match "HERMES_API_KEY")
      $hasModel = $hasModel -or ($text -match "HERMES_MODEL")
    } else {
      Add-Finding ([ref]$warnings) "hermes_env_file_missing"
    }
  }

  if ($hasBase -and $hasKey) {
    if (-not $hasModel) { Add-Finding ([ref]$warnings) "hermes_model_not_configured" }
    return [pscustomobject]@{ configured = $true; status = "available"; warnings = @($warnings); blockers = @($blockers); detection = $detection }
  }
  if ($hasBase -or $hasKey -or $hasModel) {
    Add-Finding ([ref]$warnings) "hermes_partial_config"
    return [pscustomobject]@{ configured = $false; status = "warning"; warnings = @($warnings); blockers = @($blockers); detection = $detection }
  }
  Add-Finding ([ref]$warnings) "hermes_not_configured"
  [pscustomobject]@{ configured = $false; status = "unavailable"; warnings = @($warnings); blockers = @($blockers); detection = $detection }
}

function Get-HermesTool {
  $status = Test-HermesConfigured
  $toolStatus = if ($status.configured) { "detected" } elseif ($status.status -eq "warning") { "warning" } else { "missing" }
  New-ToolRecord -ToolId "hermes" -DisplayName "Hermes Provider" -ProviderId "hermes-optional" -DetectionMethod $status.detection -ExecutablePathSafe "" -VersionSummarySafe $(if ($status.configured) { "configured_no_health_call" } else { "not_configured" }) -Status $toolStatus -Warnings $status.warnings -Blockers @()
}

function Get-McpTool {
  New-ToolRecord -ToolId "mcp" -DisplayName "MCP Provider" -ProviderId "mcp-disabled" -DetectionMethod "static_disabled_contract" -ExecutablePathSafe "" -VersionSummarySafe "future_disabled_no_connection_attempted" -Status "future" -CanPreview $false -Warnings @("mcp_future_disabled")
}

function New-Provider {
  param(
    [string]$ProviderId,
    [ValidateSet("direct", "hermes", "mcp", "disabled", "future")]
    [string]$ProviderType,
    [string]$DisplayName,
    [ValidateSet("available", "unavailable", "disabled", "future", "warning", "blocked")]
    [string]$Status,
    [string[]]$Tools,
    [string[]]$DefaultForTools = @(),
    [string[]]$Notes = @(),
    [string[]]$Warnings = @(),
    [string[]]$Blockers = @()
  )
  [pscustomobject]@{
    provider_id = $ProviderId
    provider_type = $ProviderType
    display_name = $DisplayName
    status = $Status
    tools = @($Tools)
    default_for_tools = @($DefaultForTools)
    execution_enabled = $false
    notes = @($Notes)
    warnings = @($Warnings)
    blockers = @($Blockers)
  }
}

function New-Inventory {
  $warnings = @()
  $blockers = @()
  $directTools = @(Get-DirectTools)
  $hermesStatus = Test-HermesConfigured
  $hermesTool = Get-HermesTool
  $mcpTool = Get-McpTool
  $tools = @()

  if ($Command -eq "direct") {
    $tools = @($directTools)
  } elseif ($Command -eq "hermes") {
    $tools = @($hermesTool)
  } elseif ($Command -eq "mcp") {
    $tools = @($mcpTool)
  } else {
    $tools = @($directTools + $hermesTool + $mcpTool)
  }

  if ($Fixture) { Add-Finding ([ref]$warnings) "fixture_inventory" }
  if ($NoVersionProbe) { Add-Finding ([ref]$warnings) "version_probe_skipped" }

  $directDetected = @($directTools | Where-Object { $_.status -eq "detected" }).Count
  $directStatus = if ($directDetected -ge 3) { "available" } elseif ($directDetected -gt 0) { "warning" } else { "unavailable" }
  $providers = @(
    New-Provider -ProviderId "direct-local" -ProviderType "direct" -DisplayName "Direct Local Provider" -Status $directStatus -Tools @($directTools | ForEach-Object { $_.tool_id }) -DefaultForTools @("codex", "matlab") -Notes @("Default provider for fixed local runner paths already proven by Bootstrap Alpha work.")
    New-Provider -ProviderId "hermes-optional" -ProviderType "hermes" -DisplayName "Hermes Optional Provider" -Status $hermesStatus.status -Tools @("hermes") -DefaultForTools @() -Notes @("Optional planner, gate, notification, or provider; not mandatory tool router.") -Warnings $hermesStatus.warnings -Blockers $hermesStatus.blockers
    New-Provider -ProviderId "mcp-disabled" -ProviderType "mcp" -DisplayName "MCP Provider" -Status "future" -Tools @("mcp") -DefaultForTools @() -Notes @("Future/disabled until a later goal explicitly enables repo-local configuration.") -Warnings @("mcp_future_disabled")
    New-Provider -ProviderId "execution-disabled" -ProviderType "disabled" -DisplayName "Disabled Execution Surfaces" -Status "disabled" -Tools @("general_shell", "arbitrary_prompt", "arbitrary_matlab", "worker_loop") -DefaultForTools @() -Notes @("Documents surfaces intentionally absent from the current inventory.")
    New-Provider -ProviderId "future-provider" -ProviderType "future" -DisplayName "Future Provider Boundary" -Status "future" -Tools @() -DefaultForTools @() -Notes @("Reserved for MG352-MG359 campaign/provider work.")
  )

  [pscustomobject]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    host_os = if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } elseif ($IsMacOS) { "macOS" } else { [System.Runtime.InteropServices.RuntimeInformation]::OSDescription }
    host_name_safe = Get-SafeHostName
    project_id = "skybridge-agent-hub"
    provider_inventory = if ($Fixture) { "fixture" } else { "local_windows_read_only" }
    providers = @($providers)
    tools = @($tools)
    defaults = [pscustomobject]@{
      codex = "direct-local"
      matlab = "direct-local"
      powershell = "direct-local"
      git = "direct-local"
      gh = "direct-local"
      node = "direct-local"
      pnpm = "direct-local"
      rust = "direct-local"
      tauri = "direct-local"
      hermes = "hermes-optional"
      mcp = "mcp-disabled"
    }
    disabled_capabilities = @(
      "general_shell_provider",
      "arbitrary_prompt_provider",
      "arbitrary_matlab_provider",
      "unbounded_worker_loop",
      "autonomous_queue_runner",
      "mcp_execution",
      "hermes_state_machine_takeover"
    )
    warnings = @($warnings)
    blockers = @($blockers)
    execution_allowed = $false
    task_created = $false
    task_claimed = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Write-InventoryReport($Result) {
  $targetRoot = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $RepoRoot $OutputDir }
  $fullTarget = [IO.Path]::GetFullPath($targetRoot)
  $agentTmp = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp"))
  if (-not $fullTarget.StartsWith($agentTmp, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp."
  }
  New-Item -ItemType Directory -Force -Path $fullTarget | Out-Null
  $jsonPath = Join-Path $fullTarget "tool-provider-inventory.json"
  $mdPath = Join-Path $fullTarget "tool-provider-inventory.md"
  $Result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $lines = @(
    "# Tool Provider Inventory",
    "",
    "- schema: $Schema",
    "- provider_inventory: $($Result.provider_inventory)",
    "- project_id: $($Result.project_id)",
    "- execution_allowed: false",
    "- task_created: false",
    "- task_claimed: false",
    "- execution_started: false",
    "- codex_run_called: false",
    "- matlab_run_called: false",
    "- hermes_run_called: false",
    "- mcp_run_called: false",
    "- worker_loop_started: false",
    "- project_control_unpaused: false",
    "- token_printed: false",
    "",
    "## Providers",
    ""
  )
  foreach ($provider in @($Result.providers)) {
    $lines += "- $($provider.provider_id): type=$($provider.provider_type), status=$($provider.status), execution_enabled=false"
  }
  $lines += @("", "## Tools", "")
  foreach ($tool in @($Result.tools)) {
    $lines += "- $($tool.tool_id): provider=$($tool.provider_id), status=$($tool.status), can_execute_now=false, path=$($tool.executable_path_safe)"
  }
  $lines += @("", "## Disabled Capabilities", "")
  foreach ($item in @($Result.disabled_capabilities)) { $lines += "- $item" }
  $lines += @("", "## Warnings", "")
  if (@($Result.warnings).Count -eq 0) { $lines += "- none" } else { foreach ($item in @($Result.warnings)) { $lines += "- $item" } }
  $lines += @("", "## Blockers", "")
  if (@($Result.blockers).Count -eq 0) { $lines += "- none" } else { foreach ($item in @($Result.blockers)) { $lines += "- $item" } }
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
  [pscustomobject]@{
    json = (Convert-ToSafePath $jsonPath)
    markdown = (Convert-ToSafePath $mdPath)
  }
}

$result = New-Inventory
if ($Command -eq "status") {
  $result.provider_inventory = if ($Fixture) { "fixture_status" } else { "status_only" }
  $result.tools = @()
  $result.warnings = @($result.warnings + "status_only_no_tool_versions")
} elseif ($Command -eq "safe-summary") {
  $result.provider_inventory = if ($Fixture) { "fixture_safe_summary" } else { "safe_summary" }
  $result.tools = @($result.tools | Select-Object -Property tool_id, display_name, provider_id, detection_method, status, can_preview, can_execute_now, requires_exact_confirmation, requires_template, requires_allowlist, warnings, blockers)
}

if ($WriteReport -or $Command -eq "audit") {
  $paths = Write-InventoryReport $result
  $result | Add-Member -NotePropertyName report_json_path -NotePropertyValue $paths.json -Force
  $result | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue $paths.markdown -Force
}

if ($Json) {
  $result | ConvertTo-Json -Depth 16
} else {
  "Tool provider inventory: $($result.provider_inventory)"
  "Direct provider: $((@($result.providers) | Where-Object { $_.provider_id -eq 'direct-local' } | Select-Object -First 1).status)"
  "Hermes provider: $((@($result.providers) | Where-Object { $_.provider_id -eq 'hermes-optional' } | Select-Object -First 1).status)"
  "MCP provider: future"
  "Execution performed: no"
  "token_printed=false"
}
