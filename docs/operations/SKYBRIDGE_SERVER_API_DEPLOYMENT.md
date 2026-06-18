# SkyBridge Server API Deployment

This document describes the deployment shape for direct worker connectivity. It is guidance only; this repository change does not modify real OpenResty, Authelia, 1Panel, Docker daemon or production server configuration.

## Public API Target

Use a dedicated HTTPS subdomain for SkyBridge Server. The first planned endpoint is:

```text
https://skybridge.example.com
```

Generic examples may use:

```text
https://skybridge.example.com
```

Workers should set:

```text
SKYBRIDGE_API_BASE=https://skybridge.example.com
```

Local development remains:

```text
http://127.0.0.1:8787
```

## Reverse Proxy Concept

A production deployment should put SkyBridge Server behind a reverse proxy such as OpenResty:

```text
worker -> HTTPS reverse proxy -> SkyBridge Server
```

The proxy should terminate TLS, preserve the request path, forward `Authorization` headers, enforce sane body limits and expose only the SkyBridge API. Do not proxy Hermes publicly.

See `docs/operations/openresty-skybridge.example.conf` for a template server block.

## Auth Boundary

SkyBridge worker routes support bearer token auth when the server has worker tokens configured:

```text
SKYBRIDGE_WORKER_TOKEN=<local server-side token>
SKYBRIDGE_WORKER_TOKENS_FILE=/srv/skybridge/worker-tokens.txt
```

`SKYBRIDGE_WORKER_TOKENS_FILE` should contain one token per line. Blank lines and `#` comments are ignored. Token values must not be logged, committed or sent to clients.

Authelia or another identity-aware proxy may protect human/browser surfaces later, but worker token auth is the worker-to-server boundary. Keep those concerns separate.

## Health Endpoint

Workers should validate server reachability before polling:

```text
GET /v1/health
```

Health does not prove worker authorization. Worker auth is proven by a protected worker route such as registration or heartbeat.

Use the remote smoke script for the first registration test:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-remote-skybridge-api.ps1 `
  -ApiBase https://skybridge.example.com `
  -TokenEnvVar SKYBRIDGE_WORKER_TOKEN `
  -WorkerSmoke `
  -AuthFailureCheck `
  -Json
```

## Hermes Boundary

Hermes remains private. It is an optional `PlannerAdapter` and should call SkyBridge APIs through private infrastructure. Do not expose the Hermes API as a public dependency for workers.

## Token Rotation

Recommended rotation flow:

1. Add the new token to `SKYBRIDGE_WORKER_TOKENS_FILE`.
2. Restart or reload the SkyBridge Server process.
3. Update worker local env/file configuration.
4. Verify `smoke-worker-token-auth.ps1` or an explicit remote registration smoke.
5. Remove the old token from the file.
6. Restart or reload the server again.

If using `SKYBRIDGE_WORKER_TOKEN`, replace the environment value and restart the server.

## Rollback Or Disable

To disable a compromised worker:

- remove or rotate its token;
- disable the worker record through the existing worker API/operator controls;
- stop the local worker loop;
- inspect task claims and evidence summaries before requeueing work.

To roll back remote worker access entirely, remove the public reverse proxy route or stop SkyBridge Server. Do not expose Hermes as a fallback.

## Current Gaps

- No production deployment is implemented here.
- No token issuing, revocation API or scoped token registry exists yet.
- No replay-resistant request signing exists yet.
- No branch protection or GitHub settings mutation is performed by this deployment model.
- First real cloud deployment wiring and remote worker heartbeat still require operator-side server setup.
