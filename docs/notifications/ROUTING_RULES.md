# Notification Routing Rules

SkyBridge routing rules are intentionally small in this release train. The server exposes the active rules at `GET /v1/notifications/rules`.

## Default Rule

The default rule creates a notification job for:

- `run.failed`
- `approval.requested`
- `notification.requested`

It uses a warning-or-higher threshold, selects ntfy first, and stores a dedupe key derived from event type, run/session correlation and provider.

## Quiet Hours

Quiet hours are a placeholder in the current API. They are documented in the rule shape but do not suppress local notification jobs yet.

## Privacy

Notification bodies are generated from safe source, run and severity metadata. They must not include raw prompts, patches, stdout, stderr, command output, private paths or secrets.
