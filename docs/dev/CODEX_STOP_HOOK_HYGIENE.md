# Codex Stop Hook Hygiene

After MG341, Codex reported:

```text
Stop hook failed with: error: hook timed out after 30s
```

For Bootstrap Alpha RC1 this is non-blocking if:

- git is clean;
- the RC1 tag is verified locally and on origin;
- Deploy Cloud passed;
- `/v1/version` matches the expected commit and image;
- post-tag audit passed;
- required local checks passed;
- `token_printed=false`.

## Classification

Use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-alpha-rc1-handoff.ps1 -Command stop-hook-diagnose -Json
```

Possible safe classifications:

- `repo_hook_ok`: repository-controlled hook exists and is bounded.
- `repo_hook_timeout_risk`: repository-controlled hook may exceed the safe
  budget or call heavy workflows.
- `local_codex_hook_not_repo_controlled`: the observed timeout is likely in the
  local Codex hook layer, which this repository must not mutate.
- `no_repo_hook_found`: no repository-controlled Stop hook was found.
- `warning`: safe diagnosis completed with a non-blocking warning.

MG342 does not read local Codex user configuration and does not mutate it.

## Stop Hook Constraints

Stop hooks should:

- finish in under 30 seconds;
- avoid cloud mutation;
- avoid task creation, claim, or execution;
- avoid Codex execution;
- avoid MATLAB execution;
- avoid full test suites;
- avoid cloud parity, deploy, or RC gate audits;
- avoid raw token, credential, prompt, log, stdout/stderr, or
  process-environment output.

Repository examples should prefer tiny fail-open telemetry hooks with their own
short timeout. Longer validation belongs in explicit operator commands, not stop
hooks.

## Manual Checks

If the stop hook warning recurs, run:

```powershell
corepack pnpm smoke:codex-stop-hook-hygiene
corepack pnpm smoke:bootstrap-alpha-rc1-handoff-local
corepack pnpm smoke:bootstrap-alpha-rc1-tag-check
corepack pnpm smoke:bootstrap-alpha-rc-gate-local
```

These checks are read-only and must keep `task_claimed=false`,
`execution_started=false`, `codex_run_called=false`, `matlab_run_called=false`,
`worker_loop_started=false`, `project_control_unpaused=false`, and
`token_printed=false`.
