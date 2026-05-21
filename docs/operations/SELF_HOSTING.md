# Self Hosting

SkyBridge self-hosting is safe to rehearse locally, but this repository does not deploy to production automatically.

## Local Dry-Run

```powershell
docker compose -f deploy/docker-compose.prod.yml config
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-release-dry-run.ps1
```

## Required Operator Inputs

- image tag, such as `main` or `v0.9.0`;
- external env file stored outside Git;
- public API base URL;
- backup location;
- notification topic, if used.

Never commit real `.env` files, tokens, SSH keys or production server credentials.

## Health Path

The server health endpoint is:

```text
GET /health
GET /v1/health
```

Staging automation remains dry-run until a future explicitly authorized goal changes that boundary.
