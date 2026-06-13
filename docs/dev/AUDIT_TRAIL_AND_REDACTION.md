# Audit Trail And Redaction

Goal 219 adds safe audit events and a redaction scan gate for the release path. Audit events are metadata records. They must not include raw prompts, raw transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, raw diffs, authorization headers, cookies, private keys, tokens, environment dumps, or secret-bearing local paths.

## Contracts

- `skybridge.audit_event.v1`
- `skybridge.audit_trail.v1`
- `skybridge.audit_report.v1`
- `skybridge.redaction_scan_result.v1`
- `skybridge.redaction_violation.v1`
- `skybridge.safe_export_gate.v1`

## Event Lifecycle

The audit trail can record safe milestones:

- resource gate passed or blocked;
- approval requested, approved preview, rejected preview, or expired preview;
- human review required;
- task PR created or merged;
- finalizer completed;
- retry refused;
- server heartbeat ingested;
- server payload rejected;
- evidence indexed;
- redaction scan passed or failed.

These events do not execute work. They support later release review and controlled execution design.

## Redaction Checks

The scanner rejects token-print indicators, authorization headers, bearer-token shapes, GitHub tokens, OpenAI keys, private key markers, cookies, raw output fields, raw prompt/transcript fields, environment dump patterns, and identifiable secret-bearing paths. It allows safe hashes, safe PR URLs, safe relative paths, and false-valued persistence fields.

## Validation

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-audit-event-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-redaction-rejects-token.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-redaction-allows-safe-hashes.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-safe-export-gate.ps1
```

