# Task Template Model

Bootstrap Alpha tasks are created from templates. A template constrains planner
drafts and future worker execution so natural language cannot become arbitrary
commands. MG327 makes the first templates first-class in
`docs/product/TASK_TEMPLATE_REGISTRY.md` and
`packages/event-schema/src/task-template-registry.json`.

## Template Fields

- `template_id`: stable identifier and version, for example
  `software-docs-task.v1`.
- `input_schema_summary`: structured inputs accepted by the template.
- `required_capabilities`: worker capabilities required before claim.
- `allowed_paths`: repository or workspace paths the runner may read or write.
- `blocked_paths`: paths the runner must never access or mutate.
- `risk_class`: operator-facing risk category: `low`, `medium`, or `high`.
- `validation_rules`: preflight and post-run checks required for the task.
- `runner_id`: worker runner implementation that may execute the template.
- `evidence_schema`: safe result fields returned to the server.

## First Planned Templates

MG327 registers these template ids for deterministic draft previews. MG328 may
use the same template metadata to validate confirmed queued-record submit.
Template execution remains future reviewed work.

### `software-docs-task.v1`

Documentation-only repository updates. Expected runner produces changed docs,
focused checks, PR metadata, and a safe audit summary.

### `codex-analysis-report.v1`

Read-only or docs-only Codex analysis/report tasks. Expected runner produces a
report path, source references, validation status, and no raw transcript.

### `safe-local-smoke.v1`

Local smoke validation with bounded commands from an allowlisted script. Expected
runner returns pass/fail status, command identifiers, and sanitized error
summaries.

### `matlab-parameter-sweep.v1`

Future MATLAB experiment runner for bounded parameter sweeps. Expected runner
requires explicit input ranges, allowed output paths, MATLAB capability, result
summary, report path, and audit status.

### `matlab-result-analysis.v1`

Future MATLAB result-analysis runner for summarizing existing experiment output.
Expected runner reads from allowed result paths and writes reviewable summaries
or reports.

## Freeze Boundary

MG327 documents, types, and validates the registry only. MG328 adds reviewed
queued-record submit, but still does not implement template execution, MATLAB
execution, Codex execution, task claims, worker loops, notification sends,
daemon paths, or project-control changes. Every registered template keeps
`execution_supported=false`,
`task_creation_supported=false`, `campaign_creation_supported=false`,
`claim_supported=false`, `codex_run_supported=false`,
`matlab_run_supported=false`, `arbitrary_shell_enabled=false`, and
`token_printed=false`.

token_printed=false
