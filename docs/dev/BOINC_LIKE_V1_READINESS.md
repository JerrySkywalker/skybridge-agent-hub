# BOINC-like v1 Readiness

BOINC-like v1 is not authorized for execution. This report records the preview contract and the gaps that must be closed before any real apply path exists.

## Completed Managed Mode Runs

- `managed-mode-pilot-208`
- `managed-mode-run-209`
- `managed-mode-run-210`
- `managed-mode-run-211`

These runs establish the completed Managed Mode v0.9 readiness baseline. The general bounded queue apply path remains disabled, multi-workunit apply remains disabled, and `no_next_execution_authorized=true`.

## Readiness Model

- Resource gate state: integrated and required before any future authorized run.
- Worker readiness summary: worker can be represented, but BOINC-like v1 claim and execution are disabled.
- Scheduler preview: exactly two docs/local-smoke workunit candidates are modeled.
- Two-workunit preview: workunit B waits for workunit A to complete and finalize.
- Drain/pause policy: modeled as preview-only controls.
- Apply disabled: `apply_enabled=false`, `run_apply_enabled=false`, and `multi_workunit_apply_enabled=false`.
- `token_printed=false`.

## Readiness Gaps Before v1 Apply

- reliable two-workunit finalizer
- desktop resident enforcement
- failure budget policy
- queue drain implementation
- operator approval flow
- release/audit docs
- long-run evidence retention model
- explicit v1 authorization goal

## Current Decision

BOINC-like v1 readiness is in preview status only. The only safe next action is reviewing the two-workunit preview and drain policy while keeping execution and apply paths disabled.
