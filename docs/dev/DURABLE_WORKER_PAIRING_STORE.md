# Durable Worker Pairing Store

Goal 223 adds a local/dev durable pairing preview store under ignored `.agent/tmp/server-control-plane/pairing-store/`.

The store contract is `skybridge.worker_pairing_store.v1`; records use `skybridge.worker_pairing_record.v1`. Pairing stores only `pairing_code_hash` and an optional fixture-only `pairing_code_preview_last4`. It must not persist raw pairing codes, raw tokens, Authorization headers, cookies, private keys, env dumps, prompts, transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, raw diffs, or secret-bearing paths.

Preview commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command pairing-create-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command pairing-consume-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command pairing-list -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command pairing-revoke-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control-plane-durable-state.ps1 -Command pairing-expire-fixture -Json
```

All pairing records force `execution_enabled=false`, `queue_apply_enabled=false`, `remote_execution_enabled=false`, `arbitrary_command_enabled=false`, and `token_printed=false`.
