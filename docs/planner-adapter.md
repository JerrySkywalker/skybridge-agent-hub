# PlannerAdapter Runbook

PlannerAdapter is a neutral SkyBridge adapter role. Hermes can implement it, but SkyBridge Core must also work with rule-based, manual or future planner adapters.

## Decision Loop

1. Receive a bounded SkyBridge state snapshot: current project or goal, recent task status, worker capacity, validation result summaries and safe stop-criteria status.
2. Decide whether SkyBridge should create work, repair work, wait, stop or mark the goal blocked.
3. Return exactly one strict JSON object. Do not include prose around the JSON.
4. SkyBridge validates and bounds the response before creating any task metadata. Raw planner responses are not stored.

Allowed decisions:

- `continue`: create a new task from the current goal state.
- `repair`: create a focused repair task for a failed or incomplete prior task.
- `wait`: create no task because an external result, worker capacity or validation is still pending.
- `stop`: create no task because the goal is complete or no more work is useful.
- `blocked`: create no task because progress requires missing configuration, credentials, approval or unsafe access.

## JSON Contract

Use this shape:

```json
{
  "decision": "continue|repair|wait|stop|blocked",
  "reason": "One concise safe reason.",
  "task": {
    "title": "Short task title",
    "task_type": "docs",
    "risk": "low",
    "prompt": "Bounded executor prompt.",
    "allowed_paths": ["docs/"],
    "blocked_paths": [".env", "config/*.secret.ps1", ".agent/", ".data/"],
    "validation": ["corepack pnpm check"]
  },
  "stop_criteria_status": ["Goal state summary."]
}
```

`task` is required for `continue` and `repair`. For `wait`, `stop` and `blocked`, set `task` to `null` or omit it. `reason`, `allowed_paths`, `blocked_paths`, `validation` and `stop_criteria_status` must contain safe summaries only.

## Safety Boundaries

- Normalize all planner-created telemetry and task metadata through `skybridge.agent_event.v1` before ingestion.
- Keep allowed paths narrow and match the task risk.
- Do not request edits to secrets, `.env` files, credentials, production config, GitHub settings, branch protection or server root configuration.
- Do not upload raw prompts, command output, logs, patches, cookies, tokens or private keys to SkyBridge.
- Do not ask the executor to weaken authentication, authorization or redaction.
- Choose `blocked`, `wait` or `stop` instead of creating work when the safe next action is unclear.

## Minimal Example

```json
{
  "decision": "continue",
  "reason": "The next safe step is a documentation clarification.",
  "task": {
    "title": "Clarify adapter status docs",
    "task_type": "docs",
    "risk": "low",
    "prompt": "Update the adapter docs with a short status note. Keep the change documentation-only.",
    "allowed_paths": ["docs/adapters/"],
    "blocked_paths": [".env", "config/*.secret.ps1", ".agent/", ".data/"],
    "validation": ["corepack pnpm check"]
  },
  "stop_criteria_status": ["Self-bootstrap documentation proof is in progress."]
}
```

See also [Hermes PlannerAdapter](orchestrator/HERMES_PLANNER_ADAPTER.md) for the current Hermes-specific runbook.
