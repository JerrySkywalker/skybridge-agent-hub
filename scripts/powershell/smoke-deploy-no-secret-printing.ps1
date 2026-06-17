[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$paths = @(
  (Join-Path $PSScriptRoot "..\deploy\deploy-skybridge-server.sh"),
  (Join-Path $PSScriptRoot "..\..\.github\workflows\deploy-cloud.yml")
)
$text = ($paths | ForEach-Object { Get-Content -Raw $_ }) -join "`n"
foreach ($pattern in @('echo "$TENCENT_DEPLOY_SSH_KEY"', 'echo $TENCENT_DEPLOY_SSH_KEY', "cat ~/.ssh/skybridge_deploy_key", "set -x", "env |", "printenv")) {
  if ($text -match [regex]::Escape($pattern)) { throw "Secret-printing pattern found: $pattern" }
}
if ($text -notmatch "secrets_included") { throw "Expected sanitized report marker." }
$summary = [pscustomobject]@{ ok = $true; scenario = "deploy-no-secret-printing"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
