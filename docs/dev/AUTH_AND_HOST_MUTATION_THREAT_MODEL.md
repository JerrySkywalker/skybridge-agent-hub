# Auth And Host Mutation Threat Model

Status: preview-only.

The local auth layer and host mutation layer are intentionally separate. A fixture-authenticated request can read safe metadata only. It cannot grant installation, startup, registry, service, scheduled task, PATH, power, or Program Files permissions.

## Auth Guarantees

- Fixture auth only.
- Session store persists session id, timestamps, state, scope, local origin summary, and token hash only.
- No cookies are persisted.
- No authorization header values are persisted.
- No private keys are persisted.
- No raw auth value is persisted.
- Authenticated reads do not bypass release, resource, failure, evidence, audit, or human-review gates.

## Host Mutation Guarantees

- Host mutation consent states are `disabled`, `preview_requested`, `blocked_by_default`, and `future_explicit_goal_required`.
- All actual host mutation permissions remain false by default.
- Auth cannot enable host mutation.
- Installer preview remains blocked for real mutation.
- Real host mutation requires a future explicit goal.

## Abuse Cases

| Abuse case | Expected result |
| --- | --- |
| Authenticated request asks to execute or apply work | Rejected by auth gate |
| Authenticated request asks to mutate registry/startup/service/scheduled task/PATH/power settings | Blocked by host consent and installer interlock |
| Local UI adds install or worker controls | Rejected by UI smoke policy |
| Installer preview tries real install | Blocked by installer safety interlock |
| Future auth route tries to skip audit/human-review gates | Blocked by release and resource gate policy |

## Required Evidence

- `skybridge-local-auth.ps1 -Command report`
- `skybridge-host-consent-preview.ps1 -Command report`
- `skybridge-installer-safety-interlock.ps1 -Command report`
- `smoke-redteam-host-mutation-blocked.ps1`
- `smoke-auth-does-not-enable-execution.ps1`
