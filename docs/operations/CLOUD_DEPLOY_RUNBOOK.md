# Cloud Deploy Runbook

The GitHub workflow uploads only the fixed deploy script and skybridge-server compose contract, then runs `scripts/deploy/deploy-skybridge-server.sh`.

Default remote settings:

- `SKYBRIDGE_DEPLOY_PATH=/opt/skybridge/repo`
- `SKYBRIDGE_DEPLOY_COMPOSE_FILE=deploy/docker-compose.skybridge.yml`
- `SKYBRIDGE_DEPLOY_SERVICE=skybridge-server`

Required GitHub repository secrets:

- deploy host
- deploy user
- deploy SSH key

Optional GitHub repository secrets:

- deploy SSH port
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
  --compose-source deploy/docker-compose.skybridge.yml \
  --image-ref ghcr.io/jerry1999-main/skybridge-agent-hub-server:sha-<commit> \
  --commit-sha <commit> \
  --expected-tag sha-<commit>
```

Compose contract sync:

- The workflow uploads `scripts/deploy/deploy-skybridge-server.sh` to `/tmp/deploy-skybridge-server.sh`.
- The workflow uploads `deploy/docker-compose.skybridge.yml` to `/tmp/docker-compose.skybridge.yml`.
- The workflow invokes the deploy script with `--compose-source /tmp/docker-compose.skybridge.yml`.
- The deploy script installs that file to `SKYBRIDGE_DEPLOY_PATH/SKYBRIDGE_DEPLOY_COMPOSE_FILE` only after confirming the resolved target stays under `SKYBRIDGE_DEPLOY_PATH`.
- The previous compose file is backed up under the sanitized deploy report area and restored on deploy failure where possible.

Post-deploy public checks:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-cloud-parity-check.ps1
```

Version evidence:

- `/v1/version` is the release evidence endpoint for the deployed server image.
- Expected values after a commit deploy are `commit_sha=<commit>` and `image_tag=sha-<commit>`.
- Full acceptance requires `image_ref=ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-<commit>` and `token_printed=false`.
- `SKYBRIDGE_SERVER_IMAGE` remains the full immutable image ref used for image selection.
- Deploy-only variables `SKYBRIDGE_DEPLOY_COMMIT_SHA`, `SKYBRIDGE_DEPLOY_IMAGE_TAG` and `SKYBRIDGE_DEPLOY_IMAGE_REF` are mapped into container runtime variables `SKYBRIDGE_COMMIT_SHA`, `SKYBRIDGE_IMAGE_TAG` and `SKYBRIDGE_IMAGE_REF`.
- Server-local `.env` values such as `SKYBRIDGE_IMAGE_TAG=main` are defaults or legacy local state, not release evidence.

Do not run broad remote shell commands, package installs, Docker prune commands or any Hermes/OpenResty/Authelia/DNS/TLS/firewall changes as part of this runbook.
