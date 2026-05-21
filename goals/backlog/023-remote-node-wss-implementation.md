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
- Add local integration tests for auth failure, reconnect and malformed envelopes.
- Add docs that explain the disabled-by-default execution boundary.

## Completion Criteria

- Sidecar can connect, heartbeat and disconnect over WSS in local tests.
- Invalid auth and malformed command envelopes are rejected.
- No shell command execution is available by default.
- Docs and smoke scripts cover the local WSS path.
- Approval and audit records are generated for any simulated operator command.
- The feature can be disabled completely with configuration.

## Safety Boundaries

- No production deployment.
- No real secrets committed or printed.
- No destructive remote commands.
- No privileged public PR runners.
- Do not add unaudited shell execution.
- Do not weaken approval, authentication or redaction behavior to make tests pass.

## Validation Commands

```powershell
corepack pnpm --filter @skybridge-agent-hub/server test
corepack pnpm --filter @skybridge-agent-hub/sidecar test
corepack pnpm --filter @skybridge-agent-hub/sidecar typecheck
corepack pnpm smoke:multi-agent-platform
```

Add a dedicated WSS smoke command before marking this goal complete.

## CI/CD Impact

This should add local fixture-backed WSS tests and possibly a non-privileged smoke job. Public CI must use fake node tokens and GitHub-hosted runners only; real remote node connectivity belongs in a manually approved private environment.
