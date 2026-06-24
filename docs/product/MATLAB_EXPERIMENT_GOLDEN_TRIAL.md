# MATLAB Experiment Golden Trial

MG333 proves the first controlled Bootstrap Alpha MATLAB execution path. It is
a synthetic runner validation, not a real research batch.

The exact live target is:

- `task_id=live-matlab-golden-task-333-001`
- `worker_id=jerry-win-local-01`
- `template_id=matlab-parameter-sweep.v1`
- `runner_id=matlab-parameter-sweep-runner.v1`

## Synthetic Grid

The fixed runner uses this tiny toolbox-free grid:

- `eta=[2,3]`
- `h_km=[500]`
- `P=[6]`

The expected combination count is `2`. The MATLAB script computes a toy metric:

```text
score = eta * P / h_km
```

This score validates the runner and evidence path only. It is not a scientific
result.

## Runner Contract

The runner contract is `skybridge.matlab_parameter_sweep_runner.v1`. Safe output
schemas are:

- `skybridge.matlab_sweep_manifest.v1`
- `skybridge.matlab_sweep_summary.v1`
- `skybridge.matlab_sweep_evidence.v1`

The fixed PowerShell runner is:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-matlab-parameter-sweep-runner.ps1 -Command preview -Json
```

`preview` does not invoke MATLAB. `fixture` writes deterministic manifest,
summary, and metrics files without MATLAB for CI. `apply` invokes MATLAB only
through `scripts/matlab/skybridge_run_parameter_sweep.m` and requires:

```text
I_UNDERSTAND_RUN_ONE_FIXED_MATLAB_SWEEP_ONLY
```

Allowed output roots are:

- `.agent/tmp/matlab-golden-trial/**`
- `results/skybridge/matlab-golden-trial/**`

The runner writes:

- `manifest.json`
- `summary.json`
- `metrics.csv`

Reports include `raw_stdout_included=false`, `raw_stderr_included=false`, and
`raw_mat_files_uploaded=false`. Raw MATLAB stdout/stderr is not included in
server evidence, docs, or final reports.

## Live Trial Flow

The live orchestrator is:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-trial.ps1 -Command status -Json
```

Create preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-trial.ps1 -Command preview-create -Json
```

Create the one task:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-trial.ps1 -Command apply-create -Confirm -ConfirmationText I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_GOLDEN_TASK_ONLY -Json
```

Run preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-trial.ps1 -Command preview-run -Json
```

Run the exact task:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-trial.ps1 -Command apply-run -Confirm -ConfirmationText I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_MATLAB_GOLDEN_TASK_ONLY -Json
```

## Live Preconditions

Live apply is allowed only when:

- MATLAB is detected locally;
- `worker_id=jerry-win-local-01` is configured and online;
- API base and worker token file are configured;
- task id is exactly `live-matlab-golden-task-333-001`;
- task was created by the MG333 helper;
- task is queued, unleased, and not old residue;
- template id and runner id match the fixed MATLAB sweep pair;
- output paths are under the allowed roots;
- exact confirmation text is supplied.

If any precondition fails, the scripts report a blocker and do not claim the
task.

## Disabled

MG333 does not enable arbitrary MATLAB command text, Codex execution, report
generation by Codex, PR creation, worker loops, run-until-hold, multiple task
execution, project-control unpause, old task requeue, notification sends, or
production infrastructure changes.

Desktop shows the MATLAB Golden Trial preview and evidence fixture state, but
live apply remains PowerShell-only.

## MG334 Recovery Note

The first live MG333 run failed safely with `matlab_exit_code=1`. MG334 adds
[MATLAB Startup Diagnostics And Recovery](MATLAB_STARTUP_DIAGNOSTICS_AND_RECOVERY.md)
before any new claim. The recovery task id is
`live-matlab-golden-task-334-001`, and the failed MG333 task must not be
requeued or reused.

## MG335 Runtime Repair Note

MG335 adds [MATLAB Local Runtime Repair](MATLAB_LOCAL_RUNTIME_REPAIR.md). It is
local diagnostic work only: no golden or recovery task is created, claimed, or
rerun. The next MATLAB task run remains deferred until the doctor can prove the
local runtime starts, checks out a license, writes summary/metrics files, and
keeps `token_printed=false`.

## MG336 Success Note

MG336 adds [MATLAB Golden Recovery Success](MATLAB_GOLDEN_RECOVERY_SUCCESS.md).
It creates and may claim only `live-matlab-golden-task-336-001` after the fixed
doctor passes. The failed MG333 and MG334 task ids remain historical evidence
and must not be requeued or reclaimed.

token_printed=false
