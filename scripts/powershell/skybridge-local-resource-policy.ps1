[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "preview", "safe-summary")]
  [string]$Command,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript'
}

function Get-BatterySummary {
  try {
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $battery) {
      return [pscustomobject]@{
        battery_state = "no_battery"
        battery_percent = $null
        ac_power = $true
        token_printed = $false
      }
    }
    $status = [int]($battery.BatteryStatus ?? 0)
    $onAc = $status -in @(2, 6, 7, 8, 9, 11)
    [pscustomobject]@{
      battery_state = if ($onAc) { "ac_power" } else { "battery" }
      battery_percent = if ($null -ne $battery.EstimatedChargeRemaining) { [int]$battery.EstimatedChargeRemaining } else { $null }
      ac_power = $onAc
      token_printed = $false
    }
  } catch {
    [pscustomobject]@{
      battery_state = "unknown"
      battery_percent = $null
      ac_power = $null
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

function Get-LocalResourcePolicy {
  $battery = Get-BatterySummary
  [pscustomobject]@{
    schema = "skybridge.local_resource_policy.v1"
    command = $Command
    require_ac_power = $true
    pause_on_battery = $true
    pause_below_battery_percent = 40
    require_idle = $false
    max_cpu_percent = 65
    max_memory_percent = 75
    network_required = $true
    allowed_hours = "00:00-23:59 local"
    sleep_lid_behavior_note = "No powercfg mutation; operator-managed Windows sleep/lid behavior."
    policy_source = "local_script"
    enforcement_status = "preview_only"
    battery_state = $battery.battery_state
    battery_percent = $battery.battery_percent
    memory_used_percent = Get-MemoryUsedPercent
    cpu_summary = "logical_processors=$([Environment]::ProcessorCount); no sampling loop"
    would_mutate_powercfg = $false
    task_claimed = $false
    task_executed = $false
    start_one_apply_available = $false
    start_queue_apply_available = $false
    start_all_present = $false
    arbitrary_shell_available = $false
    token_printed = $false
  }
}

$policy = Get-LocalResourcePolicy
$result = switch ($Command) {
  "status" { $policy }
  "preview" {
    $policy | Add-Member -NotePropertyName preview_only -NotePropertyValue $true -Force
    $policy | Add-Member -NotePropertyName blockers -NotePropertyValue @("execution_disabled_until_bounded_queue_authorization") -Force
    $policy
  }
  "safe-summary" {
    [pscustomobject]@{
      ok = $true
      schema = "skybridge.local_resource_policy_safe_summary.v1"
      policy = $policy
      summary = "Local resource policy is preview-only metadata and does not claim or execute tasks."
      no_powercfg_mutation = $true
      token_printed = $false
    }
  }
}

$text = $result | ConvertTo-Json -Depth 20 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking local resource policy output detected." }
if ($Json) { $text } else { $result | Format-List }
