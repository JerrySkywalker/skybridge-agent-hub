# SkyBridge Cloud Topology

The first cloud topology keeps SkyBridge Server public through a narrow HTTPS API endpoint while leaving execution providers private.

## Target Endpoint

Planned public endpoint:

```text
https://skybridge.example.com
```

Local development remains:

```text
http://127.0.0.1:8787
```

## Components

```text
remote worker
  -> HTTPS skybridge.example.com
  -> OpenResty reverse proxy
  -> SkyBridge Server container/process on loopback/internal network
  -> SQLite volume
```

SkyBridge Server owns projects, goals, tasks, worker registration, worker heartbeats, EvidenceSummary records and safe event data.

OpenResty terminates TLS through the existing panel/certificate manager and proxies only SkyBridge paths to the server. It should preserve `Authorization` headers and support server-sent events.

Authelia may protect human UI routes later. Worker API authentication remains app-level bearer-token auth with `SKYBRIDGE_WORKER_TOKEN` or `SKYBRIDGE_WORKER_TOKENS_FILE`.

Hermes API remains private on loopback or an internal network. Do not proxy Hermes through the public SkyBridge host.

ntfy remains an optional NotificationProvider. Notification credentials are separate from worker tokens and must stay outside the repository.

## Worker Boundary

Workers use local profiles with:

```json
{
  "skybridge_api_base": "https://skybridge.example.com",
  "auth_mode": "bearer_token",
  "allow_remote_server": true,
  "reject_insecure_http_for_remote": true
}
```

The worker token is read from an environment variable or local token file and sent as `Authorization: Bearer <token>`. Tokens are never committed or printed.

## Rollback And Disable

To disable remote workers:

1. Remove or rotate `SKYBRIDGE_WORKER_TOKEN` / `SKYBRIDGE_WORKER_TOKENS_FILE`.
2. Restart the SkyBridge Server process or container.
3. Disable affected worker records through operator controls if needed.
4. Stop local worker loops and requeue only reviewed tasks.

To disable public SkyBridge API access:

1. Remove or disable the OpenResty SkyBridge location/server block.
2. Confirm `https://skybridge.example.com/v1/health` no longer reaches SkyBridge.
3. Keep Hermes private; do not expose it as a fallback.

No GitHub settings, branch protection, production deploy automation or unattended auto-merge behavior is changed by this topology.
