[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
$summary = Invoke-WorkunitQueue -Command safe-summary
if ($summary.task_created -or $summary.task_claimed) { throw "Workunit preview must not create or claim tasks." }
Assert-TokenPrintedFalse $summary
[pscustomobject]@{ ok = $true; scenario = "bounded-queue-no-task-claim"; token_printed = $false } | ConvertTo-Json -Compress
