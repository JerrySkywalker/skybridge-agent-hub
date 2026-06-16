# Live-local Server Rehearsal

Status: v2.1 RC preview.

The live-local rehearsal promotes the previous fixture-only auth rehearsal into a bounded loopback fixture server. It is still not production identity and it does not enable worker execution, workunit apply, task claim, queue apply, arbitrary command dispatch, remote execution, or host mutation.

## Script

`scripts/powershell/skybridge-live-local-server.ps1`

Commands:

- `status`
- `plan`
- `start-fixture`
- `stop-fixture`
- `auth-request`
- `route-check`
- `e2e-preview`
- `safe-summary`
- `report`

## Server Boundary

- Binds only to `127.0.0.1`.
- Uses a bounded temporary fixture process.
- Uses fixture/hash-only session state.
- Persists safe metadata reports only.
- Rejects remote origins.
- Rejects command-shaped payloads.
- Rejects authorization header values.
- Leaves no background process after report and E2E commands.

## Reports

- `.agent/tmp/live-local/live-local-server-report.json`
- `.agent/tmp/live-local/live-local-server-report.md`
- `.agent/tmp/live-local/live-local-e2e-report.json`
- `.agent/tmp/live-local/v2.1-live-local-rc-report.json`
- `.agent/tmp/live-local/v2.1-live-local-rc-report.md`
