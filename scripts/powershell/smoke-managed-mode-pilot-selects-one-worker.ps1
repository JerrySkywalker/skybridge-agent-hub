. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$preview = Invoke-ManagedModePilotJson "pilot-preview"
if ([int]$preview.request.selected_worker_count -ne 1) { throw "Expected exactly one selected worker." }
if ($preview.request.selected_routes[0].selected_worker_id -ne "laptop-zenbookduo") { throw "Unexpected selected worker." }
Write-ManagedModeSmokeResult "managed-mode-pilot-selects-one-worker"
