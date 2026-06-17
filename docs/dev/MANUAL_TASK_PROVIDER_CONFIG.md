# Manual Task Provider Config

Real Hermes DeepSeek config is local-only and ignored by git:

```text
.agent/local/hermes-deepseek.local.json
```

Start from the placeholder file:

```text
config/hermes-deepseek.local.example.json
```

The local config fields are:

- `provider_id=hermes_deepseek`
- `endpoint`
- `model`
- `timeout_seconds`, default `60`
- `max_response_chars`, default `2000`
- `live_enabled=false` by default
- `raw_request_persisted=false`
- `raw_response_persisted=false`
- `token_printed=false`

Credential values must stay out of tracked files and reports. The provider script reads the credential from local environment variable `HERMES_DEEPSEEK_API_KEY` when live opt-in is explicitly requested.

Live calls are blocked unless all are true:

- the command is `run-next-hermes-live-optin`
- the operator passes `-AllowLive`
- local config has `live_enabled=true`
- endpoint and credential are configured locally
- CI environment markers are absent

The provider report only exposes booleans such as `endpoint_configured`, `config_present` and `credential_values_exposed=false`.
