# Server Control Plane And Pairing

Goal 218 adds a preview-only server control-plane model for BOINC-like workers.

The worker registration contract is `skybridge.worker_registration.v1`. It records safe identity and capability metadata: `worker_id`, `device_id_hash`, display name, repo, branch, commit, capabilities, resource policy summary, pairing state and disabled execution flags.

Pairing preview uses `skybridge.worker_pairing_preview.v1`. Raw pairing codes are never persisted. Local fixtures store only `pairing_code_hash`, and `pairing_code_raw_persisted=false`.

Preview routes:

- `GET /api/workers`
- `GET /api/workers/:id/status`
- `POST /api/workers/register-preview`
- `POST /api/workers/pairing-preview`
- `POST /api/workers/:id/revoke-preview`

Pairing cannot enable execution, remote command dispatch, queue apply, local resource gate bypass, operator approval bypass or human PR review bypass. Every response includes `execution_enabled=false`, `remote_execution_enabled=false`, `arbitrary_command_enabled=false` and `token_printed=false`.

Validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-worker-pairing-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-worker-registration-preview.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-worker-pairing-does-not-enable-execution.ps1
```

Goal 219 can build on this by adding authenticated transport and durable audit policy without changing the no-remote-execution boundary.
