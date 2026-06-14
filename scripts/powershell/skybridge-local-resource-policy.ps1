[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "preview", "safe-summary", "enforcement-gate", "run-allowance", "fixture-ac-ok", "fixture-battery-blocked", "fixture-memory-blocked", "fixture-idle-required", "fixture-network-blocked")]
  [string]$Command,
  [string]$RunId = "managed-mode-run-210",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$SkybridgeCoreEngineModules = @("Skybridge.Core.psm1", "Skybridge.ResourceGate.psm1", "Skybridge.SafetyScanner.psm1")
foreach ($module in $SkybridgeCoreEngineModules) {
  Import-Module (Join-Path $PSScriptRoot "lib/$module") -Force
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true'
}

function Get-BatterySummary {
  try {
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $battery) {
      return [pscustomobject]@{
        battery_state = "no_battery"
        battery_percent = $null
        ac_power = $true
        battery_device_present = $false
        token_printed = $false
      }
    }
    $batteryStatus = if ($null -ne $battery.BatteryStatus) { $battery.BatteryStatus } else { 0 }
    $status = [int]$batteryStatus
    $onAc = $status -in @(2, 6, 7, 8, 9, 11)
    [pscustomobject]@{
      battery_state = if ($onAc) { "ac_power" } else { "battery" }
      battery_percent = if ($null -ne $battery.EstimatedChargeRemaining) { [int]$battery.EstimatedChargeRemaining } else { $null }
      ac_power = $onAc
      battery_device_present = $true
      token_printed = $false
    }
  } catch {
    [pscustomobject]@{
      battery_state = "unknown"
      battery_percent = $null
      ac_power = $null
      battery_device_present = $true
      token_printed = $false
    }
  }
}

function Get-MemoryUsedPercent {
  try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os -or -not $os.TotalVisibleMemorySize) { return $null }
    $used = [double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory
    [int][Math]::Round(($used / [double]$os.TotalVisibleMemorySize) * 100)
  } catch {
    $null
  }
}

function Test-NetworkAvailable {
  try {
    $profiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
    if ($profiles.Count -eq 0) { return $null }
    return [bool](@($profiles | Where-Object { $_.IPv4Connectivity -eq "Internet" -or $_.IPv6Connectivity -eq "Internet" }).Count -gt 0)
  } catch {
    $null
  }
}

function New-DefaultPolicy {
  param([bool]$BatteryDevicePresent = $true)
  [pscustomobject]@{
    schema = "skybridge.local_resource_policy.v1"
    require_ac_power = [bool]$BatteryDevicePresent
    pause_on_battery = $true
    pause_below_battery_percent = 30
    require_idle = $false
    max_cpu_percent = 65
    max_memory_percent = 90
    network_required = $true
    allowed_hours = "00:00-23:59 local"
    lid_sleep_note = "No powercfg mutation; operator-managed Windows sleep/lid behavior."
    sleep_lid_behavior_note = "No powercfg mutation; operator-managed Windows sleep/lid behavior."
    policy_source = "local_script"
    enforcement_status = "enforced"
    observation_source = "local_safe_observation"
    token_printed = $false
  }
}

function New-Observation {
  param([string]$Fixture = "")
  if ($Fixture -eq "ac-ok") {
    return [pscustomobject]@{ schema = "skybridge.local_resource_observation.v1"; observation_source = "fixture"; battery_state = "ac_power"; battery_percent = 95; ac_power = $true; battery_device_present = $true; memory_used_percent = 42; cpu_percent = $null; network_available = $true; current_local_time = (Get-Date).ToString("HH:mm"); token_printed = $false }
  }
  if ($Fixture -eq "battery-blocked") {
    return [pscustomobject]@{ schema = "skybridge.local_resource_observation.v1"; observation_source = "fixture"; battery_state = "battery"; battery_percent = 85; ac_power = $false; battery_device_present = $true; memory_used_percent = 42; cpu_percent = $null; network_available = $true; current_local_time = (Get-Date).ToString("HH:mm"); token_printed = $false }
  }
  if ($Fixture -eq "memory-blocked") {
    return [pscustomobject]@{ schema = "skybridge.local_resource_observation.v1"; observation_source = "fixture"; battery_state = "ac_power"; battery_percent = 95; ac_power = $true; battery_device_present = $true; memory_used_percent = 97; cpu_percent = $null; network_available = $true; current_local_time = (Get-Date).ToString("HH:mm"); token_printed = $false }
  }
  if ($Fixture -eq "idle-required") {
    return [pscustomobject]@{ schema = "skybridge.local_resource_observation.v1"; observation_source = "fixture"; battery_state = "ac_power"; battery_percent = 95; ac_power = $true; battery_device_present = $true; memory_used_percent = 42; cpu_percent = $null; network_available = $true; current_local_time = (Get-Date).ToString("HH:mm"); idle_detected = $false; token_printed = $false }
  }
  if ($Fixture -eq "network-blocked") {
    return [pscustomobject]@{ schema = "skybridge.local_resource_observation.v1"; observation_source = "fixture"; battery_state = "ac_power"; battery_percent = 95; ac_power = $true; battery_device_present = $true; memory_used_percent = 42; cpu_percent = $null; network_available = $false; current_local_time = (Get-Date).ToString("HH:mm"); token_printed = $false }
  }

  $battery = Get-BatterySummary
  [pscustomobject]@{
    schema = "skybridge.local_resource_observation.v1"
    observation_source = "local_safe_observation"
    battery_state = $battery.battery_state
    battery_percent = $battery.battery_percent
    ac_power = $battery.ac_power
    battery_device_present = $battery.battery_device_present
    memory_used_percent = Get-MemoryUsedPercent
    cpu_percent = $null
    network_available = Test-NetworkAvailable
    current_local_time = (Get-Date).ToString("HH:mm")
    token_printed = $false
  }
}

