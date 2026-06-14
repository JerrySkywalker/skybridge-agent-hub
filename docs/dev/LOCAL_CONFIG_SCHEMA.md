# Local Config Schema

The local config preview uses `skybridge.local_config.v1` with a `skybridge.local_config_profile.v1` profile.

Required safe fields:
- `profile_name`
- `mode=local_preview`
- `web_enabled`
- `desktop_enabled`
- `server_preview_enabled`
- `resident_polling_preview_enabled`
- `diagnostics_enabled`
- `execution_enabled=false`
- `queue_apply_enabled=false`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `trusted_docs_auto_merge_enabled=false`
- `token_printed=false`

The example config lives at `fixtures/productization/local-config.example.json` and must not contain secrets, tokens, Authorization headers, cookies, private keys, or raw secret-bearing local paths.
