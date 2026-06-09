[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
$summary = Invoke-WorkunitQueue -Command safe-summary
if ($summary.task_executed -or $summary.worker_loop_started -or $summary.pr_created) { throw "Workunit preview must not execute, start a worker loop, or create PRs." }
Assert-TokenPrintedFalse $summary
[pscustomobject]@{ ok = $true; scenario = "bounded-queue-no-execution"; token_printed = $false } | ConvertTo-Json -Compress
