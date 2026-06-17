# Manual Task Provider Architecture

Manual Task Queue has three provider surfaces:

| Provider id | Status | Network owner | Notes |
| --- | --- | --- | --- |
| `mock` | default | none | Deterministic local provider for CI and safe manual smoke tests. |
| `skybridge_server_hermes` | server-mediated | SkyBridge server | Calls the Hermes cloud API through the Hermes adapter contract when server config exists. |
| `hermes_deepseek` | deprecated preview-only | none | Kept only for no-network preview compatibility. Local-direct live mode is blocked. |

## Data Flow

```text
Web/Desktop/manual helper
  -> SkyBridge server /v1/manual-tasks/run-next/skybridge-hermes
  -> Hermes adapter contract
  -> Hermes API /v1/capabilities and /v1/responses
```

The local client never stores Hermes or backend model secrets. It may show configured/disabled status, but credential values stay server-side.

## Boundaries

These remain false for every manual task provider:

- `output_executed`
- `remote_execution_enabled`
- `arbitrary_command_enabled`
- `queue_apply_enabled`
- `workunit_created`
- `task_claim_created`
- `task_pr_created`
- `raw_request_persisted`
- `raw_response_persisted`
- `token_printed`

Model output is advisory text for a human operator only.

## Deprecated Local-Direct Provider

`hermes_deepseek` remains visible to preserve the Goal 295/296 preview UI and smoke contract. It now means:

```text
deprecated_preview_no_network
```

It must not read local backend keys, perform direct live calls, persist raw request or response bodies, or become the default provider.
