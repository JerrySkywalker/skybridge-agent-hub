# Hermes-assisted Multi-round Reliability Sprint

Date: 2026-05-29

## Goal

Use Hermes as an advisory planner, SkyBridge as the deterministic policy/control plane, `laptop-zenbookduo` as the local executor, and GitHub PR/CI/evidence as completion authority for up to four low-risk reliability rounds.

## 178R Recovery Status

The sprint did not proceed to proposal persistence or task execution because the real Hermes preview path remained unstable at `/v1/responses`.

- Hermes endpoint: `https://api.hermes.jerryskywalker.space`.
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
