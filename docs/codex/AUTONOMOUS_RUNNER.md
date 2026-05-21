# Autonomous Runner

SkyBridge's autonomous runner is a local, single-worker loop for processing Markdown goal files with Codex. It is now the fallback batch/background processor. Primary long-horizon development should use Codex TUI with `goals/00_AUTONOMOUS_MASTER_GOAL.md` and `goals/mega/*.md`.

Use the runner when a goal has already been decomposed into a bounded `goals/ready/*.md` task and unattended processing is useful. It is meant to create reviewable AI branches, not to plan multi-hour product work and not to deploy production changes.

For the primary TUI workflow, see `docs/codex/TUI_MASTER_GOAL.md`.

## Status

The current implementation is an MVP in `scripts/powershell/yolo-runner.ps1`.

It supports:

- scanning `goals/ready/*.md`;
- selecting one goal at a time;
- resuming a previously claimed goal from `goals/doing`;
- moving the goal into `goals/doing`;
- writing claim metadata next to the goal and under `.agent/runs`;
- writing per-goal lock metadata with stale-lock detection;
- creating or reusing an `ai/<goal-id>-<slug>` branch;
- running `codex exec` with `--json` and `--output-last-message`;
- writing run logs to `.agent/runs/<timestamp>-<goal-id>/`;
- running `just check` or `corepack pnpm check`;
- attempting limited Codex repair rounds;
- moving completed goals to `goals/done` and failed goals to `goals/failed`;
- committing remaining passing changes when the Codex run has not already committed them;
- pushing the branch;
- creating a GitHub PR when requested and `gh` is available;
- optionally emitting summarized `skybridge.agent_event.v1` telemetry to the local SkyBridge server;
- sending only important ntfy notifications when notification environment variables are configured.

`MaxParallel` must remain `1`. Parallel execution is intentionally out of scope for this MVP.

## Role In The Workflow

Use these paths for different automation needs:

- Codex TUI: primary development workflow for mega goals and staged multi-commit work.
- `yolo-runner.ps1`: fallback batch processor for bounded queue goals in `goals/ready`.
- `codex exec`: non-interactive CI/scripted one-shot tasks and repair loops.

Do not put a full `goals/mega/*.md` file directly into `goals/ready`. Extract a small child goal first.

## Queue Layout

```text
goals/ready    bounded child goals available for the runner
goals/doing    claimed goals and claim metadata
goals/done     completed goals
goals/failed   failed goals
.agent/runs    ignored runtime logs and Codex JSONL output
```

Goal filenames should start with a stable numeric ID when possible:

```text
022-runner-resume-locking.md
```

That filename becomes the default branch:

```text
ai/022-runner-resume-locking
```

## Lifecycle

1. The runner reads `config/runner.json` if it exists, or uses CLI/default values.
2. It creates the queue and run-log directories if missing.
3. It first checks `goals/doing` for an already claimed Markdown file.
4. If a doing goal exists, it validates `<goal>.claim.json`, checks `<goal>.lock.json`, and resumes only when the lock is missing or stale.
5. If no doing goal exists, it selects the first Markdown file in `goals/ready`, sorted by filename.
6. It copies the original goal into `.agent/runs/<timestamp>-<goal-id>/goal.md`.
7. It moves the goal into `goals/doing` and writes `<goal>.claim.json` plus `<goal>.lock.json`.
8. It creates or checks out the goal branch, then verifies the current branch still matches the expected goal branch.
9. If runner telemetry is enabled, it emits a `run.started` event for the claimed or resumed goal.
10. It invokes Codex with JSON output:

```powershell
codex exec --sandbox workspace-write --ask-for-approval never --json --output-last-message <run-dir>\last-message.md <prompt>
```

11. It emits `tool.started` and `tool.completed` or `tool.failed` events around Codex, standard checks and repair attempts.
12. It runs the standard check:

- `just check` when `just` is available;
- otherwise `corepack pnpm check`.

13. When checks fail, it asks Codex to repair the failure and retries until `MaxRepairRounds` is exhausted.
14. On success, it moves the goal, claim and lock metadata to `goals/done`, writes `result.json`, commits any remaining staged work, pushes the branch and emits `run.completed`.
15. On failure, it moves the goal, claim and lock metadata to `goals/failed` using unique filenames when previous failure context exists, writes `result.json`, emits `run.failed` and sends a high-priority notification.

