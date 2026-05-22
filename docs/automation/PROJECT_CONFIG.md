# Iteration Controller Project Configuration

The Autonomous Iteration Controller is configured per project. Local private config lives at `config/iteration-controller.json` and is ignored by Git. Shareable examples live in `config/*.example.json`.

## Required Sections

`project` identifies the repository and working copy:

- `id`: stable SkyBridge project identifier.
- `name`: display name for dashboards and reports.
- `repository`: GitHub `owner/name`.
- `localPath`: absolute local working-copy path.
- `baseBranch`: protected merge target.
- `branchPrefix`: prefix for AI branches, usually `ai/`.

`codex` defines the implementation worker:

- `command`: executable, usually `codex`.
- `args`: base arguments such as `exec --json`.
- `sandbox`: Codex sandbox mode.
- `approvalPolicy`: approval setting for non-interactive runs.
- `outputLastMessage`: whether scripts should write a local final-message file.

`goals` points to queue state. The controller may run a single `-GoalFile` or select the next Markdown file from `queuePath`.

`iteration` defines bounded local validation:

- `maxRepairAttempts`: maximum local or CI repair loops.
- `localCheckCommands`: required checks before commit or push.
- `smokeCommands`: optional safe fixture/local smoke checks.

`github` controls PR and CI behavior:

- `requiredChecks`: check names that must pass before auto-merge is considered.
- `createPR`: whether the controller may open a PR.
- `watchCI`: whether the CI Guardian should inspect remote checks.
- `autoMerge`: defaults to `false`; enable only with branch protection and explicit operator intent.

`notifications` and `skybridge` control safe observability. SkyBridge telemetry is fail-open by default: if the API is offline, the controller keeps local metadata and continues non-network work.

`hermes` is a placeholder for supervisor settings. Hermes should call the bridge script and SkyBridge APIs instead of hardcoding project paths.

## Safety Rules

Project config must not contain secrets, tokens, cookies, private keys or production deployment credentials. Use environment variables or external secret stores for future credentialed integrations.

The controller must not upload raw prompts, patches, stdout, stderr or Codex JSONL logs. Local logs belong under `.agent/iterations/<iteration-id>/`, which is ignored by Git.

Auto-merge remains disabled unless both project config and CLI flags explicitly enable it. Branch protection and required checks are the merge gate.
