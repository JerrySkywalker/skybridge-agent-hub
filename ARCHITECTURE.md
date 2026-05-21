# Architecture

SkyBridge Agent Hub is a modular monorepo for local/cloud agent telemetry, notifications and future remote control.

## Logical layers

```text
Agent Sources
  Codex hooks / Codex exec JSON / Codex app-server
  OpenCode plugin events
  Hermes Agent API/events
  Custom agents
        │
        ▼
Adapter Layer
  Normalize source-specific events
        │
        ▼
SkyBridge Server
  Event ingestion
  Run/session aggregation
  SSE/WebSocket stream
  Notification job creation
        │
        ├── Dashboard widgets
        ├── Message Center
        └── Future Remote App API
```

## Packages

```text
apps/server              API server and event stream
apps/web                 standalone dashboard shell
apps/sidecar             future local node agent
packages/event-schema    skybridge.agent_event.v1
packages/client          API/SSE client
packages/react-widgets   embeddable React widgets
packages/web-components  framework-neutral custom elements
packages/agent-adapters  Codex/OpenCode/Hermes adapters
packages/notification-providers ntfy/Apprise/FCM/etc. adapters
```

## Design decisions

- The notification system is not the real-time progress stream.
- Real-time progress uses SSE/WebSocket from the SkyBridge server.
- ntfy is the first notification outlet, not a permanent lock-in.
- Codex hooks are treated as telemetry inputs, not as the final remote-control protocol.
- Future remote control should go through local sidecar + reverse connection + explicit approval policy.
- MVP persistence uses a local SQLite store at `.data/skybridge.sqlite`, with one-time import from the previous `.data/skybridge-store.json` JSON store when present.

## Event schema

All adapters emit `skybridge.agent_event.v1` before data reaches the server. The first supported event families are:

```text
session.* run.* turn.* plan.* todo.* tool.* file.* diff.*
approval.* message.* agent.* notification.*
```

Each event includes source metadata, optional correlation IDs, severity and a redacted payload. Codex hook payloads intentionally summarize tool input and omit full command, stdout and stderr by default.

## API surface

```text
GET  /health
POST /v1/events
GET  /v1/events
GET  /v1/runs
GET  /v1/stream
GET  /v1/notifications
POST /v1/notifications/send
```

`run.failed`, `approval.requested` and `notification.requested` are notification trigger events. If ntfy is not configured, notification attempts are recorded as skipped placeholders.
