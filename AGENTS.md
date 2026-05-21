# AGENTS.md

This repository is intended to be developed by autonomous coding agents with minimal human interruption during Jerry's thesis-defense period.

## Product identity

- Product name: **SkyBridge Agent Hub**
- Repository folder: `skybridge-agent-hub`
- Package scope: `@skybridge-agent-hub/*`
- Event schema: `skybridge.agent_event.v1`
- Goal: build a reusable agent telemetry, notification and remote-control foundation for Codex, OpenCode, Hermes Agent and future custom agents.

Do not rename the product back to temporary names such as `starter`, `yolo-starter`, `codex-dashboard`, `glance-dashboard`, or `agentops`.

## Mission

Build an open-source local/cloud agent hub with:

- unified event ingestion;
- run/session/tool-call state aggregation;
- Codex hook and Codex exec adapters;
- OpenCode and Hermes adapters;
- ntfy-first notification center;
- React widgets and Web Component embeds;
- future local sidecar and remote app support.

## Standard commands

Prefer these commands whenever possible:

```bash
pnpm install
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm check
```

If `just` is available:

```bash
just check
just dev
just test
just build
```

## Required workflow for autonomous tasks

1. Read the goal file completely.
2. Read relevant docs: `README.md`, `ARCHITECTURE.md`, `DEVELOPMENT.md`, `SECURITY.md`.
3. Split each goal into logical, reviewable subtasks.
4. Make the smallest complete change that satisfies the current subtask.
5. Prefer typed, tested, modular code.
6. Run the smallest relevant check before each commit.
7. Commit after each coherent passing subtask; do not squash goal commits.
8. Fix failures without expanding scope unnecessarily.
9. Update docs when behavior changes.
10. Run `just check` before the final stop; if `just` is unavailable, run `corepack pnpm check`.
11. Push the branch or `main` after a completed goal passes checks.
12. Summarize commits, commands, check results, working-tree status, risks and follow-up tasks.

The local queue runner is documented in `docs/codex/AUTONOMOUS_RUNNER.md`. It processes one goal at a time from `goals/ready`, writes runtime logs under `.agent/runs`, and must keep `MaxParallel` at `1` until explicit locking and conflict handling exist.

## ThesisYOLO mode

During thesis-defense YOLO mode:

- prefer forward progress over perfect architecture;
- keep PRs small enough to review later;
- auto-fix normal lint/type/test failures;
- do not ask for human confirmation unless the task crosses a hard safety boundary;
- record blocked high-risk changes as follow-up goals instead of interrupting the user.

## Hard safety boundaries

Do not do these unless the active goal explicitly authorizes them:

- commit `.env`, credentials, private keys, tokens or cookies;
- modify production secrets;
- modify `/opt/skybridge-agent-hub/.env`;
- alter server root-level OpenResty, Authelia, 1Panel or Docker daemon configuration;
- run destructive cleanup commands such as `rm -rf /`, `docker system prune -a --volumes`, or recursive removal of user home folders;
- force-push main;
- remove tests only to make checks pass;
- weaken authentication or authorization;
- add telemetry that uploads full command output or secrets by default.

## Event schema rule

All adapters must normalize source events into `skybridge.agent_event.v1` before handing them to the server or widgets.

Use these normalized event type families:

```text
session.*
run.*
turn.*
plan.*
todo.*
tool.*
file.*
diff.*
approval.*
message.*
agent.*
notification.*
```

## Definition of done

A goal is done only when:

- checks pass or the failure is clearly documented;
- each coherent passing subtask has its own commit;
- `just check` has passed before stopping, or the fallback/check failure is documented;
- the completed goal has been pushed unless blocked by credentials or remote access;
- the implementation is committed-ready;
- docs or goals are updated where relevant;
- no secrets are introduced;
- the final summary includes tests and residual risks.
