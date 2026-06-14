. "$PSScriptRoot\smoke-productization-common.ps1"
$ports = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "port-check")
if ($ports.schema -ne "skybridge.local_runtime_port_check.v1") { throw "schema mismatch" }
Assert-True $ports.ok "ok"
Assert-TokenPrintedFalse $ports
Complete-Smoke "local-runtime-port-check"
