$ErrorActionPreference = "Stop"

$jsonOutput = Join-Path ".agent\tmp\campaign-reports" "smoke-campaign-report-no-secrets.json"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign.ps1" runner-report -CampaignId dev-queue-189-200 -ApiBase https://skybridge.jerryskywalker.space -OutputFile $jsonOutput -Json | ConvertFrom-Json
if (-not $result.ok) { throw "Expected runner-report ok." }
$paths = @($result.report.artifact_paths | Where-Object { $_ })
$texts = @($result | ConvertTo-Json -Depth 100)
foreach ($path in $paths) {
  if (Test-Path -LiteralPath $path -PathType Leaf) { $texts += (Get-Content -Raw -LiteralPath $path) }
}
$combined = $texts -join "`n"
$secretPattern = "(?i)(sk-[A-Za-z0-9_-]{20,}|Authorization\s*:\s*Bearer\s+\S+|-----BEGIN (RSA |OPENSSH |PRIVATE )?PRIVATE KEY-----|skybridge[_-]?worker[_-]?token\s*[:=]\s*\S+|hermes[_-]?api[_-]?key\s*[:=]\s*\S+|raw stdout|raw stderr)"
if ($combined -match $secretPattern) { throw "Report contains secret-looking or raw-output text." }
if ($combined -notmatch '"token_printed"\s*:\s*false' -and $combined -notmatch 'Token printed: false') { throw "Expected token_printed=false in report output." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-no-secrets"; token_printed = $false } | ConvertTo-Json -Compress
