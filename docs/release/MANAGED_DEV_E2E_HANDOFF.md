# Managed Dev E2E Handoff

This document freezes the managed development end-to-end capability baseline at
the close of MG363.

## Current State

- Current main commit: `961b492fabdcc7a737043e83d906d6c8d3f4bf38`
- Current cloud image:
  `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-961b492fabdcc7a737043e83d906d6c8d3f4bf38`
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
- No task creation or claim outside explicitly scoped safe/manual goals.
- No unsanitized prompts, logs, process streams, sensitive browser/session
  material, provider auth material, proxy profiles, or environment snapshots in
  reports.
- `token_printed=false`

## Manual Audit

Run a read-only local handoff audit:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-dev-e2e-handoff.ps1 -Command audit -ExpectedCommit 961b492fabdcc7a737043e83d906d6c8d3f4bf38 -ExpectedCloudImage ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-961b492fabdcc7a737043e83d906d6c8d3f4bf38 -Json -WriteReport
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

1. MG367A Vite Chunk Remediation: split or defer the current web/desktop entry
   chunks only with explicit runtime-risk acceptance.
2. Hermes Planner Provider Pilot: add optional planner/provider integration
   without taking over SkyBridge state.
3. MCP Tool Provider Stub: define disabled/future MCP provider shape without
   connecting to live MCP servers.
4. Worker Service Install/Daemonization: recover the Windows worker service
   install/daemon path while keeping worker-loop start separately gated.

`token_printed=false`
