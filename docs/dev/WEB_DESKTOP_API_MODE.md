# Web/Desktop API Mode

Web and Desktop share the same explicit API mode model:

- `cloud_operator`
- `local_dev`
- `custom`

Environment overrides remain supported:

- `VITE_SKYBRIDGE_API_BASE`
- `VITE_SKYBRIDGE_API_MODE`

When an override is present, Settings displays the selected mode/base but disables frontend editing. Without overrides, settings are stored only in frontend local storage:

- `skybridge.api.mode`
- `skybridge.api.base`

Reset returns to cloud operator mode and the default cloud API base. Local development must be selected explicitly or supplied through `VITE_SKYBRIDGE_API_MODE=local_dev`.

The Settings UI exposes mode and API base controls plus reset. Manual Task provider status, including server-mediated Hermes, uses the selected API base.

No enabled execute, apply, start, claim, worker-run, queue-apply, host-mutation or arbitrary command controls are added by this mode selection work.
