# Codex Analysis Report Golden Trial

MG337 proves the first controlled Codex execution path in Bootstrap Alpha. It
takes the completed MG336 MATLAB golden-trial evidence bundle and asks Codex to
produce one bounded Markdown report from safe summary files only.

This is not a general Codex task runner. It is one exact report-generation
trial with fixed inputs, fixed output path, fixed prompt template, and exact
operator confirmation.

## Fixed Live Scope

- task id: `live-codex-analysis-report-task-337-001`
- worker id: `jerry-win-local-01`
- template id: `codex-analysis-report.v1`
- runner id: `codex-analysis-report-runner.v1`
- input manifest:
  `.agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json`
- input summary:
  `.agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json`
- input metrics:
  `.agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv`
- output report:
  `.agent/tmp/codex-analysis-report/live-codex-analysis-report-task-337-001/report.md`

The report must state that the MG336 result is a synthetic runner validation,
not a scientific conclusion.

## Fixed Prompt

The runner uses
`docs/product/prompts/CODEX_ANALYSIS_REPORT_PROMPT_V1.md`. The prompt asks for
a Markdown report that summarizes the tiny MATLAB runner validation, describes
the parameter combinations and metrics, and avoids external claims.

The runner does not accept arbitrary prompt text from the task body or Desktop.
The task body may describe the reviewed goal, but the PowerShell runner builds
the final Codex input from the fixed prompt and the three allowed MG336 files.

## Commands

Preview is read-only and does not invoke Codex:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-codex-analysis-report-runner.ps1 -Command preview -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-trial.ps1 -Command preview-create -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-trial.ps1 -Command preview-run -Json
```

Task creation requires:

```text
I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_ANALYSIS_REPORT_TASK_ONLY
```

Task run requires:

```text
I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_CODEX_ANALYSIS_REPORT_TASK_ONLY
```

The fixed runner apply also requires:

```text
I_UNDERSTAND_RUN_ONE_FIXED_CODEX_ANALYSIS_REPORT_ONLY
```

## Evidence

Server evidence uses `skybridge.codex_analysis_report_evidence.v1` and records:

- input manifest, summary, and metrics paths;
- output report path and `report_exists`;
- `validation_status`;
- `codex_invoked` and `codex_exit_code`;
- `changed_files` containing the actual report file only on success;
- `raw_codex_log_included=false`;
- `raw_prompt_included=false`;
- `raw_stdout_included=false`;
- `raw_stderr_included=false`;
- `matlab_run_called=false`;
- `worker_loop_started=false`;
- `pr_created=false`;
- `token_printed=false`.

The report is validated for Markdown shape, the synthetic-runner statement, and
obvious secret/token markers before task completion.

## Still Disabled

MG337 does not enable arbitrary prompts, MATLAB execution, arbitrary shell,
repo-wide inspection, source edits, PR creation, auto-merge, worker loops,
run-until-hold, project-control unpause, old task requeue, or multiple live
task execution.

Future report workflows can build on this by adding reviewed PR generation, but
MG337 stops at one local Markdown artifact and sanitized SkyBridge evidence.

token_printed=false
