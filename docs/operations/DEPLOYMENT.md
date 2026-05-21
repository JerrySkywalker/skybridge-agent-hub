# Deployment Notes

Deployment automation in this repository is intentionally conservative. It supports release validation, image publishing, staging dry-run, backup, rollback and notifications. It does not automatically deploy production from public CI.

## Staging

Staging is currently dry-run only:

```bash
SKYBRIDGE_IMAGE_TAG=main bash deploy/scripts/staging-dry-run.sh main
```

The dry-run validates the image tag, checks env file presence without printing secrets, renders `deploy/docker-compose.prod.yml` and reports the health target it would use. It does not start containers or mutate a server.

## Production

Production should be tag/release based.

Recommended flow:

```text
tag pushed
build images
push GHCR
cloud server pulls image
backup
compose up
healthcheck
rollback on failure
notify
```

## Server path

Recommended path:

```text
/opt/skybridge
```

Do not store secrets in the public repository.

## Production Compose Template

`deploy/docker-compose.prod.yml` expects:

- `SKYBRIDGE_IMAGE_REGISTRY`, defaulting to `ghcr.io/jerry1999-main`;
- `SKYBRIDGE_IMAGE_TAG`, defaulting to `latest`;
- `SKYBRIDGE_ENV_FILE`, defaulting to `.env`;
- `SKYBRIDGE_PUBLIC_API_BASE`, defaulting to `http://127.0.0.1:8787`;
- a named `skybridge-data` volume for SQLite persistence.

The env file is optional for rendering so public CI can validate the template. Operators must provide real secret values outside Git before a real deployment.

## Operator Scripts

- `deploy/scripts/backup.sh` writes timestamped non-destructive backups.
- `deploy/scripts/deploy.sh` supports `DRY_RUN=true` and uses `SKYBRIDGE_IMAGE_TAG`.
- `deploy/scripts/rollback.sh` rolls back to the `previous-version` marker after a health check.
- `deploy/scripts/notify-deploy.sh` sends ntfy-first status notifications when configured.
- `deploy/scripts/healthcheck.sh` validates the server health endpoint.
