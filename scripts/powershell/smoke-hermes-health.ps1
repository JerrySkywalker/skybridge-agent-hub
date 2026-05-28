[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"

$result = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-health.ps1 `
  -HermesApiBase https://hermes-api.example.invalid `
  -ApiKeyEnvVar HERMES_HEALTH_SMOKE_KEY `
  -FixtureFile .\scripts\powershell\fixtures\hermes-capabilities.json `
  -Json | ConvertFrom-Json

if ($result.ok -ne $true) { throw "Expected Hermes health smoke ok=true." }
if ($result.api_base -ne "https://hermes-api.example.invalid") { throw "Expected supplied api_base." }
if ($result.platform -ne "hermes") { throw "Expected platform=hermes." }
if ($result.model -ne "hermes-fixture-model") { throw "Expected fixture model." }
if ($result.runtime.mode -ne "fixture") { throw "Expected runtime.mode=fixture." }
if ($result.runtime.tool_execution -ne "disabled") { throw "Expected disabled tool execution." }
if ($result.features.responses_api -ne $true) { throw "Expected responses_api=true." }
if ($result.features.runs -ne $false) { throw "Expected runs=false." }
if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }

$summary = [pscustomobject]@{
  ok = $true
  api_base = $result.api_base
  runtime_mode = $result.runtime.mode
  tool_execution = $result.runtime.tool_execution
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
