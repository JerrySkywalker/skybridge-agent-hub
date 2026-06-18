# Tencent Deploy Runbook

The GitHub workflow uploads and runs only `scripts/deploy/deploy-skybridge-server.sh`.

Default remote settings:

- `SKYBRIDGE_DEPLOY_PATH=/opt/skybridge-agent-hub`
- `SKYBRIDGE_DEPLOY_COMPOSE_FILE=compose.yaml`
- `SKYBRIDGE_DEPLOY_SERVICE=skybridge-server`

Required GitHub repository secrets:

- `TENCENT_DEPLOY_HOST`
- `TENCENT_DEPLOY_USER`
- `TENCENT_DEPLOY_SSH_KEY`

Optional GitHub repository secrets:

- `TENCENT_DEPLOY_PORT`
- `SKYBRIDGE_DEPLOY_PATH`
- `SKYBRIDGE_DEPLOY_COMPOSE_FILE`
- `SKYBRIDGE_DEPLOY_SERVICE`
- `GHCR_USERNAME`
- `GHCR_TOKEN`

Safe preflight:

```powershell
gh secret list --repo JerrySkywalker/skybridge-agent-hub
gh run list --workflow deploy-cloud.yml --limit 5
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-cloud-parity-check.ps1
```

If no repository secrets are configured, `Deploy Cloud` must stop before SSH and upload a sanitized skipped report with missing secret names only.

Manual dry-run:

```bash
SKYBRIDGE_DEPLOY_SERVICE=skybridge-server \
  bash scripts/deploy/deploy-skybridge-server.sh \
  --dry-run \
  --image-ref ghcr.io/jerry1999-main/skybridge-agent-hub-server:sha-<commit> \
  --commit-sha <commit> \
  --expected-tag sha-<commit>
```

Post-deploy public checks:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-cloud-parity-check.ps1
```

Do not run broad remote shell commands, package installs, Docker prune commands or any Hermes/OpenResty/Authelia/DNS/TLS/firewall changes as part of this runbook.
