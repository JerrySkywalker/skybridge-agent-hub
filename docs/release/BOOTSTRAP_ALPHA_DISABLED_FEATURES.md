# Bootstrap Alpha Disabled Features

Bootstrap Alpha RC intentionally does not support the following capabilities.
They remain disabled until a future reviewed goal adds explicit product,
security, and operator controls.

- General remote shell.
- Unbounded run.
- Daemon auto-expansion.
- Arbitrary task execution.
- Arbitrary prompt execution.
- MATLAB arbitrary command.
- Codex arbitrary prompt.
- Production deployment automation for other projects.
- PR creation by worker runner.
- Auto-merge.
- Multi-user permissions.
- Mobile/watch client.
- Notification center productization.
- Multi-project production support.
- Long-running real research sweeps.
- Background autonomous queue processing.

## RC Safety Flags

The RC gate and reports must preserve:

- `task_created=false`
- `task_claimed=false`
- `execution_started=false`
- `codex_execution_started=false`
- `matlab_execution_started=false`
- `worker_loop_started=false`
- `project_control_unpaused=false`
- `deploy_mutation_performed=false`
- `tag_created=false`
- `github_release_created=false`
- `token_printed=false`

## Operator Rule

If any disabled feature appears enabled in a report, Desktop panel, task
evidence summary, or release gate output, Bootstrap Alpha RC is blocked.
