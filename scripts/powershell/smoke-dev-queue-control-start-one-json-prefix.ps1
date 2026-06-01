$ErrorActionPreference = "Stop"
$old = $env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX
try {
  $env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX = "From https://github.com/JerrySkywalker/skybridge-agent-hub"
  $json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command start-one -DryRun -MaxRuntimeMinutes 60 -Json | ConvertFrom-Json
  if ($json.mode -ne "dry-run") { throw "Expected dry-run mode." }
  if ($json.child_parse_mode -ne "extracted_json") { throw "Expected extracted_json parse mode." }
  if ($json.child_non_json_prefix_present -ne $true) { throw "Expected non-JSON prefix metadata." }
  if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
} finally {
  $env:SKYBRIDGE_DEV_QUEUE_CONTROL_TEST_PREFIX = $old
}
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-start-one-json-prefix"; token_printed = $false } | ConvertTo-Json -Compress
