# Backlog: Mobile App Readiness

## Background

PR #9 prepares server-side metrics, approvals, notifications and node status, but does not define a mobile operator app contract.

## Tasks

- Define mobile API requirements for status, approvals, notifications and node summaries.
- Add auth/session assumptions for a mobile operator.
- Define push notification behavior and provider fallback policy.
- Design approval interaction screens and denial/expiry behavior.

## Completion Criteria

- Mobile API contract is documented.
- A fixture-driven mobile flow smoke exists.
- Approval actions remain local-first and auditable.

## Safety Boundaries

- Do not add production push credentials.
- Do not enable remote execution from mobile.
- Do not weaken approval or auth boundaries.