## Resume and Locks

The runner remains single-worker only. `MaxParallel` must stay `1`.

For each claimed goal, the runner writes:

```text
goals/doing/<goal>.claim.json
goals/doing/<goal>.lock.json
```

The claim is durable ownership metadata. The lock is the current runner process lease and includes host, pid, branch, run directory and timestamps.

On restart, a goal already in `goals/doing` takes priority over `goals/ready`. The runner validates that the goal filename, goal id and expected branch match the claim before invoking Codex. If the lock process is no longer alive on the same host, or the lock age exceeds `lockStaleMinutes`, the stale lock is archived as `<goal>.lock.json.<timestamp>.stale.json` and the goal is resumed with the original claim and run directory.

When a lock is still active, the runner skips work instead of taking another ready goal. This preserves single-worker behavior and avoids duplicating a claimed goal.

## Configuration

Copy the example if local overrides are needed:

```powershell
Copy-Item .\config\runner.example.json .\config\runner.json
```

`config/runner.json` is intended for local machine policy. Do not put secrets in it.

Important fields:

```json
{
  "mode": "ThesisYOLO",
  "maxParallel": 1,
  "maxRepairRounds": 3,
  "lockStaleMinutes": 240,
  "push": true,
  "autoPR": false,
  "createPR": false,
  "sandbox": "workspace-write",
  "telemetry": {
    "enabled": false,
    "apiBase": "http://127.0.0.1:8787",
    "timeoutSeconds": 3,
    "tokenEnvironmentVariable": "SKYBRIDGE_API_TOKEN",
    "agentId": "skybridge-yolo-runner"
  }
}
```

Telemetry is disabled by default. Enable it in `config/runner.json` or set `SKYBRIDGE_RUNNER_TELEMETRY=1`; `SKYBRIDGE_API_BASE` can override the API base when the config omits `telemetry.apiBase`. Delivery is fail-open: if the server is offline or rejects a request, the runner continues local queue processing.

Runner telemetry uses the normalized `skybridge.agent_event.v1` schema:

```text
agent.idle              runner started, no ready goal
run.started             goal claimed or resumed
tool.started            Codex invocation, standard check or repair started
tool.completed/failed   Codex invocation, standard check or repair finished
run.completed           goal completed
run.failed              goal failed
notification.requested  runner notification requested
```

Payloads include lifecycle names, goal IDs, branch names, run directories, attempt numbers, command names and exit codes. They intentionally omit full prompts, stdout, stderr, Codex JSONL output, check logs, repair logs, tokens and secrets by default.

Use environment variables for ntfy:

```powershell
$env:NTFY_URL = "https://ntfy.sh"
$env:NTFY_TOPIC = "your-topic"
```

## Running Once

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\yolo-runner.ps1 `
  -ConfigFile .\config\runner.example.json
```

## Running as a Local Loop

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\yolo-runner.ps1 `
  -Loop `
  -PollSeconds 60 `
  -MaxRepairRounds 3
```

Keep this loop on a dedicated local machine or terminal session. It is not the primary development workflow and is not a production deployment mechanism.

## Dry Run

Use `-DryRun` to verify queue selection without invoking Codex, changing branches or running checks:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\yolo-runner.ps1 -DryRun
```

Dry-run also covers interrupted-run scenarios. A doing goal with a valid claim is reported as `resume=True`; stale locks are reported but not archived during dry-run.

Focused runner dry-run tests live in:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\test-yolo-runner.ps1
```

## Logs

Each run writes:

```text
.agent/runs/<timestamp>-<goal-id>/
  goal.md
  claim.json
  resume-<timestamp>.json
  codex.jsonl
  last-message.md
  check-0.log
  repair-0.jsonl
  repair-0-last-message.md
  result.json
```

`.agent/runs` is ignored by Git because it may contain large operational logs.

## Safety Boundaries

The runner does not authorize:

- committing secrets;
- changing production secrets or server root configuration;
- destructive cleanup commands;
- force-pushing `main`;
- weakening authentication or authorization;
- production deployment.

If a goal requires one of those actions, move it out of `goals/ready` and require human review.

## Known Limits

- No parallel execution.
- No PR update loop after remote CI fails.
- No production service wrapper.
