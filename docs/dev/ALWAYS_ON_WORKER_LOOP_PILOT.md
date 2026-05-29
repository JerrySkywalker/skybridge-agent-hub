# Always-On Worker Loop Pilot

Status: bounded pilot proven for `laptop-zenbookduo` on 2026-05-29.

This pilot exercises the always-on Edge Worker loop in the smallest useful real mode: one local trusted laptop, a low-risk docs-only task queue, a hard task cap, an idle timeout and stop-on-failure enabled. It is intended to prove that the worker can stay available long enough to claim and finish bounded work, package child PRs and then return the project to a paused state without becoming an unbounded background executor.

## Scope

- Worker target: `laptop-zenbookduo`.
- Project: `skybridge-agent-hub`.
- Worker mode: Edge Worker `-Loop` mode, not the older local Markdown goal runner.
- Task type: low-risk child tasks only, preferably docs-only for the first run.
- Parent branch: clean local checkout tracking the intended upstream base.
- Local logs: `.agent/edge-worker-loop/<timestamp>/` and `.agent/workers/<worker>/<task>/`.
- SkyBridge evidence: concise task state, safe summaries, child PR links and CI status only.

Out of scope:

- production deployment;
- server root, OpenResty, Authelia, 1Panel or Docker daemon changes;
- secret rotation or `.env` edits;
- public remote worker exposure;
- force-pushes, branch protection changes or raw log upload.

## Pilot Bounds

Start project control with a small `MaxTasks` value before launching the loop. The first real pilot used `MaxTasks=1`; later pilots may use up to `MaxTasks=3` only when the queued tasks are already validated as low-risk docs or explicitly safe local-smoke work.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command start `
  -ProjectId skybridge-agent-hub `
  -MaxTasks 1
```

Then launch the real loop only after a dry run, with an idle timeout and stop-on-failure:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -Loop `
  -MaxTasks 1 `
  -PollIntervalSeconds 30 `
  -IdleTimeoutSeconds 600 `
  -StopOnFailure `
  -Json
```

The loop must stop when any of these happens:

- the configured task cap is reached;
- no eligible work appears before `IdleTimeoutSeconds=600`;
- project control is paused or stopped;
- the worker detects degraded real-run state before claiming new work;
- any task fails while `-StopOnFailure` is set.

## Expected Child PR Evidence

Each successful child task should produce a reviewable child PR created by the worker after validation passes. The PR or task evidence should show:

- task ID and worker ID;
- child branch name;
- draft PR URL;
- changed-file list limited to the task scope;
- validation command summary, usually worker-configured `just check` or the configured fallback;
- CI Guardian result with auto-merge disabled unless explicitly enabled by policy;
- final task status reported to SkyBridge with a bounded safe summary.

CI evidence should be captured as status names, conclusions and PR links, not raw command output. If CI is blocked by infrastructure, record a bounded failure or recovered-evidence summary instead of rewriting the original task history.

## Expected Final State

At the end of the pilot, the project should be paused even when the loop exits normally:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command pause `
  -ProjectId skybridge-agent-hub
```

Final operator checks should confirm:

- project control is `paused`;
- no worker loop process is still polling for new work;
- the last loop stop reason is recorded locally;
- each claimed task is completed, failed with bounded evidence or still explicitly visible for follow-up;
- every child PR has CI evidence or a documented CI blocker;
- no secrets, `.env` files, production config or raw command logs were uploaded to SkyBridge.

The pilot is successful only if `laptop-zenbookduo` proves bounded always-on behavior and leaves the system in an inspectable paused state.

## 2026-05-29 Pilot Result

The first real pilot used the cloud SkyBridge queue and `laptop-zenbookduo` with:

- `MaxTasks=1`
- `IdleTimeoutSeconds=120`
- `PollIntervalSeconds=5`
- `StopOnFailure=true`
- project `skybridge-agent-hub`
- goal `master-goal-always-on-worker-loop-pilot`

The first queued task, `always-on-worker-loop-pilot-docs-179`, was blocked before execution because its required capabilities included `docs`, while the worker profile advertises `codex`, `git`, `gh`, `node`, `pnpm`, `powershell`, `windows` and `laptop`. The corrected task, `always-on-worker-loop-pilot-docs-179b`, required `codex` and `git`, restricted `allowed_paths` to `docs/dev/ALWAYS_ON_WORKER_LOOP_PILOT.md`, and was the only queued/running task before the loop.

The loop claimed exactly one task, Codex completed without transport retry, changed only `docs/dev/ALWAYS_ON_WORKER_LOOP_PILOT.md`, and opened child PR [#79](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/79). CI Guardian stopped the loop while checks were pending, so the cloud task initially recorded `failed` and the loop exited with `stop_reason=failure`; the loop finalizer still restored project control to `paused` with `stop_requested=false`.

PR #79 passed AI branch validation, Project check, Docker build server and Docker build web, then merged at `39e554b4c3fe704133bb0f3d0b0c46b442c43330`. Evidence repair recorded `recovered=true`, `ci_status=passed_after_pending`, `risk_status=low_docs_only`, the PR URL and changed file list for `always-on-worker-loop-pilot-docs-179b`.

The pilot is proven for one low-risk docs task. Before larger batches, task preparation should align `required_capabilities` with executable worker tools. `docs` is a `task_type`, not a hard worker capability; docs tasks should normalize toward `codex`, `git` and `gh` when their expected files are under `docs/`.
