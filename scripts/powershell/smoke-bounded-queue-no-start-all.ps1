[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
$script = Get-Content (Join-Path $PSScriptRoot "skybridge-workunit-queue.ps1") -Raw
if ($script -match 'ValidateSet\("[^"]*start-all' -or $script -match 'start-all\s+apply') { throw "Workunit queue script must not expose start-all." }
$summary = Invoke-WorkunitQueue -Command safe-summary
if (-not $summary.no_start_all) { throw "safe summary must declare no_start_all=true." }
Assert-TokenPrintedFalse $summary
[pscustomobject]@{ ok = $true; scenario = "bounded-queue-no-start-all"; token_printed = $false } | ConvertTo-Json -Compress
