. "$PSScriptRoot\smoke-productization-common.ps1"
$action = Invoke-JsonScript "skybridge-session-supervisor.ps1" @("-Command", "next-action")
if ($action.schema -ne "skybridge.session_supervisor_next_action.v1") { throw "schema mismatch" }
Assert-False $action.destructive_action_required "destructive_action_required"
Assert-False $action.host_mutation_required "host_mutation_required"
Assert-TokenPrintedFalse $action
Complete-Smoke "session-supervisor-next-safe-action"
