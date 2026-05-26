# Codex Executor Adapter

`CodexExecutorAdapter` is the first edge worker executor. It is dogfooding infrastructure, not a core dependency.

## Inputs

The adapter receives a claimed SkyBridge task and local worker config. It uses safe task fields:

- `task_id`;
- `title`;
- `body`;
- `prompt_summary`;
- `risk`;
- `source`;
- `required_capabilities`.

It does not require Hermes.

## Execution

The adapter:

1. creates `.agent/workers/<worker>/<task>/`;
2. creates a task branch from `origin/main`;
3. resolves Codex from explicit `codex_command` or, when omitted, `Get-Command codex`;
4. writes the task prompt to a local `prompt.md`;
5. runs `codex exec --sandbox <codex_sandbox> --json --output-last-message <path> -` with the prompt file redirected to stdin;
6. writes Codex JSONL and last-message files locally;
7. returns a structured `ExecutionResult`.

`danger-full-access` is intended only for trusted local repository execution.

Explicit `codex_command` is preferred when present. A missing explicit path fails with a clear setup error. The examples intentionally omit `codex_command` so normal Windows installs resolve the active Codex CLI from `PATH` instead of depending on temporary `.agent` shims. PowerShell shims such as `codex.ps1` are invoked through `pwsh -File` to avoid Windows process launch ambiguity.

## Validation

Validation runs configured commands such as:

```powershell
just check
corepack pnpm check
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-task-runner.ps1 -DryRun
```

Validation logs are local-only and summarized in `ValidationResult`.

## Git And PR

The nested Codex prompt explicitly tells Codex not to run `git add`, `git commit`, `git push` or `gh pr create`. The edge worker owns git packaging after validation: it commits only safe changed files, excluding `.agent`, `.data`, local env files, local edge worker config and secret-like filenames. It then pushes a task branch and creates a draft PR with `gh pr create`.

GitHub is treated as an SCM/CI provider. The adapter must not mutate repository settings, branch protection or secrets.

## CI Guardian

After PR creation the worker runs `skybridge-ci-guardian.ps1` with auto-merge disabled by default. Auto-merge is passed only when worker config explicitly sets `auto_merge_enabled=true`, and the normal policy file still gates eligibility.

## Reporting

The worker reports safe task results:

- completion: summary, local last-message path and PR URL;
- failure: bounded error summary and optional local result path.

Raw Codex prompts, JSONL, stdout, stderr, patches and validation logs remain local.
