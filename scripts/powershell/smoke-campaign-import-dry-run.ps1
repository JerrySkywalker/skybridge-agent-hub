[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "import-dry-run" -Json:$Json
exit $LASTEXITCODE
