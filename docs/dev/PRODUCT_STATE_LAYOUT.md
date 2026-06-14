# Product State Layout

SkyBridge Agent Hub uses a stable local state layout for daily productized operation. Runtime reports are metadata-only and stay under ignored `.agent/tmp` directories.

## Contract

`skybridge.product_state_layout.v1`

Required directories:

| Path | Purpose | Git status |
| --- | --- | --- |
| `.agent/tmp/` | Root for generated local reports | ignored |
| `.agent/tmp/diagnostics/` | Safe health and dependency summaries | ignored |
| `.agent/tmp/product-readiness/` | Product readiness summaries | ignored |
| `.agent/tmp/launch-profiles/` | Safe launch profile reports | ignored |
| `.agent/tmp/packaging-preview/` | Desktop packaging metadata previews | ignored |
| `.agent/tmp/windows-launcher-preview/` | Windows launcher and autostart preview reports | ignored |
| `.agent/tmp/upgrade-preview/` | Upgrade and backup preview metadata | ignored |

Rules:

- Generated runtime reports use relative paths when possible.
- Absolute paths are not required in product reports and must be sanitized when displayed.
- Reports must not contain secrets, raw prompts, transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, Authorization headers, cookies, private keys, tokens, raw pairing codes, raw approval secrets, environment dumps or secret-bearing local paths.
- `token_printed=false` must appear in generated JSON and Markdown summaries.

## Schemas

`skybridge.product_state_layout.v1`

- `directories`: relative report directories.
- `ignored_runtime_reports`: `true`.
- `secrets_allowed`: `false`.
- `absolute_paths_sanitized`: `true`.
- `token_printed`: `false`.

`skybridge.product_profile.v1`

- `profile`: one of the documented local profiles.
- `mode`: `preview_only`.
- `execution_enabled`: `false`.
- `queue_apply_enabled`: `false`.
- `remote_execution_enabled`: `false`.
- `arbitrary_command_enabled`: `false`.
- `trusted_docs_auto_merge_enabled`: `false`.
- `token_printed`: `false`.

`skybridge.local_runtime_paths.v1`

- `diagnostics_dir`: `.agent/tmp/diagnostics`
- `product_readiness_dir`: `.agent/tmp/product-readiness`
- `launch_profiles_dir`: `.agent/tmp/launch-profiles`
- `packaging_preview_dir`: `.agent/tmp/packaging-preview`
- `windows_launcher_preview_dir`: `.agent/tmp/windows-launcher-preview`
- `upgrade_preview_dir`: `.agent/tmp/upgrade-preview`

`skybridge.local_state_health.v1`

- `name`: local subsystem name.
- `ok`: boolean health result.
- `summary`: bounded safe text.
- `warnings`: bounded safe strings.
- `token_printed`: `false`.

token_printed=false
