Import-Module (Join-Path $PSScriptRoot "Skybridge.Core.psm1") -Force

function Invoke-SkybridgeSmokeScript {
  param([Parameter(Mandatory = $true)][string]$ScriptPath, [string[]]$Arguments = @())
  $full = Resolve-SkybridgePath $ScriptPath
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $full @Arguments
  $text = ($raw | Out-String).Trim()
  if (Test-SkybridgeUnsafeText $text) { throw "Unsafe smoke output: $ScriptPath" }
  $json = $text | ConvertFrom-Json
  Assert-SkybridgeTokenPrintedFalse $json
  $json
}

function Assert-SkybridgeTokenPrintedFalse {
  param([Parameter(Mandatory = $true)]$Value)
  if (-not (Test-SkybridgeTokenPrintedFalse $Value)) { throw "Expected token_printed=false." }
  [pscustomobject]@{ ok = $true; token_printed = $false }
}

function Assert-SkybridgeNoMutation {
  param([string[]]$Before = @(), [string[]]$After = @())
  $beforeText = ($Before | Sort-Object) -join "`n"
  $afterText = ($After | Sort-Object) -join "`n"
  if ($beforeText -ne $afterText) { throw "Mutation detected." }
  [pscustomobject]@{ ok = $true; no_mutation = $true; token_printed = $false }
}

function Skip-SkybridgeParameterizedHarness {
  param([string]$Name)
  [pscustomobject]@{ ok = $true; skipped = $true; reason = "parameterized_helper_requires_wrapper"; name = $Name; token_printed = $false }
}

function Write-SkybridgeSmokeResult {
  param([string]$Scenario, [bool]$Ok = $true)
  [pscustomobject]@{ ok = $Ok; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}

Export-ModuleMember -Function Invoke-SkybridgeSmokeScript, Assert-SkybridgeTokenPrintedFalse, Assert-SkybridgeNoMutation, Skip-SkybridgeParameterizedHarness, Write-SkybridgeSmokeResult
