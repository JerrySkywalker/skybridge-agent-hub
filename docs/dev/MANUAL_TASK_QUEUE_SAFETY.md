# Manual Task Queue Safety

The manual task queue is not the SkyBridge worker queue.

It must not create or mutate:

- workunits
- server tasks
- task claims
- task PRs
- worker leases
- queue apply state
- host settings
- remote execution state

## Persisted Data

Allowed local fields:

- `input_preview`
- `input_hash`
- `result_preview`
- task id
- lifecycle state
- provider id
- timestamps
- safe booleans

Forbidden persisted data:

- raw prompt bodies
- raw transcripts
- raw provider requests
- raw provider responses
- auth headers
- cookies
- private keys
- env dumps
- raw command output
- tokens

## Provider Boundary

`provider_id=mock` is deterministic and local-only. It returns a safe `result_preview` and sets:

- `network_enabled=false`
- `hermes_live_call_enabled=false`
- `raw_request_persisted=false`
- `raw_response_persisted=false`
- `output_executed=false`
- `token_printed=false`

Command-like text may be entered for red-team testing, but it is classified as `command_text_detected_no_execution` and is never executed.
