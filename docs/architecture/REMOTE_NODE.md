# Remote Node Design Draft

## Purpose

A local sidecar should actively connect to the cloud Agent Hub so that a future mobile app can control local agents without exposing the local machine directly.

## Direction

```text
Mobile App
  ↓
Cloud Agent Hub
  ↓ reverse WSS
Local Sidecar
  ↓
Codex / OpenCode / Scripts
```

## MVP

- Node registration.
- Heartbeat.
- Event upload.
- No remote command execution yet.

## Local Node Identity

The sidecar exposes a local identity model through `/health` and `/v1/local/status`:

- `node_id`: stable local identifier, defaulting to a sanitized host-derived value;
- `host`: operator-visible hostname label;
- `labels`: local grouping labels such as `local` and `sidecar`;
- `capabilities`: safe capabilities such as `event-forwarding`, `heartbeat` and `spool`;
- `last_seen`: current sidecar timestamp;
- `sidecar_version`: package/runtime version.

The server accepts normalized `node.connected`, `node.heartbeat` and `node.disconnected` events and exposes `/v1/nodes` as a non-destructive registry summary. Stale state is derived from heartbeat age; no command channel is opened by this registry.

## Local Spool

The current sidecar keeps an in-process spool counter when event forwarding fails. A future durable spool may use local JSONL or SQLite, but it must contain normalized redacted events only and must not store raw prompts, command output, patches or secrets.

## Safe Cloud Forwarding

Example local-only configuration:

```text
SKYBRIDGE_CLOUD_URL=http://127.0.0.1:8787
SKYBRIDGE_NODE_ID=local-devbox
SKYBRIDGE_NODE_LABELS=local,dev
SKYBRIDGE_NODE_CAPABILITIES=event-forwarding,heartbeat,spool
```

Do not put cloud tokens or production secrets in repository files. Future cloud forwarding should use a short-lived sidecar token from an operator-managed secret store.

## Later

- Run dispatch.
- Approval response.
- Command cancellation.
- File artifact sync.
- Strict audit log.
