# Draft Review And Submit

MG328 adds the first reviewed path from a safe Chat-to-Task draft into
server-side queued records. It does not execute work. It creates records only
after an operator preview and exact confirmation.

## Flow

1. Desktop generates a `skybridge.task_draft_preview.v1` draft.
2. Desktop shows template id, risk, capabilities, allowed paths, blocked paths,
   runner id, evidence schema, validation, and safety flags.
3. The operator requests submit preview.
4. The server validates the draft against the task template registry and the
   existing project constraints.
5. Submit preview returns `skybridge.draft_submit_preview.v1` and creates
   nothing.
6. Confirmed submit requires `confirm_submit=true` plus the exact confirmation
   text `I_UNDERSTAND_CREATE_QUEUED_DRAFT_RECORDS_ONLY_NO_EXECUTION`.
7. Confirmed submit returns `skybridge.draft_submit_result.v1`.

## Server Endpoints

- `POST /v1/drafts/submit-preview`: validates the draft and returns safe
  metadata only. It does not create tasks or campaigns.
- `POST /v1/drafts/submit`: creates queued records only after exact
  confirmation.

Unknown templates, blocked planner previews, unsafe deployment requests,
missing projects, and enabled execution flags fail closed.

## Task Drafts

A confirmed task draft creates one queued task. The task stores safe summary
text, template id, runner id, evidence schema, allowed paths, validation rules,
required capabilities, and planner metadata. Raw prompts and raw responses are
not persisted.

The docs example uses `software-docs-task.v1` and creates a queued task only.
It does not claim the task, run Codex, run validation, start a worker loop, or
send notifications.

## Campaign Drafts

A confirmed campaign draft creates one non-running campaign and safe campaign
steps. For `matlab-parameter-sweep.v1`, the expected steps are:

- `prepare-parameter-grid`
- `run-matlab-sweep`
- `aggregate-results`
- `generate-analysis-report` when a report was requested
- `hold-for-operator-review`

The campaign remains `draft`; steps are not executed. The MATLAB runner remains
future work for MG329/MG330.

## Desktop

Desktop adds a Draft Review + Submit card in the Bootstrap Alpha
Chat-to-Task panel. It can show submit preview state, confirmation status, and
created task or campaign ids after confirmed submit. It does not expose a run
button, claim button, worker-loop button, Codex button, MATLAB button, or raw
shell box.

## PowerShell

Manual local commands:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-draft-submit.ps1 -Command status -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-draft-submit.ps1 -Command sample-docs-preview -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-draft-submit.ps1 -Command sample-matlab-submit-preview -Json
```

Confirmed submit should be used only against the intended SkyBridge API base
and must include exact confirmation. Do not paste secrets, tokens, cookies,
provider headers, raw prompts, raw responses, raw logs, stdout, stderr, or
full environment listings into docs or logs.

## Disabled In MG328

- `claim_created=false`
- `execution_started=false`
- `codex_run_called=false`
- `matlab_run_called=false`
- `worker_loop_started=false`
- `arbitrary_shell_enabled=false`
- `raw_prompt_persisted=false`
- `raw_response_persisted=false`
- `project_control_unpause=false`
- `token_printed=false`

Next safe action after submit is `hold_for_mg329_worker_runner`.

token_printed=false
