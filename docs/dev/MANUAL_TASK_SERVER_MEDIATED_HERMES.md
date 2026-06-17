# Manual Task Server-Mediated Hermes Provider

Goal 297/298 moves Manual Task Queue live inference behind the SkyBridge server.

The client-facing provider id is:

```text
skybridge_server_hermes
```

Default behavior remains:

```text
default_provider_id=mock
```

## Contract

Manual Task Queue clients call SkyBridge:

```text
GET  /v1/manual-tasks/providers
POST /v1/manual-tasks/run-next/mock
POST /v1/manual-tasks/run-next/hermes-preview
POST /v1/manual-tasks/run-next/skybridge-hermes
```

Only the SkyBridge server may call Hermes. The server-side Hermes adapter uses:

```text
GET  /v1/capabilities
POST /v1/responses
```

SkyBridge does not call DeepSeek directly. DeepSeek, if used at all, is a backend behind Hermes and is outside the SkyBridge client contract.

## Server Config

Server-side config uses environment variables or a server-side token file:

```text
HERMES_API_BASE=
HERMES_API_KEY=
HERMES_API_KEY_FILE=
HERMES_TIMEOUT_MS=60000
HERMES_MAX_RESPONSE_CHARS=2000
```

Client apps do not need, store, or report Hermes credentials.

## Result Safety

Manual task results expose safe metadata only:

- `provider_id`
- `provider_status`
- `server_mediated_llm_inference_enabled`
- `cloud_hermes_provider_enabled`
- `live_call_performed`
- `result_preview`
- `result_hash`
- `duration_ms`
- `error_summary`
- `output_executed=false`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `queue_apply_enabled=false`
- `token_printed=false`

Raw requests and raw responses are not persisted.

## Reports

Safe local reports are written under ignored `.agent/tmp/manual-task/`:

- `server-hermes-provider-report.json`
- `server-hermes-provider-report.md`
- `server-hermes-preview-report.json`
- `server-hermes-live-optin-report.json` only when a server-mediated live call is attempted

Reports use booleans, provider status, hashes and summaries. They must not contain raw tokens, raw request bodies or raw response bodies.
