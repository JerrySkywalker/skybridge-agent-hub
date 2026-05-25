# Worker Pool And Task Core

SkyBridge Core owns durable, agent-agnostic state for worker availability, project intent and task execution. Hermes, Codex, OpenCode, GitHub and ntfy remain adapters or providers around that core, not required dependencies.

## Model

### Project

A project is the neutral container for development work. It names a repository or product area, records safe operator metadata and owns one or more master goals.

### MasterGoal

A master goal is a durable objective inside a project. Planner adapters may decompose a master goal into tasks, but the goal record itself is owned by SkyBridge Core.

### Worker

A worker is a runtime-capable machine or process that can claim and execute tasks through an executor adapter. Workers advertise capabilities and safe labels. They do not store secrets in SkyBridge Core.

### WorkerHeartbeat

A heartbeat records that a worker was seen at a point in time. Worker status is derived from the latest heartbeat plus the worker disabled flag:

- `online`
- `stale`
- `offline`
- `disabled`

### Task

A task is a queued unit of work under a project and optionally a master goal. Tasks store safe summaries, acceptance criteria, risk, source and adapter hints. They do not store raw unsafe prompts, command output, credentials or patches.

### TaskEvent

A task event is an immutable state-change or note for a task. Task events are the durable audit trail for claim, start, complete, fail, block and requeue actions.

### TaskClaim

A task claim records that a worker has taken responsibility for a queued task. Claims bind a task to a worker, a claim time and optional lease metadata.

### TaskResult

A task result records safe completion or failure metadata such as summary, result link, PR link and error summary. It excludes raw command output and secrets.

### TaskStatus

Supported task statuses are:

- `queued`
- `claimed`
- `running`
- `completed`
- `failed`
- `blocked`
- `cancelled`
- `stale`

### TaskRisk

Supported risk levels are:

- `low`
- `medium`
- `high`

High-risk tasks can be represented and reviewed, but this core does not add destructive controls or unattended approval.

### TaskSource

Supported task sources are neutral:

- `manual`
- `planner`
- `rule_based`
- `hermes`
- `codex`
- `opencode`
- `custom`

Concrete systems are optional adapter sources, not core requirements.

### WorkerCapability

Worker capabilities describe what execution modes a worker can support, for example:

- `manual-execution`
- `codex-exec`
- `opencode-exec`
- `filesystem`
- `git`
- `tests`
- `docs`
- `notifications`

Capabilities are safe strings and must not include credentials.

## Adapter Boundary

SkyBridge Core owns neutral state:

- projects;
- master goals;
- workers;
- worker heartbeats;
- task queue state;
- task events;
- safe summaries and result links.

Hermes is an optional `PlannerAdapter`. It may create or update tasks, but SkyBridge Core must work with the rule-based planner or manual task creation when Hermes is absent.

Codex, OpenCode and manual execution are `ExecutorAdapter` implementations. They may claim tasks and report results through the task API, but the task lifecycle does not require a specific executor.

GitHub is one `SCM/CIProvider`. Task result links may point to GitHub PRs or checks, but the core model should also support other SCM providers or no SCM provider.

ntfy is one `NotificationProvider`. Worker and task state must not depend on ntfy delivery.

## Safety

The core stores safe metadata only. It must not persist secrets, raw prompts, command output, full patches, private tokens, cookies or production environment values. Unsafe task text should be summarized into `prompt_summary` or a bounded safe `body`.

This milestone intentionally does not implement the full Edge Worker, public Hermes exposure, production deployment, remote destructive commands or an always-on planner loop.
