# Cloud Auto Deployment

SkyBridge cloud auto deployment is limited to the `skybridge-server` compose service.

Trigger:

- `Deploy Cloud` runs after the `Docker Images` workflow completes successfully on `main`.
- `workflow_dispatch` can run the same fixed script with an explicit image reference.

Gate:

- Docker Images must succeed on `main`.
- Required deploy secrets must exist in GitHub repository settings. The workflow
  validates names only and must not print values.
- `SKYBRIDGE_PUBLIC_API_BASE` must exist as a GitHub repository variable or
  secret-backed workflow value. Public workflows must not commit
  Jerry-specific deployment hostnames.
- The image reference must include commit evidence through a digest, `sha-<commit>` tag, or expected immutable tag.

Repository secret bootstrap:

- Verify configured secret names with `gh secret list --repo JerrySkywalker/skybridge-agent-hub`.
- Add the required secrets through GitHub repository settings or `gh secret set`.
- Optional settings may be added only when the default is wrong: deploy SSH port,
  `SKYBRIDGE_DEPLOY_PATH`, `SKYBRIDGE_DEPLOY_COMPOSE_FILE`,
  `SKYBRIDGE_DEPLOY_SERVICE`, `GHCR_USERNAME`, `GHCR_TOKEN`.
- Add `SKYBRIDGE_PUBLIC_API_BASE` as a repository variable for the public
  SkyBridge Server API base used by Deploy Cloud parity checks. A repository
  secret may be used instead if the workflow is intentionally changed to read
  from `secrets.*`.
- Do not paste secret values into issues, PRs, logs, docs or deploy reports.
- If the workflow skips with `missing_required_configuration`, the expected
  safe report lists missing secret or variable names only and no SSH step runs.

Current private deployment settings:

- `SKYBRIDGE_DEPLOY_PATH=/opt/skybridge/repo`
- `SKYBRIDGE_DEPLOY_COMPOSE_FILE=deploy/docker-compose.skybridge.yml`
- `SKYBRIDGE_DEPLOY_SERVICE=skybridge-server`

After secrets are configured, re-run `Deploy Cloud` with `workflow_dispatch` or wait for the next successful `Docker Images` run on `main`. Use an image reference with commit evidence, for example `ghcr.io/<owner>/skybridge-agent-hub-server:sha-<commit>`.

Compose contract sync:

- Cloud Auto Deploy uploads only two fixed assets before the remote deploy command: `scripts/deploy/deploy-skybridge-server.sh` and `deploy/docker-compose.skybridge.yml`.
- The compose file is uploaded to a temporary remote path and passed as `--compose-source`; the deploy script installs it to `SKYBRIDGE_DEPLOY_PATH/SKYBRIDGE_DEPLOY_COMPOSE_FILE` after verifying the target resolves under `SKYBRIDGE_DEPLOY_PATH`.
- The previous compose file is backed up under the sanitized deploy report area and restored on deploy failure where possible.
- Do not use `rsync` or sync the full repository for this deploy path.

Scope:

- Allowed mutation: `docker compose up -d skybridge-server`.
- Forbidden mutation: Hermes containers, OpenResty, Authelia, DNS, TLS, firewall, host packages and production secrets.

Reports:

- `.agent/tmp/deploy/cloud-deploy-plan.json`
- `.agent/tmp/deploy/cloud-deploy-report.json`
- `.agent/tmp/deploy/cloud-deploy-report.md`

Reports are sanitized and include `token_printed=false`.

Runtime hygiene:

- Official GitHub Actions should stay on Node 24-compatible major versions,
  currently `actions/checkout@v6`, `actions/setup-node@v6` and
  `actions/upload-artifact@v6`.
- GitHub-hosted `ubuntu-latest` is acceptable for these workflows.
- If a future trusted workflow uses self-hosted runners, those runners must be
  at least `v2.327.1` before Node 24 official actions are used.
- Do not add `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION`.

Version evidence:

- `/v1/version` must report immutable deployed image metadata: `commit_sha=<commit>`, `image_tag=sha-<commit>` and the full image ref when available.
- Release evidence is valid only when `/v1/version.commit_sha` equals the deployed main commit, `/v1/version.image_tag` equals `sha-<deployed main commit>`, `/v1/version.image_ref` equals the immutable GHCR ref and `token_printed=false`.
- `SKYBRIDGE_SERVER_IMAGE` selects the image. Deploy-only variables `SKYBRIDGE_DEPLOY_COMMIT_SHA`, `SKYBRIDGE_DEPLOY_IMAGE_TAG` and `SKYBRIDGE_DEPLOY_IMAGE_REF` are mapped into the container runtime as `SKYBRIDGE_COMMIT_SHA`, `SKYBRIDGE_IMAGE_TAG` and `SKYBRIDGE_IMAGE_REF`.
- Server-local `.env` image defaults are compose defaults only. They are not release evidence and must not override deploy-provided runtime version metadata.
