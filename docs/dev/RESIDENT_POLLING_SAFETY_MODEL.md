# Resident Polling Safety Model

Resident polling preview is explicitly non-executing.

It must not claim tasks, execute Codex, apply queues, create workunits, create tasks, create task PRs, or start automatically without an explicit preview command.

Safety invariants:

- `polling_enabled=false`
- `polling_preview_enabled=true`
- `execution_enabled=false`
- `claim_enabled=false`
- `queue_apply_enabled=false`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `no_next_execution_authorized=true`
- `token_printed=false`

Use `smoke-resident-polling-no-task-claim.ps1`, `smoke-resident-polling-no-codex-execution.ps1`, `smoke-resident-polling-no-queue-apply.ps1`, and `smoke-resident-polling-token-printed-false.ps1` before treating the preview as ready.
