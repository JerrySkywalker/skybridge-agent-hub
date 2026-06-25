# Codex Artifact Persistence Recovery

MG338 recovers the failed MG337 Codex Analysis Report golden trial by tightening
the artifact persistence contract and rerunning the report path with a new
deterministic task id.

## MG337 Failure

The MG337 live Codex task reached the fixed report runner after the MG336 input
files existed:

- `.agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json`
- `.agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json`
- `.agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv`

The task failed safely. The observed report path was truncated to
`.agent/tmp/c`, `report.md` did not exist, `changed_files=[]`, and server
evidence reported `validation_status=failed`. No raw Codex logs were included
in server evidence.

## MG338 Fix

MG338 keeps the same fixed template and runner ids:

- `template_id=codex-analysis-report.v1`
- `runner_id=codex-analysis-report-runner.v1`

It uses a new recovery task id only:

```text
live-codex-analysis-report-task-338-001
```

The runner now computes the output path from the task id instead of trusting a
free output value:

```text
.agent/tmp/codex-analysis-report/live-codex-analysis-report-task-338-001/report.md
```

The runner rejects output paths outside `.agent/tmp/codex-analysis-report/**`,
rejects suspiciously short/truncated paths, creates the output directory before
Codex invocation, and returns the full `output_report_path`,
`report_exists`, and `report_size_bytes`.

## Fallback Writer

The artifact outcome is explicit:

- If Codex exits successfully and writes `report.md`, the runner validates that
  report.
- If Codex exits successfully but `report.md` is missing, the runner writes a
  deterministic fallback Markdown report from the already-safe MG336 manifest,
  summary, and metrics files and sets `fallback_report_used=true`.
- If Codex exits successfully but `report.md` fails sanitizer validation, the
  runner replaces it with the deterministic fallback report and records
  `codex_failure_category=report_validation_failed_after_codex`.
- If Codex fails, the runner does not fake success. A partial report is reported
  accurately if it exists; otherwise `validation_status=failed`.

Validation passes only when `report.md` exists, is non-empty, is under the exact
expected directory, avoids obvious token/secret patterns, avoids raw process
stream markers, and states that the MATLAB result is a synthetic runner
validation rather than a scientific conclusion.

## Live Recovery Commands

Preview commands create no task and claim nothing:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-recovery.ps1 -Command status -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-recovery.ps1 -Command preview-create -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-recovery.ps1 -Command preview-run -Json
```

Task creation requires:

```text
I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_REPORT_RECOVERY_TASK_ONLY
```

Task run requires:

```text
I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_CODEX_REPORT_RECOVERY_TASK_ONLY
```

The recovery script must not requeue or reclaim
`live-codex-analysis-report-task-337-001`.

## Evidence

Recovery evidence uses `skybridge.codex_analysis_report_evidence.v1` and
includes:

- `task_id`, `worker_id`, `template_id`, `runner_id`;
- input paths and existence booleans;
- `output_report_path`, `report_exists`, `report_size_bytes`;
- `fallback_report_used`;
- `validation_status`;
- `changed_files` with actual existing files only;
- `codex_invoked`, `codex_exit_code`, and `codex_failure_category`;
- `raw_codex_log_included=false`;
- `raw_prompt_included=false`;
- `raw_stdout_included=false`;
- `raw_stderr_included=false`;
- `matlab_run_called=false`;
- `arbitrary_shell_enabled=false`;
- `worker_loop_started=false`;
- `pr_created=false`;
- `project_control_unpaused=false`;
- `token_printed=false`.

The server task evidence sanitizer must preserve these bounded scalar fields
and path arrays. It must still redact unsafe payloads and must not persist raw
Codex logs, raw prompts, stdout, stderr, auth material, provider headers,
proxy profiles, or process metadata dumps.

## Boundary

MG338 adds no new product feature. It closes the Bootstrap Alpha Codex artifact
persistence gap only.

## MG339 Native Follow-Up

MG338 proved the artifact path and fallback writer, but the live recovery used
`fallback_report_used=true` because the Codex-native output failed validation.
MG339 keeps the same artifact path contract and fallback safety net, then
hardens the fixed prompt, native output capture, and validation checks so
`live-codex-analysis-report-task-339-001` can complete with
`final_report_source=codex_native`, `fallback_report_used=false`,
`native_report_valid=true`, and `codex_failure_category=none`.

Still disabled:

- arbitrary prompt input;
- arbitrary shell input;
- MATLAB execution;
- PR creation;
- worker loop start;
- queue/run-until-hold execution;
- project-control unpause;
- old task requeue;
- raw Codex logs, raw prompts, process streams, auth material, or process
  metadata details in server evidence.

token_printed=false
