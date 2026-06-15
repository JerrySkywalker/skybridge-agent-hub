# Launcher Error Model

Launcher commands fail closed with `skybridge.launcher_safe_error.v1`.

Safe error fields include:

- `code`
- `message`
- `next_safe_action`
- `docs_link`
- `exit_code`
- execution and mutation flags set to `false`
- `token_printed=false`

Unknown commands, shell metacharacters, worker execution, workunit apply, task claim, queue apply and host mutation terms are rejected before routing.
