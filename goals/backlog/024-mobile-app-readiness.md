# Backlog: Mobile App Readiness

## Background

PR #9 prepares server-side metrics, approvals, notifications and node status, but does not define a mobile operator app contract.

## Tasks

- Define mobile API requirements for status, approvals, notifications and node summaries.
- Add auth/session assumptions for a mobile operator.
- Define push notification behavior and provider fallback policy.
- Design approval interaction screens and denial/expiry behavior.
- Add mobile fixture payloads for summary, approval and notification screens.
- Identify which existing endpoints are stable enough for mobile consumption and which remain release-candidate only.

## Completion Criteria

- Mobile API contract is documented.
- A fixture-driven mobile flow smoke exists.
- Approval actions remain local-first and auditable.
- Push notification examples use fake provider configuration only.
- The mobile contract distinguishes read-only status from approval mutation.

## Safety Boundaries

- Do not add production push credentials.
- Do not enable remote execution from mobile.
- Do not weaken approval or auth boundaries.
- Do not store mobile session tokens in fixtures, docs examples or CI logs.

## Validation Commands

```powershell
corepack pnpm --filter @skybridge-agent-hub/client typecheck
corepack pnpm --filter @skybridge-agent-hub/server test
corepack pnpm smoke:multi-agent-platform
corepack pnpm smoke:release-candidate
```

## CI/CD Impact

Expected CI impact is contract tests or fixture validation only. Native mobile builds and real push-provider tests are deferred until a separate mobile implementation goal authorizes the platform and credentials model.
