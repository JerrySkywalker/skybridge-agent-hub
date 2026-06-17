# Manual Task Live LLM Safety

Hermes DeepSeek live inference is an operator opt-in preview, not a worker execution feature.

Safety boundaries:

- default provider remains `mock`
- Hermes live calls are disabled by default
- CI blocks live calls
- preview mode performs no network request
- model output is never executed
- Codex worker execution stays disabled
- workunit, task claim and task PR creation stay disabled
- queue apply, start-all, start-queue and resume stay disabled
- raw request and raw response persistence stay disabled by default
- reports store `result_preview`, `result_hash`, `duration_ms` and `error_summary` only
- `token_printed=false`

The prompt wrapper states that the request is a Manual Task Queue test, forbids command execution, asks the model not to fabricate realtime data and instructs weather answers to say realtime weather cannot be verified when no live weather tool exists.

Live opt-in failures must return a safe blocked or failed summary instead of logs, response bodies, headers or credentials.
