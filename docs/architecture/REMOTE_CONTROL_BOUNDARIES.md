# Remote Control Boundaries

SkyBridge is preparing a reverse WSS control plane, but the current release train keeps remote execution disabled.

## Connection Lifecycle

1. A local sidecar starts with a local `node_id`, labels and safe capabilities.
2. The sidecar sends `node.connected` and periodic `node.heartbeat` events.
3. The server records node state and marks old heartbeats stale.
4. A future WSS client may hold a reverse connection from sidecar to hub.
5. Disconnects emit `node.disconnected` or age into `stale`.

## Authentication Concept

Future WSS connections should use operator-issued sidecar tokens scoped to one node. Tokens must not be stored in Git, printed in logs, sent in notifications or embedded in dashboard bundles.

## Command Envelope

Remote commands, when implemented, must use a typed envelope:

```json
{
  "command_id": "cmd_123",
  "node_id": "local-devbox",
  "requested_by": "operator",
  "kind": "safe_operation",
  "requires_approval": true,
  "payload": {}
}
```

The MVP does not execute this envelope. It is a design constraint for future work.

## Approval Boundary

Potentially destructive or privacy-sensitive actions require an `approval.requested` event and an operator decision before execution. Denial, expiry and resolution must be auditable through normalized approval events.

## Disabled Defaults

Remote shell, file deletion, secret reads, production deployment and privileged Docker commands are disabled by default and are not implemented in this release foundation.
