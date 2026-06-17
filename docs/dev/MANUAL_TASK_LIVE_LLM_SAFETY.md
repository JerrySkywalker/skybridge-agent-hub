# Manual Task Live LLM Safety

Manual Task Queue live inference is server-mediated through `provider_id=skybridge_server_hermes`, not a worker execution feature.

Safety boundaries:

- default provider remains `mock`
- clients call SkyBridge server, not a backend model provider
- SkyBridge server calls Hermes only through `/v1/capabilities` and `/v1/responses`
- local-direct `hermes_deepseek` mode is deprecated preview-only and performs no network request
- model output is never executed
- Codex worker execution stays disabled
- workunit, task claim and task PR creation stay disabled
- queue apply, start-all, start-queue and resume stay disabled
- raw request and raw response persistence stay disabled by default
- reports store `result_preview`, `result_hash`, `duration_ms` and `error_summary` only
- `token_printed=false`

The prompt wrapper states that the request is a Manual Task Queue test, forbids command execution, asks the model not to fabricate realtime data and requires safe advisory text for a human operator.

Server-mediated failures must return a safe blocked or failed summary instead of logs, response bodies, headers or credentials.
