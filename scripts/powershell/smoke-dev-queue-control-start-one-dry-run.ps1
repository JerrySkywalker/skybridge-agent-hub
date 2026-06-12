$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command start-one -DryRun -MaxRuntimeMinutes 60 -Json | ConvertFrom-Json
if ($json.mode -notin @("dry-run", "preview")) { throw "Expected dry-run/preview mode." }
if ($json.task_created -ne $false -or $json.worker_loop_started -ne $false) { throw "start-one dry-run/preview must not create tasks or start workers." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-start-one-dry-run"; token_printed = $false } | ConvertTo-Json -Compress
