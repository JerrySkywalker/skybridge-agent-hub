# Autonomous Iteration Controller

SkyBridge's Autonomous Iteration Controller turns the successful nightly CI repair loop into a reusable, observable subsystem. It replaces blind PowerShell `while` loops with explicit state, bounded attempts, safe telemetry and reviewable PR handoffs.

The controller is not a production deployment mechanism. It coordinates local goal execution, local checks, GitHub PR review, CI repair and optional GitHub auto-merge through documented gates. Production rollout, secrets and host-level server configuration remain operator-owned.

## Why Not An Infinite Loop

The old nightly loop proved that Codex, local checks and GitHub Actions can repair many failures without human intervention. It was also hard to inspect because state lived in terminal history, ad hoc logs and a PR thread.

The controller makes each iteration a first-class record:

- every run has an `iteration_id`, project, branch, PR and attempt count;
- transitions are explicit and finite;
- local command output stays in ignored local logs, while SkyBridge receives only safe metadata;
- CI failures become structured repair attempts instead of unbounded retries;
- Hermes can supervise the controller by reading SkyBridge state instead of scraping terminals.

## Roles

Hermes Supervisor:
Reviews SkyBridge state, starts scheduled or queued work, summarizes blocked runs and sends escalation notices. Hermes never bypasses safety boundaries and does not touch production secrets.

SkyBridge Iteration Controller:
Owns reusable project configuration, iteration state, safe event emission, local log layout, bounded repair attempts and API/dashboard visibility.

Codex Worker:
Runs implementation or repair prompts through `codex exec` or the Codex TUI goal workflow. Codex works on AI branches and does not force-push `main`.

GitHub CI Guardian:
Inspects PR checks, fetches failure metadata where safe, prompts Codex for repair and updates PR status. It stops on repeated failure or safety boundaries.

GitHub Auto-merge Gate:
Uses GitHub branch protection and auto-merge as the unattended merge gate. Auto-merge is disabled by default and can only be enabled by explicit project configuration or CLI flag.

Notification Center:
Receives concise iteration events and supervisor escalation decisions. Notifications contain IDs, states, PR links and reasons, not raw prompts, patches, stdout, stderr or secrets.

## Supported Modes

- One-shot iteration: claim one goal, run Codex once, check, commit, push and optionally open a PR.
- PR CI guardian mode: watch one PR, repair failed CI up to a bounded attempt count, then stop.
- Nightly guardian mode: scheduled supervisor pass over queued goals and open AI PRs.
- Auto-merge candidate mode: enable GitHub auto-merge only after local checks and required GitHub checks are green.
- Dry-run mode: validate config, goal selection, command shape and telemetry shape without running Codex, mutating Git or creating PRs.

## State Machine

```text
idle
queued
planning
coding
local_checking
pushing
pr_opened
ci_pending
ci_failed
ci_repairing
ci_green
auto_merge_enabled
merged
blocked
failed
```

Normal one-shot path:

```text
queued -> planning -> coding -> local_checking -> pushing -> pr_opened -> ci_pending
```

Guardian repair path:

```text
ci_pending -> ci_failed -> ci_repairing -> local_checking -> pushing -> ci_pending
```

Completion paths:

```text
ci_pending -> ci_green -> auto_merge_enabled -> merged
ci_pending -> ci_green
any state -> blocked
any state -> failed
```

## Safety Boundaries

The controller must not:

- commit `.env`, credentials, private keys, tokens, cookies or production configuration;
- modify `/opt`, OpenResty, Authelia, 1Panel or Docker daemon settings;
- deploy to a real server;
- run destructive cleanup or privileged remote execution;
- enable privileged self-hosted runners for public PRs;
- force-push `main`;
- weaken tests, branch protection guidance, redaction, audit or validation;
- upload raw prompts, patches, stdout, stderr, Codex JSONL or secrets to SkyBridge.

Remote WSS execution remains design-only until a later goal adds audited, approval-gated, feature-flagged behavior.

## Stop Conditions

An iteration stops when:

- no goal is available;
- local checks fail after `max_repair_attempts`;
- GitHub checks fail after `max_repair_attempts`;
- a safety boundary is detected;
- the branch is not the expected AI branch;
- the worktree contains unrelated uncommitted changes that would make an automated commit unsafe;
- required tooling is missing and dry-run cannot validate the path;
- GitHub or SkyBridge is unavailable in a mode that requires it.

SkyBridge telemetry is fail-open for local work. If the SkyBridge server is offline, scripts continue and retain local metadata under `.agent/iterations/<iteration-id>/`.

## Relationship To Existing Runner Workflows

`scripts/powershell/yolo-runner.ps1` remains the fallback queue runner for bounded `goals/ready` tasks. It is intentionally single-worker and can still be used when a simple queue loop is enough.

The Autonomous Iteration Controller is the reusable control-plane feature for one-shot work, PR CI repair, Hermes supervision and dashboard visibility. It should call Codex in the same safe style as the runner, but it records iteration state separately from raw run logs.

Codex TUI Master Goal remains the preferred interface for long-horizon human-supervised development. The controller can launch one-shot `codex exec` workers for prepared goals or serve as the CI repair layer for TUI-created PRs.
