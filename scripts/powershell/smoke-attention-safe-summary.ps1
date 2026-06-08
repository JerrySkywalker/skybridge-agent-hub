$ErrorActionPreference = "Stop"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-attention-fixture.ps1" -Command safe-summary -Json | ConvertFrom-Json
foreach ($required in @("attention_count", "top_blocker", "recommended_next_action", "token_printed")) {
  if (-not $result.PSObject.Properties[$required]) { throw "Safe summary missing $required." }
}
if ([int]$result.attention_count -lt 1) { throw "Expected attention_count >= 1." }
if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{
  ok = $true
  scenario = "attention-safe-summary"
  attention_count = [int]$result.attention_count
  token_printed = $false
} | ConvertTo-Json -Compress
