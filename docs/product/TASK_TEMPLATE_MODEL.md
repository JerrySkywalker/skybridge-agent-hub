# Task Template Model

Bootstrap Alpha tasks are created from templates. A template constrains planner
drafts and worker execution so natural language cannot become arbitrary
commands.

## Template Fields

- `template_id`: stable identifier and version, for example
  `software-docs-task.v1`.
- `input_schema`: structured inputs accepted by the template.
- `required_capabilities`: worker capabilities required before claim.
- `allowed_paths`: repository or workspace paths the runner may read or write.
- `blocked_paths`: paths the runner must never access or mutate.
- `risk_class`: operator-facing risk category such as `docs_only`,
  `local_smoke`, `local_experiment`, or `review_required`.
- `validation_rules`: preflight and post-run checks required for the task.
- `runner_id`: worker runner implementation that may execute the template.
- `evidence_schema`: safe result fields returned to the server.

## First Planned Templates

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

This goal documents and freezes the model only. It does not implement full
template execution, MATLAB execution, Codex execution, task claims, worker
loops, notification sends, daemon paths, or project-control changes.

token_printed=false
