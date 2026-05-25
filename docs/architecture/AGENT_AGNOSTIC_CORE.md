# Agent-Agnostic Core Boundary

SkyBridge is an agent-agnostic control plane for AI-assisted software development.

It provides project/goal/task orchestration, worker pool management, run/event/audit logging, CI/PR/auto-merge policy, notification routing and an operator dashboard. Agent systems such as Hermes, Codex, OpenCode or future tools connect through adapters.

## SkyBridge Core

SkyBridge Core owns neutral product state and policy:

- projects, goals, work orders and task state;
- normalized `skybridge.agent_event.v1` ingestion;
- run/session/tool-call aggregation;
- audit records and approval metadata;
- CI/PR/auto-merge policy records;
- notification jobs and routing decisions;
- provider capability and health status;
- API, SSE and Operator Console read models.

Core must stay useful when Hermes, Codex, GitHub and ntfy are all absent. The rule-based planner and manual executor fixtures exist to keep that boundary testable.

## Adapter Ring

The adapter ring translates external tools and providers into neutral SkyBridge contracts.

```text
PlannerAdapter -> PlannerDecision -> WorkOrder
ExecutorAdapter -> ExecutionResult -> skybridge.agent_event.v1
SCMProvider -> PR/CI policy records
NotificationProvider -> NotificationJob delivery result
RuntimeProvider -> worker/node status and event forwarding
```

Adapters may be stable, experimental, fixture-backed or dogfooding. Adapter-specific code can mention concrete systems directly, but core APIs should expose neutral roles and capabilities.

## PlannerAdapter

A planner adapter turns a goal into one or more `WorkOrder` records. Examples:

- Hermes planner/supervisor adapter: dogfooding.
- Rule-based planner adapter: fixture-backed proof that Hermes is optional.
- Future product planners: custom or hosted agents.

## ExecutorAdapter

An executor adapter performs or records work for a `WorkOrder` and returns an `ExecutionResult`. Examples:

- Codex exec/hook adapters: dogfooding.
- OpenCode plugin adapter: fixture-backed.
- Manual executor adapter: fixture-backed proof that Codex is optional.

## SCMProvider

An SCM/CI provider reports pull request, branch, check and auto-merge policy state. GitHub is the current dogfooding provider. Core policy must not require GitHub settings mutation, GitHub-specific branch protection or GitHub-hosted CI.

## NotificationProvider

A notification provider delivers a `NotificationJob` or records a skipped/failed placeholder. ntfy is the first provider and bootstrap fallback, not a core dependency.

## RuntimeProvider

A runtime provider reports worker/node availability and may forward normalized events. The local sidecar is the current experimental runtime provider. Future remote workers must stay behind auth, approval and audit boundaries.

## Dogfooding Adapters

SkyBridge is currently developed with Hermes, Codex, GitHub Actions and ntfy. Those adapters are valuable because they exercise the product, but they must remain optional:

- Hermes is a planner/supervisor adapter.
- Codex is an executor/telemetry adapter.
- GitHub is an SCM/CI provider.
- ntfy is a notification provider.

## What Must Not Enter Core

Core must not depend on:

- Hermes API keys, tunnel paths, prompts or cloud endpoint shape;
- Codex CLI flags, hook file paths, JSONL logs or prompt formats;
- OpenCode plugin internals;
- GitHub-only branch protection, Actions or auto-merge assumptions;
- ntfy topic URLs, tokens or phone-notification assumptions;
- raw prompts, command output, patches, stdout/stderr, tool results or secrets;
- production deployment credentials or host-level server configuration.

When concrete behavior is necessary, place it in an adapter package, script, config example or adapter-specific doc and normalize the output before it reaches core.
