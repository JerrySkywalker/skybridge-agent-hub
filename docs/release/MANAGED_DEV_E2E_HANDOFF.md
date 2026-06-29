# Managed Dev E2E Handoff

This document freezes the managed development end-to-end capability baseline
through Stage S1.1, closing MG351-MG366C.

## Current State

- Current main commit: `c2bd551370f68950c2cd759de6a4f30b5e0396d8`
- Current cloud image:
  `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-c2bd551370f68950c2cd759de6a4f30b5e0396d8`
- Cloud health: `/v1/health` ok
- Cloud version: `/v1/version` matches the current main commit
- Cloud parity: ok
- `token_printed=false`

## Capability Matrix

| Milestone | Capability | Status | Manual entrypoint |
| --- | --- | --- | --- |
| M1 | Tool Provider Inventory | Complete. Direct provider available; Codex and MATLAB detected; Hermes optional/unavailable; MCP future. | `scripts/powershell/manual-tool-provider-check.ps1` |
| M2 | Single Goal Loop | Complete. Fixture passed and live `safe-local-smoke` passed after heartbeat apply. | `scripts/powershell/manual-single-goal-loop-test.ps1` |
| M3 | Static Multi-Step Campaign | Complete. Fixture sequenced safe-local-smoke, MATLAB, and Codex-report steps with evidence. | `scripts/powershell/manual-multi-goal-loop-test.ps1` |
| M4 | Local Codex Goal Markdown Generator | Complete. Fixture and local Codex generate-one passed; candidate remained unimported. | `scripts/powershell/manual-local-goal-generate-test.ps1` |
| M5 | Goal Append Review/Import | Complete. Candidate review, approval, and metadata append passed with no execution. | `scripts/powershell/manual-goal-append-review-test.ps1` |
| M6 | Bounded Goal Budget Loop | Complete. Ready-step, reviewed append, proposed generation, and budget-exhausted hold scenarios passed. | `scripts/powershell/manual-bounded-goal-loop-test.ps1` |
| M7 | Managed Development PR Pilot | Complete. Controller-native Git/GH path repaired; draft PR creation, CI observation, and human-review gate proven. | `scripts/powershell/manual-managed-dev-pr-pilot.ps1` |
| M8 | Campaign-Driven Managed Dev E2E | Complete. Reviewed goal to campaign step to bounded action to draft PR to CI to human review and merge gate passed. | `scripts/powershell/manual-managed-dev-campaign-test.ps1` |

## Post-Freeze Real Task

MG365 is the first managed-dev v2 real low-risk task after the M1-M8 freeze.
It inventories warning hygiene only:

- `docs/dev/WARNING_INVENTORY.md`
- `scripts/powershell/skybridge-warning-inventory.ps1`

The inventory tracks Vite chunk-size warnings and GitHub Actions Node.js 20
deprecation annotations as non-failing, tracked, and not suppressed. It does
not remediate either warning class, does not change build configuration, does
not change GitHub workflows, and does not alter CI thresholds. Remediation
requires a future explicit goal.

MG366B is the first warning remediation goal after that inventory. It updates
only Docker GitHub Action major versions to Node.js 24 runtime candidates and
does not change workflow topology, permissions, triggers, secrets, deploy
targets, Docker build semantics, warning suppression or CI thresholds. See
`docs/dev/ACTIONS_NODE_RUNTIME_HYGIENE.md`.

MG366A analyzes the remaining Vite chunk-size warning without changing build
behavior. It records the current oversized web and desktop entry chunks, likely
single-entry bundle causes, and remediation options. It does not suppress the
warning, raise Vite thresholds, change CI, change dependencies or perform
runtime chunk splitting. See `docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md`.

MG366C adds the Hermes Planner Provider Pilot as an advisory-only provider
surface. Fixture mode can generate one unapproved candidate markdown file, but
Hermes cannot approve, append, create tasks, execute, create branches or PRs,
merge, deploy, run worker loops or mutate `project_control`. Direct providers
remain the execution path. See
`docs/orchestrator/HERMES_PLANNER_PROVIDER.md`.

