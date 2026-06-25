# Task Template Registry

MG327 makes Bootstrap Alpha task templates explicit and queryable. The
registry is the safe source of metadata that Chat-to-Task drafts, Desktop,
reviewed submit, and worker runners can reference before execution is allowed.

## Why Templates Exist

Natural language is not executable input. A template narrows an operator intent
into a known shape with stable path policy, capability requirements,
validation, runner id, evidence schema, and disabled safety flags. A draft may
reference a template id. MG327 does not turn that draft into a server task or
campaign. MG328 uses the registry as the validation source before confirmed
queued-record submit.

## Registry Contract

The shared registry is stored at
`packages/event-schema/src/task-template-registry.json` and validated by:

- `skybridge.task_template_registry.v1`
- `skybridge.task_template.v1`
- `skybridge.task_template_validation.v1`
- `skybridge.task_template_evidence_schema.v1`

Each template includes:

- `template_id`, `version`, `title`, `description`, and `category`;
- `draft_type=task` or `draft_type=campaign`;
- `risk_class=low`, `medium`, or `high`;
- required and optional capabilities;
- input schema summary;
- allowed and blocked paths;
- validation rules;
- runner id;
- evidence schema;
- output paths;
- disabled execution and creation flags.

## First Templates

- `software-docs-task.v1`: low-risk docs/report draft bounded to `docs/**` and
  `README.md`.
- `codex-analysis-report.v1`: medium-risk summarized analysis/report draft over
  `docs/experiments/**`, `results/skybridge/**`, and the MG337 temporary
  report output path `.agent/tmp/codex-analysis-report/**`.
- `safe-local-smoke.v1`: low-risk local smoke draft constrained to known smoke
  scripts and fixtures.
- `matlab-parameter-sweep.v1`: medium-risk campaign draft for future bounded
  MATLAB parameter sweeps.
- `matlab-result-analysis.v1`: medium-risk analysis draft over summarized
  MATLAB outputs.

## Relation To Chat-to-Task Drafts

The deterministic MG326 planner now uses registry metadata for known task and
campaign drafts. A generated MATLAB or docs/report draft must reference a
registry template id, runner id, path policy, validation rules, and evidence
schema. Clarifying and blocked previews remain safe planner states and do not
create tasks.

## Desktop Surface

Desktop shows the Bootstrap Alpha Task Templates panel with available templates,
risk class, capabilities, allowed paths, blocked paths, runner id, evidence
schema, and safety flags. Submit happens from the reviewed Chat-to-Task draft
surface, not directly from a template list. The template panel does not show a
run button, claim button, worker loop button, Codex execution button, MATLAB
execution button, arbitrary shell box, or automatic submit path.

## Manual Commands

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command status -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command list -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command get -TemplateId matlab-parameter-sweep.v1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command validate -Json
```

## Worker Runner Relation

MG328 adds reviewed draft submit to the server. MG329 adds the first worker
template runner for `safe-local-smoke.v1` only. Other templates remain draft or
queued-record metadata until later goals add reviewed runner support. The
registry remains the source for template id, runner id, path policy,
capabilities, validation, and evidence schema.

MG329 does not change the registry safety flags: templates still report
`execution_supported=false` and runner execution is separately gated by the
PowerShell runner contract.

MG333 uses the existing `matlab-parameter-sweep.v1` id for one exact
golden-trial task, `live-matlab-golden-task-333-001`, through the fixed
`matlab-parameter-sweep-runner.v1`. This is not a generic template execution
flip in the registry. The registry remains the metadata source, while the
MG333 PowerShell scripts enforce exact task id, tiny synthetic grid, output
path bounds, MATLAB availability, and exact confirmation.

MG337 uses the existing `codex-analysis-report.v1` id for one exact Codex
analysis report task, `live-codex-analysis-report-task-337-001`, through the
fixed `codex-analysis-report-runner.v1`. The registry now names
`skybridge.codex_analysis_report_evidence.v1` as the evidence schema, but keeps
`execution_supported=false`; the live run is authorized only by the MG337
PowerShell orchestrator and exact confirmation.

## Disabled In MG327

- `execution_supported=false`
- `task_creation_supported=false`
- `campaign_creation_supported=false`
- `claim_supported=false`
- `codex_run_supported=false`
- `matlab_run_supported=false`
- `arbitrary_shell_enabled=false`
- `token_printed=false`

No raw prompts, raw responses, logs, credentials, provider headers, cookies, or
tokens should be pasted into docs or logs.

token_printed=false
