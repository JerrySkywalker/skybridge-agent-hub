# Chat-to-Task Draft Planner

MG326 adds the first Desktop-facing Bootstrap Alpha planner surface. It turns
natural-language input into a safe task or campaign draft preview. It does not
create server tasks or campaigns and does not execute anything.

## Planner Mode

The first planner is deterministic and local:

- no live Hermes call is required;
- no raw prompt is persisted by default;
- no raw response is persisted;
- only `input_preview` and `input_hash` are returned;
- task creation, campaign creation, task claim, Codex execution, MATLAB
  execution, arbitrary shell, and worker loop start remain disabled.

Future goals may add Hermes or local model integration behind the same draft
schema. That integration must keep review-before-submit and no-execution
defaults.

MG327 adds the Bootstrap Alpha Task Template Registry. Known MATLAB and
docs/report drafts now use registry metadata for `template_id`, `runner_id`,
allowed paths, blocked paths, validation rules, risk class, and evidence
schema. The planner remains deterministic and preview-only.

## Draft Schemas

The shared preview contracts are:

- `skybridge.chat_to_task_session.v1`
- `skybridge.task_draft.v1`
- `skybridge.campaign_draft.v1`
- `skybridge.task_draft_clarifying_question.v1`
- `skybridge.task_draft_preview.v1`

Drafts include template id, project id, title, summary, risk, required
capabilities, allowed paths, blocked paths, validation, runner id, evidence
schema, planner id, input preview, input hash, and explicit safety flags.

These flags stay false in MG326:

- `raw_prompt_persisted=false`
- `raw_response_persisted=false`
- `task_created=false`
- `campaign_created=false`
- `claim_created=false`
- `execution_started=false`
- `codex_run_called=false`
- `matlab_run_called=false`
- `arbitrary_shell_enabled=false`
- `token_printed=false`

## Clarifying Questions

If the request does not contain enough template, path, or evidence detail, the
planner returns `skybridge.task_draft_clarifying_question.v1`. The Desktop panel
shows the question list and keeps submit disabled.

Command-looking text is detected and marked as `command_text_detected=true`.
It is never executed. The planner asks the operator to convert command-looking
text into template parameters.

## Blocked Requests

Requests that mention production deploy, DNS, Cloudflare, OpenResty, Authelia,
GitHub settings, secrets, arbitrary shell, unbounded runs, or worker loop start
return a blocked preview. A blocked preview is safe output, not a server task.

## MATLAB Example

Input:

```text
帮我用 MATLAB 跑第四章参数扫描实验，eta=2..10，h=500/700km，P=6/8/10，输出 summary 和报告。
```

Expected draft:

- `draft_type=campaign`
- `template_id=matlab-parameter-sweep.v1`
- required capabilities include `windows`, `powershell`, `matlab`, and `codex`
  when a report is requested;
- allowed paths include `results/skybridge/**` and `docs/experiments/**`;
- blocked paths include `.env`, `secrets/**`, `deploy/**`, and `.git/**`;
- `runner_id=matlab-parameter-sweep-runner.v1`;
- execution flags remain false.

## Manual Smoke

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-chat-to-task-draft.ps1 -Command sample-matlab -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-chat-to-task-draft.ps1 -Command sample-docs -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-chat-to-task-draft.ps1 -Command status -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-task-template-registry.ps1 -Command list -Json
```

Do not paste secrets, tokens, cookies, provider headers, raw prompts, stdout,
stderr, or full environment listings into docs, issues, logs, or screenshots.

token_printed=false
