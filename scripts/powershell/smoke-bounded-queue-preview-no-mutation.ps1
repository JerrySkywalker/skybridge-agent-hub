[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
$before = (git status --short | Out-String).Trim()
$plan = Invoke-WorkunitQueue -Command preview
if (-not $plan.no_mutation) { throw "Preview must declare no_mutation=true." }
foreach ($field in @("would_create_tasks", "would_claim_tasks", "would_execute_tasks", "would_create_prs", "would_start_runner")) {
  if ($plan.$field) { throw "Preview field $field must be false." }
}
Assert-CleanGitStatus -Before $before
Assert-TokenPrintedFalse $plan
[pscustomobject]@{ ok = $true; scenario = "bounded-queue-preview-no-mutation"; token_printed = $false } | ConvertTo-Json -Compress
