[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-matlab-config-fixture-" + [Guid]::NewGuid().ToString("n"))
$fakeExe = Join-Path $tempRoot "matlab.exe"
$homeRoot = Join-Path $tempRoot "home"
$configPath = Join-Path $homeRoot ".skybridge\matlab.env.ps1"
$scriptPath = Join-Path $PSScriptRoot "skybridge-matlab-local-config.ps1"

try {
  New-Item -ItemType Directory -Force -Path $tempRoot, $homeRoot | Out-Null
  Set-Content -LiteralPath $fakeExe -Value "fixture executable placeholder" -Encoding ASCII

  $rawRejected = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -Command apply `
    -MatlabExecutable $fakeExe `
    -HomeRoot $homeRoot `
    -Json
  $rejectedText = ($rawRejected | Out-String).Trim()
  Assert-NoUnsafeText $rejectedText
  $rejected = $rejectedText | ConvertFrom-Json
  if ($rejected.ok -ne $false) { throw "Apply without confirmation should be rejected." }
  if ([string]$rejected.failure_category -ne "missing_exact_confirmation") { throw "Unexpected missing confirmation category." }
  Assert-False $rejected.did_mutate "rejected apply did_mutate"
  Assert-TokenPrintedFalse $rejected

  $rawApplied = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -Command apply `
    -MatlabExecutable $fakeExe `
    -RunMode fixed-fallback `
    -HomeRoot $homeRoot `
    -Confirm `
    -ConfirmationText I_UNDERSTAND_CONFIGURE_LOCAL_MATLAB_EXECUTABLE_ONLY `
    -Json
  $appliedText = ($rawApplied | Out-String).Trim()
  Assert-NoUnsafeText $appliedText
  $applied = $appliedText | ConvertFrom-Json

  if ([string]$applied.schema -ne "skybridge.matlab_local_config.v1") { throw "Unexpected local config schema." }
  Assert-True $applied.ok "local config apply ok"
  Assert-True $applied.did_mutate "local config apply did_mutate"
  Assert-False $applied.writes_token "local config apply writes_token"
  Assert-False $applied.writes_license_key "local config apply writes_license_key"
  Assert-False $applied.modifies_matlab_installation "local config apply modifies_matlab_installation"
  Assert-False $applied.modifies_system_path "local config apply modifies_system_path"
  Assert-False $applied.modifies_registry "local config apply modifies_registry"
  Assert-False $applied.matlab_invoked "local config apply matlab_invoked"
  Assert-False $applied.claim_created "local config apply claim_created"
  Assert-False $applied.execution_started "local config apply execution_started"
  Assert-False $applied.worker_loop_started "local config apply worker_loop_started"
  Assert-TokenPrintedFalse $applied

  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Expected fixture matlab.env.ps1." }
  $configText = Get-Content -Raw -LiteralPath $configPath
  Assert-NoUnsafeText $configText
  foreach ($needle in @("SKYBRIDGE_MATLAB_EXE", "SKYBRIDGE_MATLAB_RUN_MODE", "fixed-fallback")) {
    if ($configText -notmatch [regex]::Escape($needle)) { throw "Missing config marker $needle." }
  }
  foreach ($forbidden in @("TOKEN", "LICENSE_KEY", "PATH =")) {
    if ($configText -match [regex]::Escape($forbidden)) { throw "Forbidden config text $forbidden." }
  }

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-local-config-fixture"
    rejected_without_confirmation = $true
    fixture_config_written = $true
    matlab_invoked = $false
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
