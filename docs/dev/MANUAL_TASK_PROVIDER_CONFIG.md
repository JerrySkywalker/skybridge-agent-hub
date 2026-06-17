# Manual Task Provider Config

Manual Task Queue live inference is server-mediated. The active live-capable provider is:

```text
provider_id=skybridge_server_hermes
```

Configure it only on the SkyBridge server:

```text
HERMES_API_BASE=
HERMES_API_KEY=
HERMES_API_KEY_FILE=
HERMES_TIMEOUT_MS=60000
HERMES_MAX_RESPONSE_CHARS=2000
```

Tracked examples must keep placeholders empty. Client apps and local queue helpers do not require backend keys.

`provider_id=hermes_deepseek` is now deprecated preview-only compatibility. Local-direct live mode is blocked and does not read local backend secrets.

The provider report only exposes booleans such as `api_base_configured`, `api_key_present`, `client_secret_required=false` and `credential_values_exposed=false`.
