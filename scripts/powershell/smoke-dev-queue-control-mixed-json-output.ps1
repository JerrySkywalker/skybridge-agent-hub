$ErrorActionPreference = "Stop"
$old = $env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX
try {
  $env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX = "From https://github.com/JerrySkywalker/skybridge-agent-hub"
  $json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
  if (-not $json.ok) { throw "Expected report ok." }
  if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
} finally {
  $env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX = $old
}
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-mixed-json-output"; token_printed = $false } | ConvertTo-Json -Compress
