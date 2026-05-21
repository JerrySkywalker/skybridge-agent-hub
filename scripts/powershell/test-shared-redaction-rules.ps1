[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "shared-redaction.ps1")

$rules = Get-SkyBridgeSharedRedactionRules
if ($rules.source -ne "packages/event-schema/src/redaction-rules.json") {
  throw "Expected PowerShell redaction helper to load shared JSON rules, got '$($rules.source)'"
}

$sample = @{
  token = "abc123"
  headers = @{ Authorization = "Bearer abc.def.ghi" }
  stdout = "full command output"
  nested = @{ api_key = "sk-testsecret123456" }
}

$psRedacted = ConvertTo-SkyBridgeSafeValue -Value $sample -Rules $rules
$psJson = $psRedacted | ConvertTo-Json -Depth 20 -Compress
if ($psJson -match "abc123|abc\.def\.ghi|sk-testsecret123456|full command output") {
  throw "PowerShell shared redaction leaked a secret sample"
}
if ($psRedacted.token -ne $rules.replacement) {
  throw "PowerShell shared redaction did not replace token fields"
}
if (-not $psRedacted.stdout.bounded) {
  throw "PowerShell shared redaction did not bound stdout"
}

$nodeOutput = @'
import { redactForTelemetry } from "./packages/event-schema/src/index.ts";

const sample = {
  token: "abc123",
  headers: { Authorization: "Bearer abc.def.ghi" },
  stdout: "full command output",
  nested: { api_key: "sk-testsecret123456" }
};

const redacted = redactForTelemetry(sample);
process.stdout.write(JSON.stringify(redacted));
'@ | corepack pnpm exec tsx

if ($LASTEXITCODE -ne 0) { throw "TypeScript redaction parity sample failed" }
if ($nodeOutput -match "abc123|abc\.def\.ghi|sk-testsecret123456|full command output") {
  throw "TypeScript shared redaction leaked a secret sample"
}

$tsRedacted = $nodeOutput | ConvertFrom-Json -AsHashtable
if ($tsRedacted["token"] -ne $rules.replacement) {
  throw "TypeScript shared redaction did not replace token fields"
}
if (-not $tsRedacted["stdout"]["omitted"]) {
  throw "TypeScript shared redaction did not omit stdout"
}

Write-Output (@{
  ok = $true
  rulesSource = $rules.source
  replacement = $rules.replacement
  powershellStdoutBounded = [bool]$psRedacted.stdout.bounded
  typescriptStdoutOmitted = [bool]$tsRedacted["stdout"]["omitted"]
} | ConvertTo-Json -Compress)
