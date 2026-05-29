# Always-On Worker Loop Pilot

Status: bounded pilot plan for `laptop-zenbookduo`.

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

Start project control with a small `MaxTasks` value before launching the loop. For the first pilot, use `MaxTasks=2` at the project-control layer and pass the same cap to the worker loop:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command start `
  -ProjectId skybridge-agent-hub `
  -MaxTasks 2
```

Then launch the real loop only after a dry run, with an idle timeout and stop-on-failure:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -Loop `
  -MaxTasks 2 `
  -PollIntervalSeconds 30 `
  -IdleTimeoutSeconds 600 `
  -StopOnFailure `
  -Json
```

The loop must stop when any of these happens:

- two tasks are completed or otherwise terminal under the pilot cap;
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