function New-Blocker {
  param([string]$Id, [string]$Summary, [ValidateSet("blocker", "warning")][string]$Severity = "blocker")
  [pscustomobject]@{
    schema = "skybridge.local_resource_blocker.v1"
    blocker_id = $Id
    severity = $Severity
    summary = $Summary
    token_printed = $false
  }
}

function Invoke-Enforcement {
  param([string]$Fixture = "", [switch]$IdleRequired)
  $observation = New-Observation -Fixture $Fixture
  $policy = New-DefaultPolicy -BatteryDevicePresent ([bool]$observation.battery_device_present)
  if ($IdleRequired) { $policy.require_idle = $true }
  $blockers = @()
  $warnings = @("cpu usage is advisory; no sampling loop is used")

  if ($policy.require_ac_power -and $observation.ac_power -ne $true) {
    $blockers += New-Blocker "ac_power_required" "AC power is required before one-at-a-time run apply."
  }
  if ($policy.pause_on_battery -and $observation.battery_state -eq "battery") {
    $blockers += New-Blocker "on_battery" "Run apply pauses while the machine is on battery."
  }
  if ($null -ne $observation.battery_percent -and $observation.battery_percent -lt $policy.pause_below_battery_percent) {
    $blockers += New-Blocker "battery_below_threshold" "Battery percent is below policy threshold."
  }
  if ($null -ne $observation.memory_used_percent -and $observation.memory_used_percent -gt $policy.max_memory_percent) {
    $blockers += New-Blocker "memory_above_threshold" "Memory usage is above policy threshold."
  }
  if ($policy.network_required -and $observation.network_available -eq $false) {
    $blockers += New-Blocker "network_unavailable" "Network is required before run apply."
  }
  if ($policy.require_idle -and $observation.PSObject.Properties.Name -contains "idle_detected" -and $observation.idle_detected -ne $true) {
    $blockers += New-Blocker "idle_required" "Idle is required by policy and was not detected."
  } elseif ($policy.require_idle) {
    $warnings += "idle detection is advisory unless fixture-provided"
  }

  $policy | Add-Member -NotePropertyName battery_state -NotePropertyValue $observation.battery_state -Force
  $policy | Add-Member -NotePropertyName battery_percent -NotePropertyValue $observation.battery_percent -Force
  $policy | Add-Member -NotePropertyName ac_power -NotePropertyValue $observation.ac_power -Force
  $policy | Add-Member -NotePropertyName memory_used_percent -NotePropertyValue $observation.memory_used_percent -Force
  $policy | Add-Member -NotePropertyName cpu_summary -NotePropertyValue "logical_processors=$([Environment]::ProcessorCount); max_cpu_percent advisory" -Force
  $policy | Add-Member -NotePropertyName blockers -NotePropertyValue @($blockers | ForEach-Object { $_.blocker_id }) -Force
  $policy | Add-Member -NotePropertyName warnings -NotePropertyValue @($warnings) -Force
  $policy | Add-Member -NotePropertyName can_run_one_at_a_time -NotePropertyValue (@($blockers).Count -eq 0) -Force

  [pscustomobject]@{
    schema = "skybridge.local_resource_policy_enforcement.v1"
    policy = $policy
    observation = $observation
    blockers = @($blockers)
    warnings = @($warnings)
    can_run_one_at_a_time = (@($blockers).Count -eq 0)
    task_claimed = $false
    task_executed = $false
    no_powercfg_mutation = $true
    admin_required = $false
    token_printed = $false
  }
}

function New-RunAllowance {
  param([string]$Fixture = "")
  $gate = Invoke-Enforcement -Fixture $Fixture
  [pscustomobject]@{
    schema = "skybridge.local_run_allowance.v1"
    run_id = $RunId
    explicit_authorization_required = $true
    resource_gate_required = $true
    can_run_one_at_a_time = [bool]$gate.can_run_one_at_a_time
    blockers = @($gate.blockers | ForEach-Object { $_.blocker_id })
    enforcement = $gate
    token_printed = $false
  }
}

$result = switch ($Command) {
  "status" { (Invoke-Enforcement).policy }
  "preview" {
    $gate = Invoke-Enforcement
    $gate | Add-Member -NotePropertyName preview_only -NotePropertyValue $false -Force
    $gate
  }
  "safe-summary" {
    [pscustomobject]@{
      ok = $true
      schema = "skybridge.local_resource_policy_safe_summary.v1"
      enforcement = Invoke-Enforcement
      summary = "Local resource policy is an enforcement gate for future one-at-a-time run allowance; it does not claim or execute tasks."
      no_powercfg_mutation = $true
      admin_required = $false
      token_printed = $false
    }
  }
  "enforcement-gate" { Invoke-Enforcement }
  "run-allowance" { New-RunAllowance }
  "fixture-ac-ok" { Invoke-Enforcement -Fixture "ac-ok" }
  "fixture-battery-blocked" { Invoke-Enforcement -Fixture "battery-blocked" }
  "fixture-memory-blocked" { Invoke-Enforcement -Fixture "memory-blocked" }
  "fixture-idle-required" { Invoke-Enforcement -Fixture "idle-required" -IdleRequired }
  "fixture-network-blocked" { Invoke-Enforcement -Fixture "network-blocked" }
}

$text = $result | ConvertTo-Json -Depth 30 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking local resource policy output detected." }
if ($Json) { $text } else { $result | Format-List }
