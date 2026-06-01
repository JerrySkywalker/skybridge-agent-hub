$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json
if ($LASTEXITCODE -ne 0) { throw "control report failed." }
if (($raw -join "`n") -match "\x1b\[") { throw "JSON output must not contain ANSI escapes." }
$json = $raw | ConvertFrom-Json
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-json-output-clean"; token_printed = $false } | ConvertTo-Json -Compress
