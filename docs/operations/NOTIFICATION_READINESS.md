# Notification Readiness

Goal 317 adds `skybridge-notification-readiness.ps1` for safe notification
readiness dry-runs. It checks provider status and summarizes whether blocker
notices can be supported later without sending a real message.

## Run

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-notification-readiness.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -DryRun `
  -Json
```

The output schema is `skybridge.notification_readiness.v1`.

Required safety fields:

```text
dry_run=true
real_send_performed=false
raw_notification_payload_included=false
credential_values_exposed=false
token_printed=false
```

Dry-run readiness distinguishes real delivery providers from the local
bootstrap dry-run provider:

```text
provider_configuration_status =
  no_provider_configured |
  no_provider_configured_bootstrap_dry_run_available |
  real_provider_unavailable |
  real_provider_unavailable_bootstrap_dry_run_available |
  real_provider_ready
real_provider_count = number
real_ready_provider_count = number
dry_run_safe_provider_count = number
bootstrap_dry_run_available = true | false
blocker_notice_supported = true | false
```

When no real provider is configured, `notify-bootstrap.ps1` can still appear as
`bootstrap-notifier` with `readiness_kind=bootstrap_dry_run`,
`dry_run_safe=true`, `real_send_capable=false` and
`blocker_notice_supported=true`. This proves that a blocker notice can be
rendered through the reviewed dry-run path. It does not prove live delivery.

## Policy

Goal 317 never sends a real notification. The dry-run exists so later
self-bootstrap automation can report blockers through a reviewed notification
path without exposing provider credentials, webhook URLs, raw payloads, logs,
prompts or Hermes responses.

## Smoke

```powershell
corepack pnpm smoke:notification-readiness
```

The smoke is fixture-only and proves partial readiness with no real send and no
credential or raw notification payload exposure. It also covers the
no-provider/bootstrap-dry-run case.

## Operator Report Delivery

Mega Goal 323 adds `skybridge-operator-notification-readiness.ps1` for the
operator report path. It wraps the existing readiness probe and adds explicit
report/review-gate delivery fields:

```text
schema=skybridge.operator_notification_readiness.v1
report_delivery_supported=true | false
review_gate_supported=true | false
bootstrap_dry_run_available=true | false
real_provider_configured=true | false
real_send_performed=false by default
raw_notification_payload_included=false
credential_values_exposed=false
token_printed=false
```

Default mode is dry-run. A real send test is optional and must fail closed when
no safe configured provider exists. Even when a real provider is available, the
test payload is a minimal sanitized summary and must not include raw prompts,
raw logs, credentials, webhook secrets, provider tokens or auth headers.

Safe notification content is limited to status, task ids, PR numbers, commit
ids, counts, stop reasons, hold reasons, sanitized evidence summaries and the
recommended next action.
