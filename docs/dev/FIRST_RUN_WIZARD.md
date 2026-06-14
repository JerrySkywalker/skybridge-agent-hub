# First-run Wizard

The first-run wizard is read-only and preview-only.

Steps:

1. Bootstrap complete status.
2. Product readiness status.
3. Runtime profile selection.
4. Diagnostics health.
5. Pairing/approval state.
6. Resident polling preview.
7. Packaging preview.
8. Backup/restore preview.
9. Disabled capabilities.
10. Next safe action.

Schemas:

- `skybridge.first_run_wizard.v1`
- `skybridge.first_run_step.v1`
- `skybridge.onboarding_status.v1`
- `skybridge.next_safe_action.v1`

The wizard must not expose enabled execute, apply, start or claim controls.

token_printed=false
