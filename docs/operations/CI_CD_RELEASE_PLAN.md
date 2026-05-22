# CI/CD And Release Plan

SkyBridge Agent Hub uses public, secret-free CI by default. Release and deployment automation must be reproducible, reviewable and safe for an open-source repository.

## Current Audit

Existing automation before this plan:

- `.github/workflows/pr-ci.yml` runs install, `pnpm check`, PowerShell parse validation, operator console smoke and dev/test compose config checks on pull requests.
- `.github/workflows/ai-branch-ci.yml` runs similar checks on `ai/**` pushes.
- `.github/workflows/build-image.yml` builds and pushes server and web images, but only tags by commit SHA.
- `.github/workflows/deploy-staging.yml` is a non-deploying placeholder.
- `deploy/docker-compose.dev.yml` and `deploy/docker-compose.test.yml` support local validation.
- `deploy/docker-compose.prod.yml` exists as a production template but needs explicit env, health, image tag and rollback assumptions.
- `deploy/scripts/*.sh` provide initial backup, deploy, healthcheck and rollback hooks.
- `scripts/powershell/*` contains safe local smoke scripts for the Operator Console, Codex hooks and runner behavior.

## Workflow Set

### 1. PR CI

Trigger: `pull_request` to `main`.

Runs on GitHub-hosted runners only. It must not require secrets or privileged self-hosted infrastructure.

Required checks:

- Corepack and pnpm install.
- `corepack pnpm check`.
- PowerShell parse validation for `scripts/powershell/*.ps1`.
- Safe line-ending and diff hygiene checks.
- Docker compose config validation for dev and test compose files.
- Safe smoke scripts that use temporary files and do not require secrets.
- Browser visual QA optional smoke in skip-safe mode, uploading only the sanitized log unless fixture screenshots are enabled in a later reviewed change.
- Upload safe smoke logs or summaries when failures occur.

### 2. AI Branch CI

Trigger: pushes to `ai/**`.

Runs the PR CI baseline plus AI-run-specific local smoke:

- Operator Console smoke in temporary SQLite mode.
- Browser visual QA optional smoke in skip-safe mode.
- Codex hook smoke in safe temporary spool/server mode.
- Release dry-run smoke once available.

No AI branch job may require repository secrets, production env files or deployment credentials.

### 3. Docker Image Build

Trigger: pull requests, `main`, tags and manual dispatch.

Runs build-only validation on PRs. Pushes are disabled for untrusted PR contexts.

Required checks:

- Build server image.
- Build web image.
- Use `.dockerignore` to exclude `.agent`, `.data`, `node_modules`, logs and env files.
- Document health paths and runtime environment variables.

### 4. GHCR Publish

Trigger: `main`, `v*` tags and manual dispatch.

Uses only `GITHUB_TOKEN` with least-privilege permissions:

- `contents: read`
- `packages: write`

Image tags:

- `sha-<short-sha>`
- `main` for the `main` branch
- sanitized branch tag for other trusted branches when manually dispatched
- semantic version tag for `v*` releases

### 5. Staging Dry-Run

Trigger: manual dispatch and `main`.

This workflow renders and validates the staging deployment plan without deploying:

- Confirms the requested image tag is syntactically safe.
- Confirms env file behavior without printing secrets.
- Renders the production compose template.
- Runs safe health target validation where possible.
- Uploads sanitized dry-run output.

It must not run `docker compose up`, mutate a server, SSH to infrastructure or use production secrets.

### 6. Release / Tag Validation

Trigger: `v*` tags and manual dispatch.

Required release checks:

- Full project checks.
- PowerShell and shell script parse validation.
- Compose config validation.
- Docker image build and GHCR publish.
- Release dry-run smoke.
- Draft release notes artifact or GitHub release draft when permissions allow.

## Public Repository Runner Policy

Public pull requests must never run privileged self-hosted deployment jobs. All PR and AI-branch checks must be safe on GitHub-hosted runners with no secrets.

Self-hosted runners, if added later, may only be used for manually approved deployment jobs in a trusted private context. They must be isolated from public PR triggers and must not receive untrusted pull request code.

## Secrets Policy

CI must not print:

- `.env` contents;
- tokens;
- ntfy credentials;
- database dumps;
- `.agent/runs` logs;
- `.data` files;
- full command output captured from agents.

Deploy scripts validate whether an env file exists but do not print values.

## Release Promotion Model

Recommended flow:

1. Merge reviewed PR to `main`.
2. Public CI passes.
3. GHCR images publish with `sha-*` and `main` tags.
4. Create and push `vX.Y.Z` tag.
5. Release workflow validates checks, publishes semver image tags and creates release notes output.
6. Operator performs a staging dry-run using the target image tag.
7. A separate authorized deployment step may pull the validated image and run backup, deploy, healthcheck, notification and rollback scripts.

Production deployment remains manual and outside public PR automation until explicitly authorized.
