# Bootstrap Alpha Product Flow

Bootstrap Alpha is the first product-shaped SkyBridge flow. It connects a cloud
SkyBridge Server, a local Rust/Tauri Desktop client, and a local Windows worker
service into a reviewed task loop. The goal is usable operator flow, not broader
automation.

## Target Flow

1. Install and deploy the cloud SkyBridge Server through the existing server
   deploy contract.
2. Install the local Rust/Tauri Desktop client.
3. The Desktop client installs, repairs, or reports status for the local Windows
   worker service. MG325 implements this as status, doctor, install-preview, and
   repair-preview only.
4. The Desktop client provides a natural-language chat window for task intent.
5. A local Hermes planner or server-mediated Hermes planner converts natural
   language into structured task or campaign drafts.
6. Task templates constrain what the planner may produce.
7. The operator reviews a preview and explicitly confirms before any
   server-side task or campaign is created.
8. The SkyBridge Server stores project, goal, campaign, task, worker, lease, and
   evidence state.
9. The local worker actively pulls from the server and claims compatible tasks.
10. The worker executes only template runners. MG329 starts with one
    safe-local-smoke fixture runner; Codex and MATLAB runners remain future
    reviewed goals.
11. The worker reports evidence, PR, CI, smoke, and audit summaries back to the
    server.
12. The operator reviews the result through Desktop and server reports and
    decides whether to continue.

## Product Boundary

Bootstrap Alpha is a reviewed local execution product flow. It is not a general
remote shell, not an arbitrary server-to-worker command channel, and not a
silent daemon expansion.

The server is the source of truth for durable state and evidence. The client is
the operator surface. The worker is the local execution plane. The planner
creates drafts, not direct execution.

## State Contract

Bootstrap Alpha state is owned by the SkyBridge Server:

- projects define the repository or work domain;
- goals group operator intent and roadmap slices;
- campaigns group related tasks;
- tasks are concrete template-bound work items;
- workers advertise capabilities and pull compatible work;
- leases bound claims to one worker and one task;
- evidence records safe completion metadata, PR/CI links, smoke status, and
  audit summaries.

Raw prompts, raw logs, stdout, stderr, credentials, cookies, and provider
authorization values are outside the server evidence contract.

## Execution Contract

Workers may execute only through reviewed template runners. A template runner
has an explicit runner id, input schema, path bounds, validation rules, risk
class, capability requirements, and evidence schema.

Initial runner families are expected to cover software documentation/report
tasks, safe local smokes, and future MATLAB experiment batches. MG329 implements
the first narrow runner for `safe-local-smoke.v1` only.

## MG325 Local Worker Setup Layer

The first Desktop-facing layer reports `skybridge.local_worker_service_status.v1`
with service, config, tool capability, blocker, warning, and recommended-action
fields. It keeps `claim_enabled=false`, `execute_enabled=false`,
`worker_loop_started=false`, and `token_printed=false`.

## MG326 Chat-to-Task Draft Layer

The first Desktop-facing natural-language planner reports
`skybridge.task_draft_preview.v1` from a deterministic local planner. It can
produce a MATLAB parameter sweep campaign draft, a software docs/report task
draft, a clarifying question, or a blocked request preview. It keeps
`task_created=false`, `campaign_created=false`, `claim_created=false`,
`execution_started=false`, `codex_run_called=false`, `matlab_run_called=false`,
`arbitrary_shell_enabled=false`, and `token_printed=false`.

## MG327 Task Template Registry

The first registry reports `skybridge.task_template_registry.v1` and defines
the Bootstrap Alpha templates used by planner drafts:
`software-docs-task.v1`, `codex-analysis-report.v1`, `safe-local-smoke.v1`,
`matlab-parameter-sweep.v1`, and `matlab-result-analysis.v1`. Desktop shows
the registry metadata as read-only template information. The registry keeps
`execution_supported=false`, `task_creation_supported=false`,
`campaign_creation_supported=false`, `claim_supported=false`,
`codex_run_supported=false`, `matlab_run_supported=false`,
`arbitrary_shell_enabled=false`, and `token_printed=false`.

## MG328 Draft Review And Submit

The reviewed submit layer adds `skybridge.draft_submit_preview.v1` and
`skybridge.draft_submit_result.v1`. Submit preview creates nothing. Confirmed
submit requires exact operator confirmation and may create one queued task or
one non-running draft campaign. It keeps `claim_created=false`,
`execution_started=false`, `codex_run_called=false`, `matlab_run_called=false`,
`worker_loop_started=false`, `arbitrary_shell_enabled=false`,
`raw_prompt_persisted=false`, `raw_response_persisted=false`, and
`token_printed=false`.

## MG329 Worker Template Runner v1

The first worker runner adds `skybridge.worker_template_runner_preview.v1`,
`skybridge.worker_template_runner_result.v1`, and
`skybridge.template_runner_evidence.v1`. It can preview eligible tasks and,
with exact PowerShell confirmation, claim/start/complete exactly one
`safe-local-smoke.v1` fixture task against a local or fixture server.

Desktop shows a preview-only Worker Runner panel. The runner keeps
`pr_created=false`, `codex_run_called=false`, `matlab_run_called=false`,
`arbitrary_shell_enabled=false`, `worker_loop_started=false`,
`unbounded_run_enabled=false`, `project_control_unpaused=false`, and
`token_printed=false`.

token_printed=false
