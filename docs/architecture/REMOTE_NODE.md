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

## Later

- Run dispatch.
- Approval response.
- Command cancellation.
- File artifact sync.
- Strict audit log.
