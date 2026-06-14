# Persistent Operator Approval State

Goal 223 adds durable local/dev preview approval state under `.agent/tmp/server-control-plane/operator-approval-store.json`.

The store contract is `skybridge.operator_approval_store.v1`; records use `skybridge.operator_approval_record.v1`. Approval state is auditable and may be consumed in preview, but consumption does not execute anything and sets `can_execute_now=false`.

Preview commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command approval-create-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command approval-approve-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command approval-reject-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command approval-expire-fixture -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command approval-consume-preview -Json
```

Approval records require resource gate, human review, finalizer, failure budget, evidence retention, audit, and redaction. They cannot contain shell command text and cannot enable queue apply, remote execution, or arbitrary command dispatch.
