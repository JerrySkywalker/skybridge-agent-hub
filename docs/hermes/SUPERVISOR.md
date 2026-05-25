# Hermes Supervisor

Hermes is the scheduler, reviewer and escalation layer for SkyBridge autonomous iteration. It does not replace SkyBridge state, Codex implementation work or GitHub branch protection.

## Responsibilities

Hermes should:

- inspect SkyBridge status through `/v1/supervisor/status` and `/v1/iterations`;
- inspect open PRs with GitHub CLI when needed;
- trigger one bounded controller run through `skybridge-iterate.ps1`;
- trigger CI repair through `skybridge-ci-guardian.ps1`;
- summarize blocked runs for a human;
- send direct bootstrap notifications for urgent lifecycle messages;
- emit or preserve SkyBridge events when the server is reachable.

Hermes must not:

- bypass SkyBridge safety boundaries;
- touch production secrets, `.env`, SSH keys, tokens, cookies or global host config;
- deploy to real servers;
- mutate GitHub branch protection automatically;
- execute destructive remote commands;
- depend on SkyBridge Notification Center for phone notification during SkyBridge's own development.

## Supervisor Loop

1. Query SkyBridge supervisor status.
2. Query open AI PRs if the GitHub CLI is available.
3. If a run is `ci_failed`, call the CI Guardian in repair mode.
4. If no active run exists and a queued goal is available, call the iteration controller in one-shot mode.
5. If a run is `blocked` or `failed`, call the bootstrap notifier and produce a human-readable summary.
6. If all current PRs are green, record the status and let branch protection or GitHub auto-merge decide the merge.
7. Stop after one bounded decision per invocation.

Hermes can run on a schedule, for example hourly health checks and nightly queue processing. The local bridge script returns JSON so Hermes can turn each pass into a concise report without learning repository internals.

## Current Autonomy Stack

- Local Codex worker: performs repository edits, local checks and AI branch work on the operator machine.
- GitHub CI and auto-merge: runs required checks and keeps branch protection as the final merge gate.
- Auto-merge sweep: classifies open PRs, reports eligible/blocked/draft/non-AI/missing-check/pending-check counts and remains dry-run unless `-EnableAutoMerge` is explicit.
- Hermes cloud supervisor: stays private behind the local SSH tunnel and supervises health, reports and sweep decisions through JSON commands.
- Bootstrap ntfy fallback: sends concise non-urgent phone summaries when `-Send` is explicit; urgent remains reserved for hard safety boundaries.
- Human-only controls: production deployment, server root configuration, GitHub branch protection/repository settings, secret changes, public Hermes exposure and scheduled real auto-merge.

## Supervision Model

```text
Hermes Supervisor
  |
  +-- GET /v1/supervisor/status
  +-- GET /v1/supervisor/next-action
  +-- pwsh scripts/powershell/skybridge-hermes-supervisor.ps1
        |
        +-- skybridge-iterate.ps1
        +-- skybridge-ci-guardian.ps1
        +-- notify-bootstrap.ps1
        +-- optional SkyBridge event writes
```

SkyBridge remains the state center and dashboard. Hermes provides judgment, scheduling and escalation.

## Prompt Template Pattern

Hermes prompts should include:

- current mode;
- project config path;
- SkyBridge API base;
- safety boundaries;
- command to run;
- expected JSON output;
- instruction to notify through bootstrap notifier for urgent or blocked outcomes.

Templates live under `docs/hermes/prompts/` and are safe examples. They do not contain credentials.

## Nightly Pilot Commands

Safe local pilot:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-hermes-nightly-pilot.ps1 -UseHermesApi -Json
```

Same pilot with one non-urgent phone summary:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-hermes-nightly-pilot.ps1 -UseHermesApi -Send -Json
```

Dry-run sweep only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 -Mode NightlySweep -UseHermesApi -DryRun -Json
```
