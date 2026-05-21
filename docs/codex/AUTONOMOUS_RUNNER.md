# Autonomous Runner

SkyBridge's autonomous runner is a local, single-worker loop for processing Markdown goal files with Codex. It is meant to create reviewable AI branches, not to deploy production changes.

## Status

The current implementation is an MVP in `scripts/powershell/yolo-runner.ps1`.

It supports:

- scanning `goals/ready/*.md`;
- selecting one goal at a time;
- moving the goal into `goals/doing`;
- writing claim metadata next to the goal and under `.agent/runs`;
- creating or reusing an `ai/<goal-id>-<slug>` branch;
- running `codex exec` with `--json` and `--output-last-message`;
- writing run logs to `.agent/runs/<timestamp>-<goal-id>/`;
- running `just check` or `corepack pnpm check`;
- attempting limited Codex repair rounds;
- moving completed goals to `goals/done` and failed goals to `goals/failed`;
- committing remaining passing changes when the Codex run has not already committed them;
- pushing the branch;
- creating a GitHub PR when requested and `gh` is available;
- sending only important ntfy notifications when notification environment variables are configured.

`MaxParallel` must remain `1`. Parallel execution is intentionally out of scope for this MVP.

## Queue Layout

```text
goals/ready    goals available for the runner
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
3. It selects the first Markdown file in `goals/ready`, sorted by filename.
4. It copies the original goal into `.agent/runs/<timestamp>-<goal-id>/goal.md`.
5. It moves the goal into `goals/doing` and writes `<goal>.claim.json`.
6. It creates or checks out the goal branch.
7. It invokes Codex with JSON output:

   ```powershell
   codex exec --sandbox workspace-write --ask-for-approval never --json --output-last-message <run-dir>\last-message.md <prompt>
   ```

8. It runs the standard check:
   - `just check` when `just` is available;
   - otherwise `corepack pnpm check`.
9. When checks fail, it asks Codex to repair the failure and retries until `MaxRepairRounds` is exhausted.
10. On success, it moves the goal and claim metadata to `goals/done`, writes `result.json`, commits any remaining staged work and pushes the branch.
11. On failure, it moves the goal and claim metadata to `goals/failed`, writes `result.json` and sends a high-priority notification.

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
  "push": true,
  "autoPR": false,
  "createPR": false,
  "sandbox": "workspace-write"
}
```

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

Keep this loop on a dedicated local machine or terminal session. It is not a production deployment mechanism.

## Dry Run

Use `-DryRun` to verify queue selection without invoking Codex, changing branches or running checks:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\yolo-runner.ps1 -DryRun
```

## Logs

Each run writes:

```text
.agent/runs/<timestamp>-<goal-id>/
  goal.md
  claim.json
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
- No durable lock recovery beyond goal movement and claim metadata.
- No structured event ingestion into the SkyBridge server yet.
- No PR update loop after remote CI fails.
- No production service wrapper.
