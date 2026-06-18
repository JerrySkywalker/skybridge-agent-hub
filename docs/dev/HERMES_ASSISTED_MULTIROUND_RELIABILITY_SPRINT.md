# Hermes-assisted Multi-round Reliability Sprint

Date: 2026-05-29

## Goal

Use Hermes as an advisory planner, SkyBridge as the deterministic policy/control plane, `laptop-zenbookduo` as the local executor, and GitHub PR/CI/evidence as completion authority for up to four low-risk reliability rounds.

## 178R Recovery Status

The sprint did not proceed to proposal persistence or task execution because the real Hermes preview path remained unstable at `/v1/responses`.

- Hermes endpoint: `https://api.hermes.example.com`.
- Direct HTTPS: `true`.
- Hermes health: `ok=true`.
- Capabilities route: succeeded.
- Tiny `/v1/responses` probe: succeeded in 2.8 seconds.
- Real `hermes-preview`: failed with `504 Gateway Time-out` from OpenResty during `/v1/responses`.
- Retry behavior: bounded preview retry was added with `MaxHermesAttempts=3`, `RetryDelaySeconds=10`, transient-only retry classification, compact-state default, and a 600 second timeout option.
- Compact state: added as the default for planner input. It includes project/control summaries, active task counts, recent task summaries, blocked/recovered summaries, worker summaries and recent PR/evidence summaries, but excludes raw task event arrays.
- OpenResty docs: hardened to recommend `proxy_read_timeout 600s`, `proxy_send_timeout 600s`, `proxy_connect_timeout 60s`, `send_timeout 600s`, `proxy_buffering off` and `proxy_request_buffering off`.

No `hermes-apply` was run. No proposals were persisted by this recovery pass, no proposals were converted, no worker `PollOnce` was run, and no cloud tasks were created.

## Final Cloud State

- Project control remained `paused`.
- No queued/running task residue was observed.
- Historical blocked task `task_proposal-59a0236fb69800cd` remained blocked and was not run.
- Recovered historical tasks remain evidence-backed.
- Token values were not printed.

## Server-side Next Action

Because capabilities and a tiny responses call both succeed but the real planner request still returns OpenResty `504`, the next repair target is the live direct HTTPS `/v1/responses` route for long-running planner responses. Verify the active OpenResty server block matches `docs/operations/openresty-hermes-api.example.conf`, especially the 600 second read/send timeouts and disabled buffering, then inspect OpenResty and Hermes API logs for upstream timeout, streaming flush, worker timeout, or request-body handling errors.

## Proof Status

Hermes-assisted multi-round reliability sprint is not yet proven. The recovery PR is useful because it makes the preview path retryable, reduces planner input size, documents the direct HTTPS 504 diagnosis path, and adds local smokes for the new recovery behavior.

## 178T Capability Normalization and Resume

Goal 178T resumed the sprint after the direct HTTPS `/v1/responses` path recovered.

- Branch: `ai/goal-178t-hermes-capability-normalization-resume`.
- Hermes endpoint: `https://api.hermes.example.com`.
- Direct HTTPS: `true`.
- Hermes health: `ok=true`.
- Hermes runtime mode: `server_agent`.
- Planner runtime mode: `real-api`.
- Planner mode: `hermes-preview`, then `hermes-apply`.
- Planner tool execution mode: `disabled`.
- Master goal id: `master-goal-hermes-assisted-multiround-reliability-sprint`.

The planner now preserves `original_required_capabilities`, adds `normalized_required_capabilities`, and runs policy checks against the normalized capabilities. Safe docs proposals under `docs/` and safe local-smoke proposals under `scripts/powershell/smoke-*.ps1` receive `codex` when Hermes omits it. Unsafe proposal types and high-risk surfaces remain blocked.

Preview counts:

- Before this normalization change in this branch: 7 proposals, 4 accepted, 2 ask-human, 1 rejected.
- After normalization: 8 proposals, 8 accepted, 0 ask-human, 0 rejected.

`hermes-apply` persisted planning session `planning-session-a2e63e1b5456ef84` with 6 executable-policy proposals. Two proposals were selected for bounded execution because they had complete acceptance criteria and evidence requirements:

| Round | Proposal | Task | Child PR | Status |
| --- | --- | --- | --- | --- |
| 1 | `proposal-331d222d4d38a3af` Failed task pattern analysis | `task_proposal-331d222d4d38a3af` | [#76](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/76) | merged, recovered evidence |
| 2 | `proposal-ca9b20ca044e8119` CI recovery quick-reference runbook | `task_proposal-ca9b20ca044e8119` | [#77](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/77) | merged, recovered evidence |

Round outcomes:

- Round 1 changed only `docs/failed-task-patterns.md`; checks passed; PR #76 merged at `fb4ffc41e4385cd3123e1010032ef50ebd7dd3d6`; evidence repaired with `ci_status=passed_after_pending`.
- Round 2 changed only `docs/ci-recovery-runbook.md`; checks passed; PR #77 merged at `a6bed1bab86abb45e245946a34e1c6d4f3659353`; evidence repaired with `ci_status=passed_after_pending`.
- No local-smoke proposal was executed in 178T.
- Historical `task_proposal-59a0236fb69800cd` was not run directly.

The sprint stopped after two completed rounds rather than forcing a third proposal with incomplete acceptance/evidence fields. Project control was paused after each PollOnce and no queued/running residue remained.

Proof status: Hermes-assisted multi-round reliability sprint is proven for two bounded low-risk docs rounds with proposal normalization, persistence, targeted PollOnce execution, child PR checks, merge and evidence repair.
