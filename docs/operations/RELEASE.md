# Release Workflow

SkyBridge releases are tag based.

## Version Tags

Use semantic version tags prefixed with `v`:

```bash
git tag v0.3.0
git push origin v0.3.0
```

The release workflow runs full checks, validates compose files, runs the release dry-run smoke, builds images and publishes GHCR tags.

## Images

Images are published to:

- `ghcr.io/<owner>/skybridge-agent-hub-server`
- `ghcr.io/<owner>/skybridge-agent-hub-web`

Expected tags:

- `sha-<commit>`
- `main`
- `vX.Y.Z`

## Local Release Dry-Run

Before tagging, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-release-dry-run.ps1
```

This validates workflows, compose files, Dockerfiles, required docs and safe smoke script availability without requiring secrets.

## Staging Promotion

After images publish:

```bash
SKYBRIDGE_IMAGE_TAG=v0.3.0 bash deploy/scripts/staging-dry-run.sh v0.3.0
```

Only after the dry-run is reviewed should an operator perform a real deployment in an authorized environment.

## Rollback

Keep `current-version` and `previous-version` markers in the deployment directory. Use:

```bash
APP_DIR=/opt/skybridge ./scripts/rollback.sh
```

See `docs/operations/BACKUP_ROLLBACK.md` for backup and rollback details.

## Safety Rules

- Do not deploy from public pull request workflows.
- Do not put production secrets in GitHub Actions logs or artifacts.
- Do not use privileged self-hosted runners for untrusted PR code.
- Do not auto-merge or auto-deploy tags without a separate explicit authorization step.
