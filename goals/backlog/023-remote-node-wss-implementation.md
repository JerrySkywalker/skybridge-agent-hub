# Backlog: Remote Node WSS Implementation

## Background

PR #9 adds node identity, heartbeat, node registry and remote-control boundary docs. It intentionally does not implement real WSS or command execution.

## Tasks

- Implement reverse WSS connection from sidecar to hub.
- Add scoped node token authentication with no token values in logs.
- Add heartbeat and reconnect lifecycle handling.
- Define and validate a typed command envelope.
- Route any operator action through approval events and audit records.
- Keep destructive execution disabled unless a future goal explicitly authorizes it.

## Completion Criteria

- Sidecar can connect, heartbeat and disconnect over WSS in local tests.
- Invalid auth and malformed command envelopes are rejected.
- No shell command execution is available by default.
- Docs and smoke scripts cover the local WSS path.

## Safety Boundaries

- No production deployment.
- No real secrets committed or printed.
- No destructive remote commands.
- No privileged public PR runners.
