# MATLAB Startup Diagnostics And Recovery

Mega Goal 334 recovers from the MG333 live MATLAB golden trial failure. MG333
failed safely with `matlab_exit_code=1`: the task was claimed once, started
once, failed with sanitized server evidence, and did not include raw stdout or
stderr. MG334 adds startup diagnostics before any recovery claim.

## Doctor Flow

The doctor script is:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-matlab-doctor.ps1 -Command preview -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-matlab-doctor.ps1 -Command apply -Confirm -ConfirmationText I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY -Json
```

Preview is read-only and does not invoke MATLAB. Apply uses only the fixed
startup diagnostic script `scripts/matlab/skybridge_matlab_startup_doctor.m`.
It checks executable discovery, startup, batch support, fixed script visibility,
output write access, license/startup status, and a tiny no-toolbox calculation.

The doctor returns `skybridge.matlab_doctor.v1` with safe fields only. It never
prints worker tokens and never includes raw stdout or stderr.

## Recovery Task

The recovery task is deterministic:

- task id: `live-matlab-golden-task-334-001`
- previous failed task id: `live-matlab-golden-task-333-001`
- worker id: `jerry-win-local-01`
- template id: `matlab-parameter-sweep.v1`
- runner id: `matlab-parameter-sweep-runner.v1`

Runbook:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-recovery.ps1 -Command doctor-preview -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-recovery.ps1 -Command preview-create -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-recovery.ps1 -Command preview-run -Json
```

Create requires:

```text
I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_RECOVERY_TASK_ONLY
```

Run requires:

```text
I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_MATLAB_RECOVERY_TASK_ONLY
```

The live apply path runs doctor apply before claiming. If the doctor fails,
the recovery task is not claimed.

## Evidence Accuracy

Future failed MATLAB evidence reports:

- `changed_files`: actual manifest, summary, or metrics files that exist;
- `existing_outputs`: the same existing output set;
- `expected_outputs_missing`: expected files that were not produced;
- `failure_category`: sanitized startup, license, batch, timeout, or output
  classification.

Server evidence must not list nonexistent files as changed files.

## Disabled In MG334

- no arbitrary MATLAB command text;
- no user-provided shell;
- no Codex execution;
- no worker loop;
- no PR creation;
- no project_control unpause;
- no reuse or requeue of `live-matlab-golden-task-333-001`;
- no token printing.

If MATLAB remains unavailable due to license, startup, or environment failure,
MG334 fails closed with a sanitized blocker and keeps `token_printed=false`.
