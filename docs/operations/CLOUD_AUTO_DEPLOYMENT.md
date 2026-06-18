# Cloud Auto Deployment

SkyBridge cloud auto deployment is limited to the `skybridge-server` compose service.

Trigger:

- `Deploy Cloud` runs after the `Docker Images` workflow completes successfully on `main`.
- `workflow_dispatch` can run the same fixed script with an explicit image reference.

Gate:

- Docker Images must succeed on `main`.
- Required deploy secrets must exist: `TENCENT_DEPLOY_HOST`, `TENCENT_DEPLOY_USER`, `TENCENT_DEPLOY_SSH_KEY`.
- The image reference must include commit evidence through a digest, `sha-<commit>` tag, or expected immutable tag.

Repository secret bootstrap:

- Verify configured secret names with `gh secret list --repo JerrySkywalker/skybridge-agent-hub`.
- Add the required secrets through GitHub repository settings or `gh secret set`.
- Optional settings may be added only when the default is wrong: `TENCENT_DEPLOY_PORT`, `SKYBRIDGE_DEPLOY_PATH`, `SKYBRIDGE_DEPLOY_COMPOSE_FILE`, `SKYBRIDGE_DEPLOY_SERVICE`, `GHCR_USERNAME`, `GHCR_TOKEN`.
- Do not paste secret values into issues, PRs, logs, docs or deploy reports.
- If the workflow skips with `missing_required_secrets`, the expected safe report lists names only and no SSH step runs.

After secrets are configured, re-run `Deploy Cloud` with `workflow_dispatch` or wait for the next successful `Docker Images` run on `main`. Use an image reference with commit evidence, for example `ghcr.io/<owner>/skybridge-agent-hub-server:sha-<commit>`.

Scope:

- Allowed mutation: `docker compose up -d skybridge-server`.
- Forbidden mutation: Hermes containers, OpenResty, Authelia, DNS, TLS, firewall, host packages and production secrets.

Reports:

- `.agent/tmp/deploy/cloud-deploy-plan.json`
- `.agent/tmp/deploy/cloud-deploy-report.json`
- `.agent/tmp/deploy/cloud-deploy-report.md`

Reports are sanitized and include `token_printed=false`.
