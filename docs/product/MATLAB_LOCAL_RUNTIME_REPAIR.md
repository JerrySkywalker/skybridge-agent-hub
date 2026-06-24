# MATLAB Local Runtime Repair

MG335 narrows the MATLAB work back to local runtime readiness. MG333 proved the
fixed MATLAB golden-trial path could fail safely, and MG334 added recovery
diagnostics. MG335 does not create or claim a task. It improves the fixed doctor
so the operator can tell whether local MATLAB is actually usable for the later
recovery run.

## Safe Detection

`skybridge-matlab-doctor.ps1` resolves MATLAB in this order:

- explicit `-MatlabExecutable`;
- `SKYBRIDGE_MATLAB_EXE`;
- `$HOME\.skybridge\matlab.env.ps1`;
- `matlab` on `PATH`;
- common Windows install paths such as `C:\Program Files\MATLAB\*\bin\matlab.exe`.

The doctor does not write machine `PATH`, read or write license keys, edit the
registry, or modify the MATLAB installation. It writes diagnostic outputs only
under `.agent/tmp/matlab-doctor/**` unless an allowed temp output directory is
provided.

## Optional User Config

The local user-level config helper is:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-matlab-local-config.ps1 -Command preview -MatlabExecutable "C:\Program Files\MATLAB\R2025b\bin\matlab.exe" -Json
```

Apply requires the exact confirmation:

```text
I_UNDERSTAND_CONFIGURE_LOCAL_MATLAB_EXECUTABLE_ONLY
```

Confirmed apply may write only `$HOME\.skybridge\matlab.env.ps1` with:

- `SKYBRIDGE_MATLAB_EXE`;
- `SKYBRIDGE_MATLAB_RUN_MODE`.

It must not write tokens, license keys, system `PATH`, registry entries, or
MATLAB installation files.

## Doctor Commands

Preview is read-only and does not invoke MATLAB:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-matlab-doctor.ps1 -Command preview -Json
```

Apply invokes only the fixed startup diagnostic path and requires:

```text
I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-matlab-doctor.ps1 -Command apply -Confirm -ConfirmationText I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY -Json
```

The fixed MATLAB script is
`scripts/matlab/skybridge_matlab_startup_doctor.m`. It performs a tiny
no-toolbox calculation and writes `doctor_summary.json` plus
`doctor_metrics.csv`.

## Failure Categories

MG335 classifies local runtime blockers without exposing raw MATLAB logs:

- `matlab_executable_not_found`;
- `matlab_batch_unsupported`;
- `matlab_license_unavailable`;
- `matlab_startup_profile_failed`;
- `matlab_working_directory_failed`;
- `matlab_output_write_failed`;
- `matlab_fixed_script_failed`;
- `unknown_matlab_startup_failure`.

The safe doctor contract is `skybridge.matlab_doctor.v1`. Reports include
booleans such as `startup_ok`, `license_status`, `batch_supported`,
`fallback_supported`, `output_write_ok`, and `minimal_compute_ok`. They also
include existing doctor output paths, a short sanitized `failure_summary`, and a
`recommended_next_action`.

## Still Disabled

MG335 does not create recovery tasks, claim tasks, run the MATLAB sweep runner,
run Codex, start a worker loop, create PRs, unpause project control, expose an
arbitrary MATLAB command box, or print raw stdout/stderr.

The next recovery task should wait until the doctor reports:

- `startup_ok=true`;
- `license_status=available`;
- `minimal_compute_ok=true`;
- `output_write_ok=true`;
- `token_printed=false`.

token_printed=false
