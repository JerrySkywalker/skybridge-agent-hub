# SkyBridge Goal-Centric Control Plane

This document records the product vision and architecture boundary for SkyBridge after the first Hermes/Codex self-bootstrap milestones.

It defines durable concepts SkyBridge should own without binding the product to one model vendor, one agent runtime, one CLI, one database implementation or one deployment topology.

## Positioning

SkyBridge is a goal-centric, agent-agnostic control plane for AI-assisted software development.

It provides:

- project, goal and task orchestration;
- worker pool management;
- run, event, evidence and audit logging;
- CI, PR and auto-merge policy;
- notification routing;
- an operator dashboard.

Agent systems such as Hermes, Codex, OpenCode, Aider, future local agents or future cloud agents connect through adapters.

SkyBridge does not orchestrate models directly. SkyBridge orchestrates goals, tasks, workers, evidence and policies. Model selection happens behind planner, executor or supervisor adapters.

## Core principle

Goal is the core asset.

A goal is not just a prompt. A goal is a durable task contract that can move across models, machines and execution runtimes. It records what should be achieved, why it matters, how success is judged, what risks exist, who or what can execute it, and what evidence must be returned.

The stable hierarchy is:

```text
Goal
  -> Task / WorkOrder
  -> Run
  -> Evidence
```

- **Goal** is the long-lived intent and acceptance contract.
- **Task / WorkOrder** is the schedulable execution unit derived from a goal.
- **Run** is one execution attempt by a worker or executor.
- **Evidence** is the proof used to evaluate completion: PRs, diffs, changed files, CI results, validation logs, summaries and human decisions.

A model saying a task is complete is not enough. Completion must be based on evidence.

## Cloud control plane and local execution plane

SkyBridge should support a cloud-control-plane plus local-execution-plane topology.

The control plane owns long-lived state:

- project registry;
- goal registry;
- goal queue and lifecycle;
- task queue and lifecycle;
- worker registry and heartbeat;
- run and evidence history;
- PR/CI lifecycle decisions;
- notification history;
- audit records.

The execution plane owns local execution:

- reading the working tree;
- running Codex or other executors;
- editing files;
- running tests, builds, lint and smoke checks;
- packaging commits and PRs;
- returning evidence.

Local machines may keep execution copies, prompt files, Codex JSONL, last-message summaries and validation logs. Those are runtime artifacts. They are not the authoritative state.

The authoritative state belongs to the SkyBridge Server.

## Distributed goal generation, centralized goal governance

Goals may be generated anywhere:

- by a human operator;
- by a local Codex session;
- by a Hermes planner;
- by a rule-based planner;
- from GitHub issues;
- from failed runs;
- from logs, reports or roadmap documents;
- by future agents or tools.

However, all goals must return to the SkyBridge Goal Registry for governance.

SkyBridge should normalize, validate and govern goals before execution:

- structure validation;
- deduplication;
- priority assignment;
- risk classification;
- dependency checks;
- stale-context checks;
- evidence requirement checks;
- human-review gates;
- task decomposition and scheduling.

A generated goal is only a candidate until SkyBridge accepts it.

## Adapter boundary

SkyBridge Core should not depend on Hermes, Codex, GitHub, ntfy, DeepSeek, OpenAI, Claude or any specific tool.

Core depends on neutral abstractions:

- PlannerAdapter;
- ExecutorAdapter;
- SCM/CI Provider;
- NotificationProvider;
- RuntimeProvider;
- ModelBackend metadata when useful for audit.

### Planner adapters

Planner adapters produce or evaluate goals and tasks.

Hermes is currently the primary dogfooding Planner/Supervisor Adapter. It can call different model backends internally, including DeepSeek, OpenAI-compatible models, Claude-compatible models or future backends.

DeepSeek is not a SkyBridge-native component. It is one possible model backend behind Hermes or another adapter.

SkyBridge may record model metadata for audit, such as `planner_adapter=hermes`, `model_provider=deepseek`, or `model=hermes-agent`, but SkyBridge Core must not require those specific names.

### Executor adapters

Executor adapters execute tasks.

Codex CLI is the current primary dogfooding executor. OpenCode, manual execution, Aider or future executor agents should connect through the same neutral task/run/evidence contract.

### SCM/CI providers

GitHub is the current SCM/CI provider. It supplies PRs, checks, branch protection and auto-merge. Future providers should be possible.

### Notification providers

ntfy is the current bootstrap and phone notification provider. It is a provider, not the state store or task queue.

## Worker pool principle

Workers join the SkyBridge pool. The control plane assigns work; workers claim work.

Recommended pattern:

```text
SkyBridge Server assigns eligibility and stores task state.
Workers poll or long-poll for work.
Workers claim a task before execution.
Workers execute locally and return evidence.
SkyBridge updates task, goal and audit state.
```

Cloud systems should not directly SSH into local machines to force arbitrary shell commands. Local workers should voluntarily join the pool and request executable tasks.

This allows machines to sleep, go offline, rejoin, or refuse work safely.

## PR and merge principle

PRs are part of the evidence chain.

Default policy:

- low-risk child task PRs: auto PR plus policy-gated auto-merge;
- parent or super-goal PRs: auto PR, manual merge by default;
- high-risk PRs: human review required;
- duplicate or conflicting PRs: close, block, update branch or wait according to policy.

For multi-worker development, the first safe mode is per-project serial merge. Path-level locks, dependency graphs and parallel merge queues can be added later.

## Model routing principle

SkyBridge should not hard-code a fixed model division such as DeepSeek does X and Codex does Y.

Instead:

- high-capability model backends are useful for architecture, decomposition, failure replanning and high-risk review;
- low-cost model backends are useful for summaries, classification, queue maintenance, notification drafting and routine checks;
- local executor agents are useful for real code edits and local validation;
- SkyBridge stores policies and evidence, not model confidence.

Model routing is an adapter-level concern.

## Evidence-first completion

A task or goal should not be completed merely because a model says so.

Completion evidence may include:

- task summary;
- changed file list;
- PR URL and PR state;
- commit SHA;
- CI status;
- validation command output summary;
- risk classifier result;
- blocked/high-risk path check;
- human approval where required.

If evidence is missing, the state should be `failed`, `blocked`, `needs_human` or `needs_followup`, not `completed`.

## Bootstrap and dogfooding boundary

SkyBridge is currently being developed by using Hermes, Codex, GitHub auto-merge and ntfy. That is dogfooding.

Dogfooding dependencies are allowed during development. They must not become required product dependencies.

Hermes is a dogfooding planner adapter. Codex is a dogfooding executor adapter. ntfy is a dogfooding notification provider. GitHub is a dogfooding SCM/CI provider.

The product should remain usable with other compatible adapters.

## Anti-patterns

Avoid:

- storing the authoritative goal queue only in local Markdown folders;
- treating chat history as long-term state;
- letting a model declare completion without evidence;
- allowing cloud control to execute unrestricted local shell commands;
- turning goals into unstructured prompts;
- binding core logic to Hermes, Codex, DeepSeek, ntfy or GitHub names;
- merging high-risk changes based only on model confidence;
- starting with fully parallel multi-worker execution before serial merge policy is stable.

## Short version

SkyBridge is the control plane.

Goal is the core asset.

Task is the schedulable unit.

Run is the execution attempt.

Evidence is the completion basis.

Adapters provide planners, executors, SCM/CI providers, notification providers and runtimes.

Models are selected behind adapters.

The server is the authoritative state source.

Workers execute locally and return evidence.
