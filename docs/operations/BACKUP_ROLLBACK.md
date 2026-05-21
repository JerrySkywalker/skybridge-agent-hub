# Backup And Rollback

SkyBridge deployment scripts are conservative by default. They do not delete data, prune Docker state or print secrets.

## Backup

Run from the deployment directory:

```bash
APP_DIR=/opt/skybridge ./scripts/backup.sh
```

The script writes timestamped archives under `backups/` and includes:

- `docker-compose.prod.yml` when present;
- `current-version` and `previous-version` markers when present;
- the configured data directory, defaulting to `$APP_DIR/data`.

It intentionally does not archive `.env` values. Operators should back up secrets through their normal secret-management process.

## Rollback

Rollback uses the `previous-version` marker:

```bash
APP_DIR=/opt/skybridge ./scripts/rollback.sh
```

The script sets `SKYBRIDGE_IMAGE_TAG`, pulls the previous image tag, recreates services with Docker Compose, runs the health check and updates `current-version` only after health passes.

## Notifications

`deploy/scripts/notify-deploy.sh` sends ntfy-first deployment notifications when `NTFY_TOPIC_URL` is configured. It never sends env file contents or tokens.

Supported events:

- `deploy-started`
- `deploy-succeeded`
- `deploy-failed`
- `rollback-started`
- `rollback-succeeded`
- `rollback-failed`

## Safety Notes

- No script deletes backups or data by default.
- No script runs Docker prune commands.
- The public repository does not contain production env files.
- Real production deployment remains a manual operator action until explicitly authorized.
