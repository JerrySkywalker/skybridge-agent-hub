# MATLAB Golden Recovery Success

MG336 reruns the MATLAB golden path after MG335 proved the local MATLAB doctor
can start MATLAB, access a license, and complete a tiny no-toolbox diagnostic.

This goal uses a new task id and does not reuse failed MG333 or MG334 tasks.

## Fixed Live Scope

- task id: `live-matlab-golden-task-336-001`
- worker id: `jerry-win-local-01`
- template id: `matlab-parameter-sweep.v1`
- runner id: `matlab-parameter-sweep-runner.v1`
- parameter grid: `eta=[2,3]`, `h_km=[500]`, `P=[6]`
- expected combinations: `2`

The runner writes only sanitized outputs under the allowed MATLAB golden-trial
paths:

- `manifest.json`
- `summary.json`
- `metrics.csv`

## Runbook

Preview and doctor commands are safe and create no claim:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-success.ps1 -Command doctor-preview -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-success.ps1 -Command preview-create -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-success.ps1 -Command preview-run -Json
```

Doctor apply requires:

```text
I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY
```

Task creation requires:

```text
I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_SUCCESS_TASK_ONLY
```

Task run requires:

```text
I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_MATLAB_SUCCESS_TASK_ONLY
```

Apply-run refuses to claim unless the doctor precondition passes:

- `startup_ok=true`
- `license_status=available`
- `minimal_compute_ok=true`

## Evidence

Server evidence uses `skybridge.matlab_sweep_evidence.v1` and records:

- `expected_combination_count=2`
- `completed_count`
- `failed_count`
- manifest, summary, and metrics paths
- `manifest_exists`
- `summary_exists`
- `metrics_exists`
- actual `changed_files` only
- `raw_stdout_included=false`
- `raw_stderr_included=false`
- `token_printed=false`

Failure evidence also lists only actual files and reports missing expected
outputs separately.

## Still Disabled

MG336 does not enable arbitrary MATLAB command text, Codex execution, arbitrary
shell, PR creation, worker loops, project-control unpause, old task requeue, or
generic MATLAB queue execution.

token_printed=false
