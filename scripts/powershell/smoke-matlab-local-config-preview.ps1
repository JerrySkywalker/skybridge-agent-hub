[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-matlab-config-preview-" + [Guid]::NewGuid().ToString("n"))
$fakeExe = Join-Path $tempRoot "matlab.exe"
$homeRoot = Join-Path $tempRoot "home"
$scriptPath = Join-Path $PSScriptRoot "skybridge-matlab-local-config.ps1"

try {
  New-Item -ItemType Directory -Force -Path $tempRoot, $homeRoot | Out-Null
  Set-Content -LiteralPath $fakeExe -Value "fixture executable placeholder" -Encoding ASCII
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -Command preview `
    -MatlabExecutable $fakeExe `
    -HomeRoot $homeRoot `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $preview = $text | ConvertFrom-Json

  if ([string]$preview.schema -ne "skybridge.matlab_local_config.v1") { throw "Unexpected local config schema." }
  if ([string]$preview.mode -ne "preview") { throw "Preview mode mismatch." }
  Assert-True $preview.ok "local config preview ok"
  Assert-True $preview.would_mutate "local config preview would_mutate"
  Assert-False $preview.did_mutate "local config preview did_mutate"
  Assert-False $preview.writes_token "local config preview writes_token"
  Assert-False $preview.writes_license_key "local config preview writes_license_key"
  Assert-False $preview.modifies_matlab_installation "local config preview modifies_matlab_installation"
  Assert-False $preview.modifies_system_path "local config preview modifies_system_path"
  Assert-False $preview.modifies_registry "local config preview modifies_registry"
  Assert-False $preview.matlab_invoked "local config preview matlab_invoked"
  Assert-False $preview.claim_created "local config preview claim_created"
  Assert-False $preview.execution_started "local config preview execution_started"
  Assert-False $preview.worker_loop_started "local config preview worker_loop_started"
  Assert-TokenPrintedFalse $preview

  if (Test-Path -LiteralPath (Join-Path $homeRoot ".skybridge\matlab.env.ps1")) {
    throw "Preview should not write matlab.env.ps1."
  }

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-local-config-preview"
    schema = $preview.schema
    did_mutate = $false
    matlab_invoked = $false
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
