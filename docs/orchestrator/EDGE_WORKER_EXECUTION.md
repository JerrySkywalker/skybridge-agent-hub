# Edge Worker Execution

SkyBridge Edge Worker is the first local runtime provider that can join the worker pool and execute queued tasks through an executor adapter. It is intentionally adapter-shaped: Codex is the first implementation, while OpenCode, manual execution and Hermes-assisted flows can be added later without changing the task core.

## Contracts

### EdgeWorker

`EdgeWorker` is a local process that:

- reads a local `WorkerConfig`;
- registers itself with `/v1/workers/register`;
- sends heartbeats to `/v1/workers/:workerId/heartbeat`;
- polls queued tasks in its configured project;
- claims exactly one compatible task at a time;
- delegates execution to an `ExecutorAdapter`;
- validates local results;
- optionally creates a pull request through an SCM provider;
- reports task completion or failure through `/v1/tasks/:id/complete` or `/v1/tasks/:id/fail`.

The worker stores runtime logs under `.agent/workers/<worker_id>/<task_id>/`. Those logs are local-only and must not be uploaded to SkyBridge as raw command output.

### WorkerConfig

`WorkerConfig` is a local JSON file. Example configs live in `config/edge-worker.example.json` and `config/edge-worker.homepc.example.json`; real configs use `config/edge-worker.json` and remain gitignored.

Required fields:

- `worker_id`: stable worker identity.
- `project_id`: project whose tasks this worker can execute.
- `repo_path`: local repository path.
- `api_base`: SkyBridge API base URL.
- `poll_interval_seconds`: loop delay.
- `capabilities`: advertised worker capabilities.
- `allowed_task_types`: compatible task families such as `docs`, `code`, `test` or `ops`.
- `blocked_task_types`: task families the worker must skip.
- `codex_command`: Codex CLI executable.
- `codex_sandbox`: Codex sandbox mode. `danger-full-access` is allowed only for trusted local repo execution.
- `max_task_runtime_minutes`: hard timeout for execution and validation.
- `auto_merge_enabled`: defaults to `false`.
- `notification_enabled`: defaults to `false`.

### TaskPolling

The worker lists `/v1/tasks?status=queued&project_id=<project_id>`, filters tasks by required capabilities and task type, and chooses one task in server order. Polling is safe in dry-run mode: the worker reports the selected task without claiming it.

### TaskClaim

Claiming calls `/v1/tasks/:taskId/claim` with `worker_id`. The API is authoritative. If another worker wins the race, the local worker treats the claim as skipped and continues later.

### CodexExecutorAdapter

`CodexExecutorAdapter` is a local executor adapter that:

- creates a task branch from `main`;
- runs `codex exec --sandbox <sandbox> --json --output-last-message <path>`;
- writes Codex JSONL and last-message output under `.agent/workers/<worker>/<task>/`;
- never prints raw prompts, command output, patches or secrets to SkyBridge;
- returns an `ExecutionResult` with safe summary fields and local log paths.

Future executors should implement the same result shape without changing task lifecycle APIs.

### ExecutionResult

`ExecutionResult` contains:

- `ok`;
- `status`: `completed`, `failed`, `blocked` or `skipped`;
- `executor_adapter`;
- `branch`;
- `started_at` and `completed_at`;
- `exit_code`;
- `summary`;
- `last_message_path`;
- `log_path`;
- `changed_files`.

Only safe summary fields are sent to SkyBridge. Local paths may be included as operator hints, but raw file content remains local.

### ValidationResult

`ValidationResult` contains:

- `ok`;
- `status`: `passed`, `failed` or `skipped`;
- `commands`;
- `exit_code`;
- `started_at` and `completed_at`;
- `log_path`;
- `summary`.

Validation commands come from the task payload when available. If no task validation command is defined, the worker can use a conservative config default or mark validation skipped.

### PRResult

`PRResult` contains:

- `ok`;
- `status`: `created`, `skipped` or `failed`;
- `branch`;
- `pr_number`;
- `pr_url`;
- `summary`.

GitHub is the first dogfooding SCM provider. The worker must not mutate repository settings or branch protection.

### Complete/Fail Semantics

Complete a task only when execution succeeded and required validation passed or was explicitly skipped as safe. The completion payload may include:

- `summary`;
- `result_url`;
- `pr_url`;
- `worker_id`.

Fail a task when claim, execution, validation, commit, push, PR creation or CI Guardian fails. The fail payload includes a bounded `error_summary`, optional `result_url`, and `worker_id`.

### Offline And Sleep Behavior

Workers are local-first and may sleep or go offline. SkyBridge derives `online`, `stale` and `offline` from heartbeat age. A resumed worker should heartbeat before polling and should not assume a previous local task is still claimable; it must read the current task state from SkyBridge.

### Safety Boundaries

Default behavior is safe and dry-run oriented:

- `-DryRun` previews registration, heartbeat, polling, claiming and command shape.
- `-Send` is required for real bootstrap notifications.
- `auto_merge_enabled` defaults to `false`.
- notification delivery defaults to `false`.
- production deployment, server root config, secrets and GitHub settings are out of scope.
- raw Codex JSONL, stdout/stderr, patches and prompts remain local.
- `.agent`, `.data`, `.env`, local config and secret-like files must not be committed.
- first real pilot tasks must be docs-only.
