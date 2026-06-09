[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
$plan = Invoke-WorkunitQueue -Command preview
$workunit = @($plan.workunits)[0]
if ($workunit.campaign_id -ne "bootstrap-trial-201") { throw "Bootstrap campaign mapping missing." }
if ($workunit.task_id -ne "bootstrap-trial-201-task-001") { throw "Bootstrap task mapping missing." }
if ($workunit.state -ne "completed") { throw "Bootstrap workunit must be completed." }
if ($workunit.pr_url -notmatch '/pull/124$') { throw "Expected PR #124 mapping." }
if ($plan.would_create_tasks -or $plan.would_claim_tasks -or $plan.would_execute_tasks -or $plan.would_create_prs) { throw "Mapping preview must not mutate." }
Assert-TokenPrintedFalse $plan
[pscustomobject]@{ ok = $true; scenario = "workunit-bootstrap-trial-mapping"; token_printed = $false } | ConvertTo-Json -Compress
