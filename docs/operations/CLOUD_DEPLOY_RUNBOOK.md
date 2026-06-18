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

Required GitHub repository variables:

- `SKYBRIDGE_PUBLIC_API_BASE`

`SKYBRIDGE_PUBLIC_API_BASE` is the public SkyBridge Server API base used for
post-deploy parity checks. Keep it in GitHub repository variables or secrets;
do not hard-code Jerry-specific hostnames in public workflow files. If the
variable is empty, `Deploy Cloud` stops before SSH and uploads a sanitized
`missing_required_configuration` report with variable names only.

Safe preflight:

```powershell
gh secret list --repo JerrySkywalker/skybridge-agent-hub
gh run list --workflow deploy-cloud.yml --limit 5
. "$HOME\.skybridge\skybridge.env.ps1"
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-cloud-parity-check.ps1
```

`$HOME\.skybridge\skybridge.env.ps1` is the local, untracked SkyBridge operator
env file. It should set `SKYBRIDGE_API_BASE` to the SkyBridge Server API base.
Do not put Hermes credentials in this file.

Keep Hermes configuration in `$HOME\.skybridge\hermes.env.ps1` instead:

```powershell
$env:HERMES_API_BASE = "<PRIVATE_HERMES_API_BASE>"
$env:HERMES_API_KEY = "<local Hermes key>"
```

`SKYBRIDGE_API_BASE` is not `HERMES_API_BASE`. SkyBridge deployment and parity
scripts use `SKYBRIDGE_API_BASE` or explicit `-ApiBase`; Hermes health and
planning scripts use `HERMES_API_BASE` plus `HERMES_API_KEY`.

If no repository secrets are configured, `Deploy Cloud` must stop before SSH and upload a sanitized skipped report with missing secret names only.
If `SKYBRIDGE_PUBLIC_API_BASE` is not configured, it must also stop before SSH
and report the missing variable name only.

GitHub-hosted `ubuntu-latest` runners are supported. If this workflow is moved
to self-hosted runners, update the runner to at least `v2.327.1` before using
official Node 24 actions such as `actions/checkout@v6`,
`actions/setup-node@v6` or `actions/upload-artifact@v6`. Do not use
`ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION`.

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
. "$HOME\.skybridge\skybridge.env.ps1"
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-cloud-parity-check.ps1
```

For live checks, placeholder values such as `https://skybridge.example.com`,
`<PRIVATE_SKYBRIDGE_API_BASE>`, empty values and invalid URIs fail before route
probing. If `/v1/version` looks like Hermes metadata or capabilities, the
script fails with a SkyBridge-vs-Hermes endpoint diagnostic and does not print
the private URL.

Version evidence:

- `/v1/version` is the release evidence endpoint for the deployed server image.
- Expected values after a commit deploy are `commit_sha=<commit>` and `image_tag=sha-<commit>`.
- Full acceptance requires `image_ref=ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-<commit>` and `token_printed=false`.
- `SKYBRIDGE_SERVER_IMAGE` remains the full immutable image ref used for image selection.
- Deploy-only variables `SKYBRIDGE_DEPLOY_COMMIT_SHA`, `SKYBRIDGE_DEPLOY_IMAGE_TAG` and `SKYBRIDGE_DEPLOY_IMAGE_REF` are mapped into container runtime variables `SKYBRIDGE_COMMIT_SHA`, `SKYBRIDGE_IMAGE_TAG` and `SKYBRIDGE_IMAGE_REF`.
- Server-local `.env` values such as `SKYBRIDGE_IMAGE_TAG=main` are defaults or legacy local state, not release evidence.

Do not run broad remote shell commands, package installs, Docker prune commands or any Hermes/OpenResty/Authelia/DNS/TLS/firewall changes as part of this runbook.
