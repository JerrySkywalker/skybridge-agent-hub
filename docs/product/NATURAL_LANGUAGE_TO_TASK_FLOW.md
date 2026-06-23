# Natural Language To Task Flow

Bootstrap Alpha accepts natural-language intent through a chat session and
turns it into reviewed, template-bound work. The key product rule is that
natural language creates drafts, not execution.

## Flow Stages

1. Chat session starts in the Desktop client.
2. User enters natural-language input.
3. Planner produces a structured draft.
4. Planner asks a clarifying question when required fields are missing or risk
   is unclear.
5. Planner selects a known template from the Bootstrap Alpha Task Template
   Registry.
6. Planner emits a task or campaign draft with bounded inputs.
7. Desktop shows a preview with template, paths, capabilities, validation,
   evidence, and blocked actions.
8. Operator confirms or rejects the preview.
9. Server creates task and campaign records only after confirmation.
10. Worker pulls, claims, and executes the template runner.
11. Worker returns safe evidence, PR, CI, smoke, and audit summaries.
12. Operator reviews the result and decides whether to continue.

## Draft Requirements

A planner draft must include:

- selected template id;
- operator-facing summary;
- input parameters;
- allowed paths;
- blocked paths;
- required worker capabilities;
- validation rules;
- evidence schema;
- risk class;
- statement that no arbitrary shell is authorized.

MG326 implements the first local deterministic draft planner through
`scripts/powershell/skybridge-chat-to-task-draft.ps1` and the Desktop
Bootstrap Alpha Chat-to-Task panel. It returns
`skybridge.task_draft_preview.v1` only. Server-side task creation, campaign
creation, task claim, Codex execution, MATLAB execution, arbitrary shell, and
worker loop start remain disabled.

MG327 adds the first registry for template metadata:
`skybridge.task_template_registry.v1`. Known MATLAB and docs/report drafts now
take runner id, path policy, validation, risk class, and evidence schema from
the registry. The registry is queryable through
`scripts/powershell/skybridge-task-template-registry.ps1`, but it is read-only
and draft-only.

MG328 adds reviewed draft submit. Desktop can request submit preview, then
confirmed submit can create one queued task or one non-running draft campaign
only after exact operator confirmation. It keeps task claim, Codex execution,
MATLAB execution, worker loop start, arbitrary shell, project-control unpause,
raw prompt persistence, raw response persistence, and token printing disabled.

## MATLAB Parameter Sweep Example

User input:

```text
帮我用 MATLAB 跑第四章参数扫描实验，eta=2..10，h=500/700km，P=6/8/10，输出 summary 和报告。
```

Planner output:

```yaml
draft_type: campaign
campaign_template: matlab-parameter-sweep-campaign
template_id: matlab-parameter-sweep.v1
summary: Run the Chapter 4 MATLAB parameter sweep and produce a summary plus report.
inputs:
  eta_range: [2, 10]
  h_km: [500, 700]
  p_values: [6, 8, 10]
  outputs:
    - summary
    - report
allowed_paths:
  - experiments/matlab/**
  - results/skybridge/**
  - docs/experiments/**
blocked_paths:
  - .env
  - secrets/**
  - deploy/**
  - .git/**
required_capabilities:
  - windows
  - powershell
  - matlab
optional_capabilities:
  - codex
  - git
  - gh
validation:
  - confirm MATLAB is available locally
  - confirm input paths exist
  - confirm output files are under allowed paths
  - confirm no arbitrary shell command is requested
evidence_schema:
  - skybridge.matlab_sweep_evidence.v1
  - run_manifest
  - parameter_matrix
  - result_summary
  - report_path
  - audit_summary
arbitrary_shell: false
```

If the project path, MATLAB script entrypoint, or output format is ambiguous,
the planner must ask a clarifying question before emitting a confirmable draft.

token_printed=false
