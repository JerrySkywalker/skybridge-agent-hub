# Proposal Review Queue

Status: implemented locally for Super 181; real cloud pilot evidence is recorded in `docs/dev/PROGRESS.md`.

SkyBridge proposal review separates planning from execution. Hermes and rule-based planners create proposals only. Operators review, approve, reject, defer or supersede those proposals before any queued task can be created.

## Lifecycle

Proposal statuses:

- `proposed`: created by a planner and waiting for review.
- `reviewed`: inspected but not approved for conversion.
- `approved`: allowed to convert to an executable task.
- `rejected`: refused and not convertible.
- `deferred`: postponed and not convertible until approved later.
- `superseded`: replaced by another proposal.
- `blocked_dependency`: waiting on another proposal or task.
- `converted`: converted to a queued task.
- `executed`: task completed or recovered with evidence.

Policy decisions are separate from review status. A planner may classify a proposal as `accepted_for_preview`, `accepted_for_execution`, `ask_human`, `rejected_high_risk`, `rejected_expected_files`, `rejected_duplicate` or `dependency_blocked`. Conversion still requires review status `approved`.

## Approval Rules

Only approved proposals may convert to tasks. Rejected, deferred, superseded and dependency-blocked proposals cannot convert.

Low-risk docs proposals are approvable when every expected file is under `docs/` and normalized execution capabilities include `codex`, `git` and `gh`.

Local-smoke proposals remain review-gated. They are approvable only when every expected file is a safe `scripts/powershell/smoke-*.ps1` path and normalized capabilities include `codex`, `powershell` and `windows`.

High-risk, production, deploy, secret, GitHub settings, branch protection, server config and server-root config proposals are blocked from automatic approval and conversion.

Dependencies must be converted or executed before a dependent proposal can be approved or converted.

## CLI

List and inspect proposals:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command list `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command show `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id
```

Review mutations require `-Apply`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command approve `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -Reason "low-risk docs proposal reviewed" `
  -Apply
```

Reject, defer and supersede also require explicit reason or superseding proposal:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command reject `
  -ProposalId proposal-id `
  -Reason "unsafe surface" `
  -Apply
```

Convert only after approval:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command convert `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -Apply
```

Conversion creates a queued task only. It does not run a worker.

## Status UX

`skybridge-status.ps1` now uses a grouped header and grouped task summary. Task summary fields are:

- `total`: all tasks returned for the project.
- `matching`: tasks matching the current filters.
- `shown`: tasks displayed after `TaskLimit` or `RecentTasks`.
- `truncated`: true only when `matching > shown`.

Proposal visibility is opt-in:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ShowProposals `
  -ProposalLimit 10
```

Useful filters:

- `-ShowProposals -ApprovedOnly`
- `-ShowProposals -PendingReviewOnly`
- `-ShowProposals -ProposalStatus approved,converted`
- `-ShowProposals -ReviewStatus proposed`

The `-ActiveOnly` zero-task case reports `matching=0`, `shown=0` and `Tasks: none`.
