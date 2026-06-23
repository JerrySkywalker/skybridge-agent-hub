# Worker Template Runner v1

MG329 adds the first controlled Bootstrap Alpha worker execution path. It is a
template-bound, one-task runner for low-risk fixture/local validation work. It
does not add a generic queue worker, background daemon, Codex runner, MATLAB
runner, or arbitrary shell surface.

## Pull Model

The SkyBridge Server stores queued tasks and safe evidence. The server does not
remote-control the worker. A local worker inspects the queue, selects one
compatible task, then uses the existing task lifecycle endpoints:

- `POST /v1/tasks/:taskId/claim`
- `POST /v1/tasks/:taskId/start`
- `POST /v1/tasks/:taskId/complete`
- `POST /v1/tasks/:taskId/fail`

MG329 uses this lifecycle only from the PowerShell runner script and only after
exact confirmation for `apply-one`.

## Supported MG329 Template

MG329 supports only:

- `template_id=safe-local-smoke.v1`
- `runner_id=safe-local-smoke-runner.v1`
- `risk=low`
- required capabilities: `powershell`, `node`, `pnpm`

The runner writes sanitized fixture evidence under
`.agent/tmp/worker-template-runner/<task-id>/evidence.json`. That path is local
and ignored by git.

These templates remain rejected in MG329:

- `matlab-parameter-sweep.v1`
- `matlab-result-analysis.v1`
- `codex-analysis-report.v1`
- `software-docs-task.v1`
- unknown template ids

## Selection Rules

The selector requires:

- task status is `queued`;
- risk is `low`;
- template and runner ids match the supported MG329 pair;
- worker is registered, enabled, online, and has required capabilities;
- required capabilities do not include Codex or MATLAB;
- allowed paths are inside the fixed local smoke fixture policy;
- blocked paths include the fixed deny policy;
- no active lease or existing claim residue exists;
- task text and allowed paths do not mention production deploy, DNS,
  Cloudflare, OpenResty, Authelia, GitHub settings, server root, secrets,
  command text, Codex, MATLAB, or unbounded execution.

Preview returns `skybridge.worker_template_runner_preview.v1` and creates no
claim. Apply returns `skybridge.worker_template_runner_result.v1`.

## Confirmation

`apply-one` requires the exact text:

```text
I_UNDERSTAND_RUN_ONE_SAFE_TEMPLATE_TASK_ONLY
```

`MaxTasks` is hard-limited to one. Values greater than one are rejected in
MG329.

## Desktop Surface

Desktop adds a Bootstrap Alpha Worker Runner Preview panel. The panel shows the
fixture preview contract, selected template id, runner id, rejection reason,
capability summary, path checks, disabled flags, and last sanitized evidence
summary fixture.

Desktop does not perform live apply in MG329. Apply remains PowerShell-only
with exact confirmation.

## Manual Commands

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-template-runner.ps1 -Command status -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-template-runner.ps1 -Command preview -ApiBase http://127.0.0.1:8787 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-template-runner.ps1 -Command apply-one -ApiBase http://127.0.0.1:8787 -Confirm -ConfirmationText I_UNDERSTAND_RUN_ONE_SAFE_TEMPLATE_TASK_ONLY -Json
```

Use `apply-one` only against the intended local or fixture server. Live cloud
post-deploy smoke must remain read-only for MG329 and must not claim live cloud
tasks.

## Disabled In MG329

- `pr_created=false`
- `codex_run_called=false`
- `matlab_run_called=false`
- `arbitrary_shell_enabled=false`
- `worker_loop_started=false`
- `unbounded_run_enabled=false`
- `project_control_unpaused=false`
- no old task requeue
- no notification send
- `token_printed=false`

MG330 is the next planned MATLAB golden trial and must introduce MATLAB
execution separately through its own reviewed template runner boundary.

token_printed=false
