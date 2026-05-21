[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "shared-redaction.ps1")

$rules = Get-SkyBridgeSharedRedactionRules
if ($rules.source -ne "packages/event-schema/src/redaction-rules.json") {
  throw "Expected PowerShell redaction helper to load shared JSON rules, got '$($rules.source)'"
}

$samples = @(
  @{
    name = "secret keys and bearer headers"
    payload = @{
      token = "abc123"
      headers = @{ Authorization = "Bearer abc.def.ghi" }
      nested = @{ api_key = "sk-testsecret123456" }
    }
    forbidden = @("abc123", "abc.def.ghi", "sk-testsecret123456")
  },
  @{
    name = "raw agent content fields"
    payload = @{
      prompt = "raw prompt should never be stored"
      patch = "diff --git a/secret b/secret"
      stdout = "full command output"
      stderr = "full error output"
      tool_result = @{ content = "tool body with sk-toolsecret123456" }
    }
    forbidden = @("raw prompt should never be stored", "diff --git", "full command output", "full error output", "tool body")
  },
  @{
    name = "secret values inside ordinary strings"
    payload = @{
      summary = "curl -H 'Authorization: Bearer xyz.abc.def' https://example.invalid"
      note = "temporary key sk-livefixture123456789 should be replaced"
      private_key = "-----BEGIN OPENSSH PRIVATE KEY----- fixture"
    }
    forbidden = @("xyz.abc.def", "sk-livefixture123456789", "OPENSSH PRIVATE KEY")
  }
)

$psRedacted = @($samples | ForEach-Object { ConvertTo-SkyBridgeSafeValue -Value $_.payload -Rules $rules })
$psJson = $psRedacted | ConvertTo-Json -Depth 20 -Compress
foreach ($sample in $samples) {
  foreach ($forbidden in $sample.forbidden) {
    if ($psJson.Contains($forbidden)) {
      throw "PowerShell shared redaction leaked '$forbidden' from fixture '$($sample.name)'"
    }
  }
}
if ($psRedacted[0].token -ne $rules.replacement) {
  throw "PowerShell shared redaction did not replace token fields"
}
if (-not $psRedacted[1].stdout.bounded -or -not $psRedacted[1].prompt.bounded -or -not $psRedacted[1].patch.bounded) {
  throw "PowerShell shared redaction did not bound raw agent content fields"
}

$jsonObjectSample = '{"token":"json-token-secret","nested":{"Authorization":"Bearer json.header.secret"},"stdout":"json object output"}' | ConvertFrom-Json
$jsonObjectRedacted = ConvertTo-SkyBridgeSafeValue -Value $jsonObjectSample -Rules $rules
$jsonObjectRedactedText = $jsonObjectRedacted | ConvertTo-Json -Depth 20 -Compress
foreach ($forbidden in @("json-token-secret", "json.header.secret", "json object output")) {
  if ($jsonObjectRedactedText.Contains($forbidden)) {
    throw "PowerShell shared redaction leaked '$forbidden' from ConvertFrom-Json object consumption"
  }
}
if ($jsonObjectRedacted.token -ne $rules.replacement) {
  throw "PowerShell shared redaction did not replace token fields on ConvertFrom-Json objects"
}
if (-not $jsonObjectRedacted.stdout.bounded) {
  throw "PowerShell shared redaction did not bound raw output fields on ConvertFrom-Json objects"
}

$env:SKYBRIDGE_REDACTION_FIXTURES = ($samples.payload | ConvertTo-Json -Depth 20 -Compress)
$nodeOutput = @'
import { redactForTelemetry } from "./packages/event-schema/src/index.ts";

const samples = JSON.parse(process.env.SKYBRIDGE_REDACTION_FIXTURES ?? "[]");
const redacted = samples.map((sample) => redactForTelemetry(sample));
process.stdout.write(JSON.stringify(redacted));
'@ | corepack pnpm exec tsx
Remove-Item Env:\SKYBRIDGE_REDACTION_FIXTURES -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) { throw "TypeScript redaction parity sample failed" }
foreach ($sample in $samples) {
  foreach ($forbidden in $sample.forbidden) {
    if ($nodeOutput.Contains($forbidden)) {
      throw "TypeScript shared redaction leaked '$forbidden' from fixture '$($sample.name)'"
    }
  }
}

$tsRedacted = $nodeOutput | ConvertFrom-Json -AsHashtable
if ($tsRedacted[0]["token"] -ne $rules.replacement) {
  throw "TypeScript shared redaction did not replace token fields"
}
if (-not $tsRedacted[1]["stdout"]["omitted"] -or -not $tsRedacted[1]["prompt"]["omitted"] -or -not $tsRedacted[1]["patch"]["omitted"]) {
  throw "TypeScript shared redaction did not omit raw agent content fields"
}

Write-Output (@{
  ok = $true
  rulesSource = $rules.source
  replacement = $rules.replacement
  fixtureCount = $samples.Count
  powershellRawFieldsBounded = [bool]($psRedacted[1].stdout.bounded -and $psRedacted[1].prompt.bounded -and $psRedacted[1].patch.bounded)
  powershellJsonObjectRedacted = [bool]($jsonObjectRedacted.token -eq $rules.replacement -and $jsonObjectRedacted.stdout.bounded)
  typescriptRawFieldsOmitted = [bool]($tsRedacted[1]["stdout"]["omitted"] -and $tsRedacted[1]["prompt"]["omitted"] -and $tsRedacted[1]["patch"]["omitted"])
} | ConvertTo-Json -Compress)
