[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$scriptPath = Join-Path $PSScriptRoot "start-dev-queue-189-200.ps1"
$raw = Get-Content -Raw -LiteralPath $scriptPath

if ($raw -notmatch '\[string\]\$OutputFile') { throw "Launcher is missing -OutputFile." }
if ($raw -notmatch '\$jsonReport = if \(\[string\]::IsNullOrWhiteSpace\(\$OutputFile\)\)') { throw "Launcher does not resolve OutputFile before runner execution." }
if ($raw -notmatch 'Join-Path \$OutputDir "\$CampaignId-runner-report\.json"') { throw "Launcher default JSON report path is not based on OutputDir and CampaignId." }
if ($raw -notmatch '"-OutputFile", \$jsonReport') { throw "Launcher does not pass resolved output file to run-until-hold." }
if ($raw -notmatch 'reports = @\{ json = \$jsonReport; markdown = \$markdownReport \}') { throw "Launcher result does not report resolved output paths." }

$summary = [pscustomobject]@{ ok = $true; output_file_supported = $true; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
