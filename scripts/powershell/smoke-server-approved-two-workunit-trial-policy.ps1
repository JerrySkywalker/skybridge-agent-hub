$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$script = Join-Path $root "scripts\powershell\skybridge-server-approved-two-workunit-trial.ps1"
$policy = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Command policy -Json | Out-String).Trim() | ConvertFrom-Json
if ($policy.schema -ne "skybridge.server_approved_two_workunit_trial_policy.v1") { throw "Wrong policy schema." }
if ($policy.max_workunits -ne 2 -or $policy.max_parallel_repo_mutations -ne 1 -or $policy.max_codex_executions_per_workunit -ne 1 -or $policy.max_task_prs_per_workunit -ne 1) { throw "Two-workunit limits mismatch." }
if ($policy.remote_execution_enabled -ne $false -or $policy.arbitrary_command_enabled -ne $false -or $policy.generic_bounded_queue_apply_enabled -ne $false) { throw "Unsafe execution flag enabled." }
[pscustomobject]@{ ok = $true; scenario = "server-approved-two-workunit-trial-policy"; token_printed = $false } | ConvertTo-Json -Compress
