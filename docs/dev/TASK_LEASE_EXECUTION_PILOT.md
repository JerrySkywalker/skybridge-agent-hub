# Task Lease Execution Pilot

Milestone 183 records the first docs-only task lease execution evidence artifact after task lease and workspace safety hardening.

## Task

- Task ID: `task_proposal-a3d7d8d55b54455e`
- Title: `Record task lease execution evidence for milestone 183`
- Source: planner
- Risk: low
- Scope: documentation only
- Evidence file: `docs/dev/TASK_LEASE_EXECUTION_PILOT.md`

## Lease Acquisition

The task lease flow for this pilot is:

1. The SkyBridge control plane exposes one queued low-risk documentation task.
2. A compatible edge worker polls for work with `MaxParallel=1`.
3. The worker claims the task and receives an active lease before execution starts.
4. The task detail carries the lease boundary used by the local execution guard:
   - task ID;
   - worker ID;
   - project ID;
   - lease ID;
   - claimed time;
   - lease expiry time;
   - heartbeat time;
   - current attempt and maximum attempts;
   - lease status.
5. The worker refuses Codex execution if the claimed task does not include an active lease for the current worker.

The lease is the execution authority for this task. A queued task without an active matching lease remains visible work, but it is not executable by the local worker.

## Execution Scope

This pilot is intentionally narrow:

- modify documentation only;
- create or update only this milestone 183 evidence artifact;
- do not change TypeScript, scripts, package metadata, configuration or deployment files;
- do not read, edit or commit `.env` files, credentials, tokens, private keys or cookies;
- do not alter production settings, server root configuration, GitHub settings or branch protection;
- do not upload raw command output, prompts, patches, Codex JSONL logs or secrets to SkyBridge;
- leave commit, push and draft PR creation to the edge worker after validation.

The local workspace safety boundary remains the one documented in `docs/dev/TASK_LEASE_AND_WORKSPACE_SAFETY.md`: a dirty worktree, stale lock, colliding branch, existing child PR or missing active lease blocks worker execution before Codex starts.

## Completion Confirmation

Completion evidence for this task is this checked-in documentation artifact. It confirms:

- the task had a single low-risk documentation objective;
- the expected worker path is claim -> active lease -> docs-only Codex execution -> validation handoff;
- the lease boundary is the authority that permits local execution;
- the scope excluded code, configuration, secrets, production systems and GitHub settings;
- the final worker-owned steps are validation, safe evidence reporting, commit, push and draft PR creation.

For audit purposes, SkyBridge should store only concise task evidence such as task ID, status, changed documentation path, validation summary and child PR metadata. Raw command output and sensitive local files remain outside the SkyBridge task evidence payload.

## Milestone 183 Result

Result: milestone 183 has a static audit artifact documenting the task lease execution flow, the execution boundaries and the expected completion evidence for a low-risk docs-only task.
