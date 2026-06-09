. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-SimulateApply")
if ($result.PSObject.Properties.Name -contains "raw_stdout") { throw "raw_stdout must not be present." }
if ($result.PSObject.Properties.Name -contains "raw_stderr") { throw "raw_stderr must not be present." }
Write-ManagedModeSmokeResult "managed-mode-pilot-no-raw-artifacts"
