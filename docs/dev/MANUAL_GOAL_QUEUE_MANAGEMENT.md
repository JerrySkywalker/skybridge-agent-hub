# Manual Goal Queue Management

Goal 195 adds the reviewable authoring layer for manual campaign queues. It is local/offline by default and does not execute campaign steps.

## Proposed Goals

Proposed goals are not campaign goals. They live under `goals/proposed/` with review metadata, content hash, safety classification and `token_printed=false`.

Goal 199 can generate fixture drafts for human review. Import remains a separate Goal 200 workflow so a generated goal cannot approve or execute itself.

Goal 200 adds the controlled review/import command surface. Proposed drafts can be approved, rejected, edited or superseded with audit metadata. Import preview reports target path, manifest diff, dependency/order changes and hash changes. Import apply is approved-only, reason-gated and stages into `goals/reviewed/` by default, leaving execution disabled.

## Author A Goal Pack

A goal pack is a directory with `campaign.skybridge.json` and one markdown file per goal. Use the templates in `goals/templates/`:

- `super-goal.md`
- `patch-goal.md`
- `recovery-goal.md`
- `dashboard-control-goal.md`
- `worker-service-goal.md`
- `generated-proposed-goal.md`

Each markdown file starts with `skybridge.super_goal.v1` metadata and includes context, mission, hard safety boundaries, allowed scope, validation, evidence requirements, final campaign state, a no-execution statement and `token_printed=false`.

## Validate A Pack

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-pack.ps1 `
  -Command validate `
  -GoalPackDir goals/dev-queue-189-200 `
  -Json
```

Validation checks duplicate ids, duplicate order, missing markdown files, missing dependencies, dependency cycles, invalid allowed/blocked task types, required safety sections, evidence requirements, goal order/dependency mismatches and manifest hash drift.

## Update Manifest Hashes

Preview is the default:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-pack.ps1 `
  -Command manifest-preview `
  -GoalPackDir goals/dev-queue-189-200 `
  -Json
```

Write local manifest hash updates only with explicit `-Apply`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-pack.ps1 `
  -Command manifest-update `
  -GoalPackDir goals/dev-queue-189-200 `
  -Apply `
  -Json
```

This updates repository-local manifest metadata only. It does not import, advance, start, resume, claim or execute queue steps.

## Review Hash Drift

If a markdown file changes after hashes are recorded, `validate` reports `hash_drift_count` and lists drifted goals in the helper output. Review the markdown change, then run `manifest-preview` before applying a manifest hash update.

## Preview Re-import Or Update

Compare a revised local pack with an existing manifest without mutating live campaign state:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-pack.ps1 `
  -Command reimport-preview `
  -GoalPackDir .agent/tmp/revised-pack `
  -ExistingManifestFile goals/dev-queue-189-200/campaign.skybridge.json `
  -Json
```

The preview reports added, removed and changed goals, hash drift, dependency changes, order changes, safety policy changes, whether the update is safe and the proposed action. Apply-mode live campaign import/update is not part of Goal 195.

## Preview Archive

Archive preview describes the safe target and excluded material:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-pack.ps1 `
  -Command archive-preview `
  -GoalPackDir goals/dev-queue-189-200 `
  -Json
```

The default target is under ignored `.agent/tmp/campaign-archives/<campaign-id>`. Archives may include completed campaign manifests, goal markdown, completed goal reports, safe evidence snapshots and generated reports. Archives must exclude raw worker logs, raw stdout/stderr, raw prompts, tokens, Authorization headers, cookies, private keys and `.env` files.

## Desktop/Web Review Surfaces

Desktop and Web render a read-only manual goal queue review panel with:

- goal pack id;
- current campaign pack hash;
- validation result and warnings/errors;
- hash drift summary;
- dependency/order status;
- re-import preview summary;
- archive preview summary;
- explicit no-execution state.

The surfaces expose no Start One, Start Queue, Resume Apply, task claim, task execution, worker-loop start or arbitrary shell controls.

## Safe Summary

`skybridge.campaign_safe_summary.v1` now includes goal pack id, validation result, hash drift count, dependency/order status, proposed import/update action and `token_printed=false`.

## Why Goal 195 Does Not Execute The Queue

Goal 195 prepares queue authoring and review. It does not run `start-one`, `start-all`, `resume -Apply`, worker loops, Codex worker execution, task claim, campaign-step task creation, live campaign update or real queue start. All helper commands are dry-run/read/offline by default unless they write local manifest or ignored archive fixture metadata with explicit `-Apply`.

## Tool Provider Inventory Boundary

MG351 adds `skybridge.tool_provider.v1` as read-only local evidence for later
queue and campaign controllers. The inventory answers which Windows-local tools
are detected, which provider owns them today and which capabilities remain
disabled, but it does not authorize a queue step to run. Direct local runners
are the current default for proven Codex and MATLAB paths. Hermes is optional
for planning, gating or provider status. MCP is future/disabled. A future queue
controller must still require a fixed template, an allowlist, an execution gate,
exact confirmation and sanitized evidence before creating or claiming work.

MG352 adds the first one-step controller that uses this evidence. It is not a
queue start command: it previews one campaign step and can apply exactly one
`safe-local-smoke.v1` task with exact confirmation. It must stop after evidence
attachment and step completion, and it must not continue into a second queue
item or campaign step.

MG353 adds the M3 static multi-step manual controller. It still is not a queue
start command: it operates on one fixed three-step campaign, selects only the
first dependency-ready static step and requires an exact confirmation for each
`apply-next`. Fixture mode can prove safe-local-smoke, fixed MATLAB and fixed
Codex report steps in order without live tool calls. It does not generate,
append, import or execute arbitrary queue goals.

## Goal 196 Follow-on

Goal 196 builds multi-campaign locking on this foundation by treating the validated goal pack, hash drift summary, dependency order and proposed update action as review inputs. It adds explicit campaign lock ownership, repo-exclusive locks, stale recovery previews, reason-gated fixture recovery, cancel/abort/hold semantics and deterministic priority selection before any queue can start across multiple campaigns.

## Goal 198 Project Profile Defaults

Goal 198 adds project profile `goal_pack` defaults. A profile names the default goal pack directory and allowed goal pack directories, but `goal_pack.import_apply_enabled=false` remains mandatory. Invalid or out-of-repo goal pack paths are rejected by profile validation.

This keeps Goal 195 authoring/review separate from multi-project selection. Project selection can preview which goal pack would apply, but it does not import, update, archive, execute, claim or start any queue step.
