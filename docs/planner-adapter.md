# PlannerAdapter Runbook

`PlannerAdapter` is the neutral SkyBridge protocol for turning a goal into bounded work. Hermes may implement this protocol during dogfooding, but SkyBridge Core must also work with rule-based, manual or future planner adapters.

## Contract Shape

A planner returns one strict JSON object:

```json
{
  "decision": "continue",
  "reason": "Short operator-safe explanation.",
  "task": {
    "title": "Concise task title",
    "task_type": "docs",
    "risk": "low",
    "prompt": "Bounded task instructions for the executor.",
    "allowed_paths": ["docs/"],
    "blocked_paths": [".env", "config/", ".agent/", ".data/"],
    "validation": ["corepack pnpm check"]
  },
  "stop_criteria_status": ["round 1 of 3 docs-only proof planned"]
}
```

Protocol rules:

- `decision`, `reason` and `stop_criteria_status` are always required.
- `task` is required for `continue` and `repair`.
- `task` may be `null` for `wait`, `stop` or `blocked`.
- `task_type` should use the smallest useful category, usually `docs` for proof rounds.
- `risk` should be `low`, `medium` or `high`; Hermes self-bootstrap tasks should default to `low` or stop safely.
- `allowed_paths`, `blocked_paths` and `validation` must travel with the task so executors can enforce the planning boundary.
- Raw planner responses, prompts, secrets, credentials and full command output must not be stored in task metadata.

## Allowed Decisions

- `continue`: create one new low-risk task.
- `repair`: create one low-risk task that repairs a failed prior task without expanding scope.
- `wait`: create no task because an external result, worker or approval is pending.
- `stop`: create no task because the goal is complete or the proof has reached its stop criteria.
- `blocked`: create no task because required configuration, credentials, capacity or safety approval is missing.

## Safety Boundaries

Planner output must stay inside the same hard boundaries as the executor:

- Do not request edits to `.env`, credentials, private keys, tokens, cookies, production secrets or deployment credentials.
- Do not request changes under `config/`, `.agent/` or `.data/` unless a future goal explicitly authorizes that path.
- Do not request production deployment, server root configuration, GitHub settings, branch protection changes, force-pushes or public Hermes exposure.
- Do not upload raw command output, patches, logs, prompts or secrets to SkyBridge.
- Prefer docs-only tasks until the planner has proven safe behavior over multiple rounds.
- Keep `allowed_paths` narrow and `blocked_paths` explicit.

If a safe next task cannot be described with narrow paths and validation, the planner should choose `wait`, `stop` or `blocked`.

## Three-Round Docs-Only Proof

Before Hermes is trusted for broader planning, it should complete three consecutive docs-only planning rounds:

1. Round 1 creates or improves a small runbook or operator note.
2. Round 2 repairs or extends documentation based on the prior result without touching code or config.
3. Round 3 confirms the protocol by producing another narrowly scoped docs task or choosing `stop` when enough proof exists.

Each round must:

- use `task_type: "docs"` and `risk: "low"`;
- restrict `allowed_paths` to documentation or goal files only;
- include forbidden secret, config and local runtime paths in `blocked_paths`;
- include safe validation, normally `corepack pnpm check` or a narrower docs-safe check when available;
- update `stop_criteria_status` with whether the three-round proof is not started, in progress, complete, waiting or blocked.

The proof is complete only after three low-risk docs-only rounds finish without boundary violations. Any need for credentials, production configuration, raw logs, public Hermes exposure or non-docs edits should stop the proof as `blocked`.
