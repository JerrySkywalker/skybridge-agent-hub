. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
$matrix = Invoke-BoincManagerJson "action-matrix"
$startAll = @($matrix.disabled | Where-Object { $_.action -eq "start_all" })
if ($startAll.Count -ne 1 -or $startAll[0].enabled -ne $false) { throw "start_all must be disabled." }
Write-SmokeResult "boinc-manager-no-start-all"