MG368A starts the Ratatui Operator Console as the next-stage manual simulation
surface. It is fixture/read-only only, shows the pipeline layout and safety
state, and keeps candidate append, goal start, task claim, worker loops, Hermes
live calls and MCP runs disabled until later reviewed gates.

MG368B keeps the same read-only boundary and adds live monitor value: the TUI
can read local Git branch/HEAD, local `main` and `origin/main` alignment,
bounded worktree status, cloud `/v1/health`, cloud `/v1/version`, cloud image
tag and route parity. It still does not append goals, approve candidates, start
goals, pause, terminate, create branches or PRs, merge, deploy, call Hermes
live, call MCP, start a worker loop or run a queue runner.

## Stage S1.1 Close

MG367 closes Stage S1.1 as a roadmap-freeze milestone. The stage close records
the final MG351-MG366C main/cloud baseline, keeps the same safety boundaries,
and adds only read-only audit and smoke wiring. See
`docs/release/STAGE_S1_1_CLOSE.md` and
`scripts/powershell/skybridge-stage-s1-1-close.ps1`.

## PR Evidence

- PR #267: Tool Provider Contract and Local Direct Provider Inventory
- PR #268: Local+Cloud Single Goal Loop Controller
- PR #269: Multi-Step Static Campaign Loop
- PR #270: Local Codex Goal Markdown Generator
- PR #271: Goal Append Review and Import
- PR #272: Bounded Goal Budget Loop
- PR #273: Managed Development PR Pilot
- PR #274: closed, not merged, superseded fallback proof
- PR #275: Managed Dev Git/GH Provider Repair
- PR #276: merged controller-native managed-dev pilot proof
- PR #277: Campaign-Driven Managed Dev E2E implementation
- PR #278: managed-dev campaign delegate repair
- PR #279: merged campaign-driven managed-dev pilot proof
- PR #280: Managed Dev E2E handoff and capability freeze
- PR #281: Warning inventory real task
- PR #282: GitHub Actions Node runtime hygiene
- PR #283: Vite chunk warning analysis
- PR #284: Hermes Planner Provider Pilot

## Safety Boundary

- No auto-merge by default.
- No unbounded loop.
- No worker loop.
- No queue runner.
- No release, tag, or asset mutation.
- No production infrastructure mutation.
- No arbitrary shell surface.
- No Codex generation or execution unless a future exact goal authorizes it.
- No MATLAB, Hermes, or MCP execution.
- Hermes planner/provider output requires human review before append and cannot
  execute in the same invocation.
- No task creation or claim outside explicitly scoped safe/manual goals.
- No unsanitized prompts, logs, process streams, sensitive browser/session
  material, provider auth material, proxy profiles, or environment snapshots in
  reports.
- `token_printed=false`

## Manual Audit

Run a read-only local handoff audit:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-dev-e2e-handoff.ps1 -Command audit -ExpectedCommit c2bd551370f68950c2cd759de6a4f30b5e0396d8 -ExpectedCloudImage ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-c2bd551370f68950c2cd759de6a4f30b5e0396d8 -Json -WriteReport
```

The audit is read-only. It must not mutate Git, GitHub PR state, deployment,
tasks, worker state, or provider state.

## Known Warnings

- Existing Vite chunk-size warnings remain non-failing, tracked and analyzed in
  `docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md`.
- GitHub Actions Node.js 20 deprecation annotations for Docker actions were
  remediated by MG366B action-version hygiene.
- Cloud deploy workflow run selection hygiene may need a future cleanup if older
  failed workflow runs are still selected by legacy verification helpers.

## Recommended Next Milestones

1. MG368C Candidate Review/Append Console: review and append one candidate only
   behind a later explicit gate.
2. MG368D Single-step Goal Control Gate: expose one reviewed single-step control
   path without unbounded queue execution.
3. MG369 Manual Single-step Hosted-dev Experiment: run the first manual
   single-step hosted-dev experiment through the TUI after the gates above.

`token_printed=false`
