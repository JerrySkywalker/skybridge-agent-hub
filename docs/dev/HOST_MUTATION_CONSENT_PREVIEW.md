# Host Mutation Consent Preview

The host mutation consent model is preview-only. It documents future consent states without granting host permissions.

Consent states:

- `disabled`
- `preview_requested`
- `blocked_by_default`
- `future_explicit_goal_required`

All permissions remain false:

- registry write
- startup write
- scheduled task creation
- service installation
- PATH mutation
- powercfg mutation
- Program Files installation
- Desktop shortcut creation
- Start Menu shortcut creation

Local auth cannot enable host mutation. Installer safety interlock remains the final blocker for real host changes.
