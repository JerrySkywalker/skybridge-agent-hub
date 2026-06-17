# Connectivity Doctor

The Connectivity Doctor model is `skybridge.connectivity_doctor.v1`.

Fields:

- `api_mode`
- `api_base`
- `rest_health_status`
- `sse_stream_status`
- `server_online`
- `stream_degraded`
- `last_health_time`
- `last_error_summary`
- `recommended_action`
- `token_printed=false`

REST health and SSE stream health are intentionally separate. A successful `GET /v1/health` means the server is online. SSE reconnecting or closed means the live stream is degraded, not that the whole server is offline.

Error summaries are bounded and redacted before display. The model must not persist raw requests, raw responses, tokens, auth headers, cookies, private keys or environment dumps.

