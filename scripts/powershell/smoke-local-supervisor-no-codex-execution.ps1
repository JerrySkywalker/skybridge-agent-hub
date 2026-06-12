$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$gate = Invoke-LocalSupervisorSmokeCommand -Command "no-execution-gate"
Assert-FalseProperty $gate "codex_execution_enabled"
Assert-FalseProperty $gate "arbitrary_shell_dispatch_enabled"
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-no-codex-execution"; token_printed = $false } | ConvertTo-Json -Compress
