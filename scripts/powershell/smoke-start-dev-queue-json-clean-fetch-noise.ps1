$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\start-dev-queue-189-200.ps1" -DryRun -MaxSteps 1 -MaxTasks 1 -MaxRuntimeMinutes 60 -Json
if ($LASTEXITCODE -ne 0) { throw "start-dev-queue dry-run failed." }
if (($raw -join "`n") -match "From https://") { throw "git fetch noise leaked into JSON output." }
if (($raw -join "`n") -match "\x1b\[") { throw "JSON output must not contain ANSI escapes." }
$json = $raw | ConvertFrom-Json
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "start-dev-queue-json-clean-fetch-noise"; token_printed = $false } | ConvertTo-Json -Compress
