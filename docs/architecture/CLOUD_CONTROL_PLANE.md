# Cloud Control Plane

SkyBridge Agent Hub is moving from local-first dogfooding toward a cloud-control-plane architecture. The long-term shape is one authoritative SkyBridge Server with many local workers connected directly over the SkyBridge API.

## Authority Model

SkyBridge Server is the authoritative source for:

- projects;
- goals;
- task queue state;
- worker registry and heartbeats;
- PR/CI policy records;
- notification routing metadata;
- audit-safe event history.

Local workers should treat their filesystem, repository checkout and runtime logs as an execution cache. They may keep local logs under `.agent/`, but they should reconcile with the server before claiming or continuing work.

## Goal Registry

Goals are first-class server-side assets. The Goal Registry owns durable objective metadata such as lifecycle, priority, risk, acceptance criteria, evidence requirements, dedupe keys, supersession links and planner metadata.

Tasks are execution slices that link back to goals. Completing a task can add evidence and update progress, but goal completion remains evidence-driven and server-side.

## Local Worker Profile

A local worker profile describes a machine's safe execution envelope:

- worker identity and display name;
- project IDs it can serve;
- repository paths it can work in;
- capabilities and executor adapters;
- preferred and blocked task types;
- max parallel tasks;
- auto-merge and production-deploy gates;
- SkyBridge API base and future worker-token mode;
- Codex command and sandbox settings.

Profiles are local configuration. Real profiles live outside the repository, for example under `$HOME\.skybridge\worker.<hostname>.json`. Repository examples must use placeholders and must not contain real credentials.

## Direct API Connectivity

Local workers should connect directly to SkyBridge Server:

```text
worker machine -> HTTPS SkyBridge API -> authoritative state store
```

Local development may use:

```text
http://127.0.0.1:8787
```

Cloud control plane deployments should use HTTPS and a worker token. The token boundary is intentionally separate from Hermes, Codex, GitHub or ntfy credentials.

## Adapter Roles

Hermes is an optional `PlannerAdapter`. It may propose or update goals and tasks through SkyBridge APIs, but it is not a public control-plane dependency and should not be exposed directly.

Codex is a local `ExecutorAdapter`. It runs in the worker environment and reports safe summaries, PR links and evidence metadata through SkyBridge.

GitHub is an `SCM/CI Provider`. It supplies PR and check state and remains behind policy gates for auto-merge.

ntfy is a `NotificationProvider`. It receives concise operator notifications, not raw prompts, raw logs, secrets or full command output.

## SSH Tunnel Scope

SSH tunnels are a development convenience for private Hermes or local cloud supervision experiments. They are not the long-term worker transport. The durable path is direct worker-to-SkyBridge API connectivity with explicit worker identity, scoped token auth, server-side state and audit-safe records.

## Safety Boundaries

- No production deployment is implied by the cloud-control-plane model.
- Real worker tokens stay local-only.
- Hermes remains private unless a future explicit production design changes that boundary.
- Auto-merge remains governed by the existing lifecycle and merge policy.
- Local runtime artifacts under `.agent/` are not part of the authoritative state store.
