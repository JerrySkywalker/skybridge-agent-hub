# Approval Model

SkyBridge approval events model operator interaction without enabling remote execution.

## Events

- `approval.requested`: an agent or sidecar asks for a decision.
- `approval.resolved`: an operator accepts a request.
- `approval.denied`: an operator denies a request.
- `approval.expired`: a request times out.

## API

- `GET /v1/approvals`: list pending approvals.
- `GET /v1/approvals/:approvalId`: inspect one approval.
- `POST /v1/approvals/:approvalId/resolve`: record `accepted` or `denied`.

Resolution writes a normalized approval event from `skybridge/approval-api`. It does not dispatch a remote command.

## Safety

Approval payloads should include concise request metadata only. Raw prompts, patches, command output, file contents, private paths and secrets remain out of approval events.
