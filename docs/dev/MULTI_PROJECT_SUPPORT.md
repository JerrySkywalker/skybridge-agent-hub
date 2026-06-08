# Multi-project Support

Goal 198 adds safe project profiles and project policy validation. It prepares SkyBridge to review multiple repositories, but it does not enable queue execution, task claims, worker execution, project import apply, or external repository mutation.

## Project Profile Fields

Profiles use `skybridge.project_profile.v1` and live under `config/project-profiles/`.

Required fields:

- `project_id`
- `display_name`
- `repo_path`
- `repo_identity`
- `default_branch`
- `allowed_paths`
- `blocked_paths`
- `validation_commands`
- `worker_profile`
- `goal_pack`
- `ci_policy`
- `project_policy`
- `profile_hash`
- `token_printed=false`

The sample profiles are:

- `config/project-profiles/skybridge-agent-hub.json`
- `config/project-profiles/generic-node-app.fixture.json`

The fixture profile points at repository-local fixture content and is not an onboarded external repository.

## Policy Validation

Use:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-project-profile.ps1 -Command project-profile-list -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-project-profile.ps1 -Command project-profile-validate -ProjectId skybridge-agent-hub -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-project-profile.ps1 -Command project-profile-preview -ProjectId skybridge-agent-hub -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-project-profile.ps1 -Command project-select-preview -ProjectId skybridge-agent-hub -Json
```

All modes are read-only or preview-only. Validation commands are summarized but not executed.

Profiles are rejected for:

- secret-looking keys or values;
- token values, Authorization headers, cookies, credentials, private key markers, raw prompt/output/log fields;
- missing `repo_path`, `default_branch`, or `allowed_paths`;
- repo paths outside approved roots;
- allowed or blocked paths outside the declared repo root;
- production/server-root/DNS/OpenResty/Hermes paths unless the profile is explicitly fixture-only;
- validation command strings that imply arbitrary shell execution;
- invalid goal pack paths;
- worker profiles that can claim or execute tasks;
- goal pack import apply enabled.

Default branch mismatch is reported as `project_default_branch_mismatch`. It is a warning for review because some fixture/dry-run previews may intentionally compare against a requested expected branch.

## Path Policy

`allowed_paths` and `blocked_paths` are resolved relative to `repo_path`. Absolute path traversal, `..` escape, or unapproved roots are rejected. Production and server-root paths remain out of scope for Goal 198.

`repo_path_display` is safe for UI review. The real SkyBridge profile displays only the approved repository root, and fixture profiles display repository-local fixture paths.

## Validation Command Policy

Project profile validation checks command shape only. It does not run commands.

Allowed non-fixture command shapes are bounded project checks such as:

- `corepack pnpm check`
- `corepack pnpm -C apps/desktop build`
- `pwsh -ExecutionPolicy Bypass -File scripts/powershell/validate-powershell.ps1`

Shell metacharacters, `pwsh -Command`, `cmd /c`, `bash -c`, `Invoke-Expression`, `Start-Process`, network download tools, SSH, and similar arbitrary execution shapes are rejected.

Known fixture commands must use the `fixture:<id>` shape and are still not executed by profile validation.

## Project Selection Preview

`project-select-preview` returns:

- selected project id;
- profile hash;
- repo identity;
- safe repo path display;
- default branch;
- allowed path summary;
- worker profile summary;
- goal pack summary;
- blocked reason when invalid;
- `project_selection_preview_only=true`;
- `task_created=false`;
- `task_claimed=false`;
- `task_executed=false`;
- `worker_loop_started=false`;
- `queue_execution_enabled=false`;
- `validation_commands_executed=false`;
- `token_printed=false`.

The queue-control wrapper exposes the same read-only commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command project-profile-validate -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command project-select-preview -Json
```

## Desktop And Web Review

Desktop and Web render read-only Project Profile Review panels with:

- selected project profile;
- validation status;
- allowed and blocked paths;
- default branch;
- validation command summary;
- worker profile;
- goal pack;
- policy summary;
- profile hash;
- `token_printed=false`.

No project profile review panel exposes execution controls.

## Attention Events

Goal 198 adds project-derived attention event types:

- `project_profile_invalid`
- `project_profile_missing`
- `project_repo_path_invalid`
- `project_default_branch_mismatch`
- `project_policy_blocked_path`
- `project_selection_preview_only`

These events are display-only and route through the fixture-safe attention model. They do not send real external notifications by default.

## Dry-run Second-project Onboarding

To draft a second project safely:

1. Create a new JSON profile under `config/project-profiles/`.
2. Use a repository-local fixture path first, or an approved absolute path only after review.
3. Set `project_policy.dry_run_default=true`.
4. Set `project_policy.selection_preview_only=true`.
5. Keep `worker_profile.can_claim_tasks=false`.
6. Keep `worker_profile.can_execute_tasks=false`.
7. Keep `goal_pack.import_apply_enabled=false`.
8. Run `project-profile-validate`, `project-profile-preview`, and `project-select-preview`.

Do not import goals, claim tasks, run validation commands, mutate the target repository, or start queue execution from Goal 198.

## Why Execution Remains Disabled

Goal 198 is a policy and review foundation. It adds profile validation, read-only UI review, worker/queue preview metadata, and attention integration only.

Execution remains deferred because a later reviewed bootstrap goal still needs explicit approval, repo-lock ownership, task claim transition, audit evidence, and controlled import semantics. Goal 199 drafts proposed goals only, and Goal 200 reviews/imports proposed goals under control.

## Smokes

Run the focused Goal 198 smokes:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-schema.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-validate.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-secret-rejection.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-disallowed-path.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-default-branch.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-command-shape.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-goal-pack.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-selection-preview.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-hash.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-project-profile-review.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-web-project-profile-review.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-attention.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-no-execution.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-no-secrets.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-project-profile-clean-worktree.ps1
```
