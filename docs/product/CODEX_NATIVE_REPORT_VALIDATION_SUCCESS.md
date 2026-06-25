# Codex Native Report Validation Success

MG339 closes the remaining Bootstrap Alpha Codex report gap: the runner must
accept a Codex-native Markdown report without using the deterministic fallback
writer.

## Background

MG337 proved the first live Codex analysis report path but failed closed after
the output path was malformed and truncated to `.agent/tmp/c`. The MG336 input
manifest, summary, and metrics files existed, but `report.md` did not persist.

MG338 repaired artifact persistence. The runner now computes
`.agent/tmp/codex-analysis-report/<task_id>/report.md`, rejects truncated or
outside paths, validates actual file existence and size, lists only existing
files, and can write a deterministic fallback report from the safe MG336
summaries. The live MG338 recovery completed with `fallback_report_used=true`
because Codex exited successfully but the native report failed validation.

## MG339 Goal

MG339 keeps the same fixed template and runner ids:

- `template_id=codex-analysis-report.v1`
- `runner_id=codex-analysis-report-runner.v1`

It uses the new exact task id only:

```text
live-codex-analysis-report-task-339-001
```

The required report path is:

```text
.agent/tmp/codex-analysis-report/live-codex-analysis-report-task-339-001/report.md
```

The expected successful evidence has:

- `codex_invoked=true`
- `codex_exit_code=0`
- `report_exists=true`
- `report_size_bytes > 0`
- `final_report_source=codex_native`
- `fallback_report_used=false`
- `native_report_valid=true`
- `validation_status=passed`
- `codex_failure_category=none`
- `changed_files` containing only the actual report path
- `token_printed=false`

## Native Validation Contract

The fixed prompt instructs Codex to return exactly one Markdown report with a
top-level heading, no conversational wrapper, no commands, no external facts,
no repository-wide inspection, no process logs, no secrets, and no PR
instructions.

The report must include:

- a statement that the MATLAB result is a synthetic runner validation and not a
  scientific conclusion;
- the three MG336 input files reviewed;
- a parameter grid and metrics summary;
- `expected_combination_count: 2`;
- `completed_count: 2`;
- `failed_count: 0`;
- a short metric interpretation;
- validation summary, limitations, and safety notes.

The runner validates that `report.md` exists, is non-empty, is under the exact
expected output directory, has a Markdown heading, states the synthetic runner
validation boundary, includes the required count metrics, avoids obvious
secret/token patterns, avoids process stream markers, and keeps
`token_printed=false`.

If native validation fails, the runner records
`native_report_validation_failure_category`,
`native_report_validation_failure_summary`, and
`native_report_validation_checks`. A deterministic fallback may still complete
the task safely, but MG339 native success is achieved only when
`final_report_source=codex_native` and `fallback_report_used=false`.

## Live Commands

Preview commands create no task and claim nothing:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-native-success.ps1 -Command status -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-native-success.ps1 -Command preview-create -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-native-success.ps1 -Command preview-run -Json
```

Task creation requires:

```text
I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_NATIVE_REPORT_TASK_ONLY
```

Task run requires:

```text
I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_CODEX_NATIVE_REPORT_TASK_ONLY
```

The orchestrator must not reuse or requeue
`live-codex-analysis-report-task-337-001` or
`live-codex-analysis-report-task-338-001`.

## Boundary

MG339 adds no new product feature. It only hardens the native Codex report path.

Still disabled:

- arbitrary prompt input;
- arbitrary shell input;
- MATLAB execution;
- PR creation;
- worker loop start;
- queue/run-until-hold execution;
- project-control unpause;
- old task requeue;
- raw Codex logs, raw prompts, process streams, credentials, cookies, tokens,
  provider headers, proxy profiles, or runtime environment details in evidence.

token_printed=false
