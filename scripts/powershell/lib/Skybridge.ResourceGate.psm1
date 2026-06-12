Import-Module (Join-Path $PSScriptRoot "Skybridge.Core.psm1") -Force

function New-SkybridgeResourceObservation {
  param([ValidateSet("", "ac-ok", "battery-blocked", "memory-blocked", "network-blocked")][string]$Fixture = "")
  switch ($Fixture) {
    "ac-ok" { return [pscustomobject]@{ source = "fixture"; ac_power = $true; battery_percent = 95; memory_used_percent = 42; network_available = $true; token_printed = $false } }
    "battery-blocked" { return [pscustomobject]@{ source = "fixture"; ac_power = $false; battery_percent = 85; memory_used_percent = 42; network_available = $true; token_printed = $false } }
    "memory-blocked" { return [pscustomobject]@{ source = "fixture"; ac_power = $true; battery_percent = 95; memory_used_percent = 97; network_available = $true; token_printed = $false } }
    "network-blocked" { return [pscustomobject]@{ source = "fixture"; ac_power = $true; battery_percent = 95; memory_used_percent = 42; network_available = $false; token_printed = $false } }
  }
  [pscustomobject]@{ source = "local_safe_observation"; ac_power = $true; battery_percent = $null; memory_used_percent = $null; network_available = $true; token_printed = $false }
}

function Invoke-SkybridgeResourceGate {
  param([string]$RunId = "core-engine-fixture", [string]$Fixture = "")
  $obs = New-SkybridgeResourceObservation -Fixture $Fixture
  $blockers = @()
  if ($obs.ac_power -ne $true) { $blockers += "ac_power_required" }
  if ($null -ne $obs.memory_used_percent -and $obs.memory_used_percent -gt 90) { $blockers += "memory_above_threshold" }
  if ($obs.network_available -eq $false) { $blockers += "network_unavailable" }
  $warnings = @()
  if ([string]::IsNullOrWhiteSpace($Fixture)) {
    $warnings += "cpu usage is advisory; no sampling loop is used"
  }
  [pscustomobject]@{
    schema = "skybridge.local_run_allowance.v1"
    run_id = $RunId
    explicit_authorization_required = $true
    resource_gate_required = $true
    observation = $obs
    blockers = @($blockers)
    warnings = @($warnings)
    can_run_one_at_a_time = (@($blockers).Count -eq 0)
    no_powercfg_mutation = $true
    no_registry_mutation = $true
    admin_required = $false
    token_printed = $false
  }
}

Export-ModuleMember -Function New-SkybridgeResourceObservation, Invoke-SkybridgeResourceGate
