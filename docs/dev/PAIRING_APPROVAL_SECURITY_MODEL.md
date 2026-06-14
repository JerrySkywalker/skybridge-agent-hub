# Pairing Approval Security Model

The durable pairing and approval preview stores reject unsafe payload fixtures before persistence.

Rejected cases include raw pairing code persistence, raw token persistence, `token_printed=true`, Authorization headers, bearer tokens, private keys, cookie payloads, environment dump payloads, shell command text in approvals, and any attempt to set `execution_enabled`, `queue_apply_enabled`, `remote_execution_enabled`, or `arbitrary_command_enabled` to true.

Audit reports are written to:

- `.agent/tmp/server-control-plane/pairing-audit-report.json`
- `.agent/tmp/server-control-plane/approval-audit-report.json`

Audit event families include pairing created, consumed, expired, revoked, approval requested, approved, rejected, expired, consumed, unsafe payload rejected, remote execution rejected, and arbitrary command rejected. Reports are safe JSON and keep `token_printed=false`.
