# Task Template Registry

MG327 makes Bootstrap Alpha task templates explicit and queryable. The
registry is the safe source of metadata that Chat-to-Task drafts, Desktop, and
future server/worker flows can reference before any reviewed submit or runner
execution exists.

## Why Templates Exist

Natural language is not executable input. A template narrows an operator intent
into a known shape with stable path policy, capability requirements,
validation, runner id, evidence schema, and disabled safety flags. A draft may
reference a template id, but MG327 does not turn that draft into a server task
or campaign.

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
  `docs/experiments/**` and `results/skybridge/**`.
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
schema, and safety flags. It does not show a run button, claim button, worker
loop button, Codex execution button, MATLAB execution button, arbitrary shell
box, or real submit path.

## Manual Commands

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command status -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command list -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command get -TemplateId matlab-parameter-sweep.v1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command validate -Json
```

## Future Goals

MG328 may add reviewed draft submit to the server. MG329 may add the first
worker template runner. Those goals must keep review-before-submit,
template-bound execution, safe evidence, and explicit operator boundaries.

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
