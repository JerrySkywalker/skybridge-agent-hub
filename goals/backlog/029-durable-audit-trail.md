# Goal 029: Durable Audit Trail

## Background

Super Goal 005-014 added `GET /v1/audit` as a safe derived audit summary over already-redacted events. That is enough for local release-candidate review, but it is not yet a durable append-only audit subsystem.

## Tasks

- Define an append-only audit record schema with actor, source adapter, correlation IDs, safety decision, redaction policy version and immutable event reference.
- Persist audit records in SQLite without storing raw prompts, patches, stdout, stderr, private paths or secrets.
- Emit audit records for approval resolution, future remote-control commands, notification routing decisions and node connection state changes.
- Add retention/export documentation that keeps local operator privacy explicit.
- Add focused server and migration tests.

## Completion Criteria

- Audit records survive server restart and can be queried by time, action, actor and run ID.
- Existing `/v1/audit` remains backward-compatible or has a documented migration path.
- Tests prove raw payload fields are not persisted or returned.
- Documentation explains which actions are audited and which data is intentionally omitted.

## Safety Boundaries

- Do not enable real remote command execution.
- Do not store raw prompts, patches, stdout, stderr, command output, private paths, secrets, cookies, tokens or keys.
- Do not upload audit records to external services by default.
- Do not modify production databases or deployment secrets.
