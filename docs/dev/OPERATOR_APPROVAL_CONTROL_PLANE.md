# Operator Approval Control Plane

Goal 218 adds an approval model for future controlled execution without enabling execution now.

Contracts:

- `skybridge.operator_approval_request.v1`
- `skybridge.operator_approval_state.v1`
- `skybridge.operator_approval_decision.v1`
- `skybridge.operator_approval_gate.v1`

Approval requests include requested action, mode, scope, run ID, workunit IDs, limits, risk, resource gate requirement, human review requirement, finalizer requirement, failure budget requirement, evidence retention requirement, audit requirement and expiry.

Approval state can be `pending`, `approved`, `rejected`, `expired` or `consumed`. Approval does not execute anything by itself. Approval cannot contain raw shell command text, cannot bypass the local resource gate, cannot bypass task PR human review, cannot bypass the finalizer, cannot enable generic bounded queue apply and cannot enable remote arbitrary command dispatch.

Preview routes:

- `GET /api/operator-approvals`
- `POST /api/operator-approvals/request-preview`
- `POST /api/operator-approvals/:id/approve-preview`
- `POST /api/operator-approvals/:id/reject-preview`

The Web control-plane page renders pending approvals, approval state and preview-only approve/reject controls. It intentionally has no execute button, run button, apply button, command text box or raw log view.

Validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-approval-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-approval-does-not-execute.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-approval-does-not-bypass-resource-gate.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-approval-does-not-bypass-human-review.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-approval-expires.ps1
```
