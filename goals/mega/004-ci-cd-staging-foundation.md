# Mega Goal 004: CI/CD And Staging Foundation

## Mission

Build the reviewable CI/CD and staging foundation for SkyBridge without deploying production or touching secrets. The result should make branches, PRs, images and future staging promotion safer and more repeatable.

Estimated effort: 6-10 hours of sustained Codex TUI work.

Do not implement this goal as part of workflow planning. Execute it only when explicitly selected in Codex TUI.

## Context Files To Read

- `AGENTS.md`
- `README.md`
- `ARCHITECTURE.md`
- `DEVELOPMENT.md`
- `SECURITY.md`
- `docs/codex/TUI_MASTER_GOAL.md`
- `docs/codex/AUTONOMOUS_RUNNER.md`
- `docs/dev/PROGRESS.md`
- `.github/workflows/`
- `deploy/`
- `Dockerfile` or package Docker files if present
- `package.json`
- `pnpm-workspace.yaml`

## Staged Sub-Goals

1. Audit current GitHub Actions, Docker compose and build-image state.
2. Tighten PR checks for lint, typecheck, test and build without requiring production secrets.
3. Add or improve image build validation for server/web packages where appropriate.
4. Document a staging promotion plan that is explicit about manual secret handling and forbidden production changes.
5. Add local validation scripts or docs for compose and image checks.
6. Add follow-up goals for actual staging deployment if human authorization is needed.

## Expected Commits

- `ci: harden pull request checks`
- `build: validate SkyBridge container images`
- `docs(deploy): document staging foundation`

Adjust commit boundaries to the actual implementation, but keep each commit reviewable and passing.

## Checks

- `corepack pnpm check`
- `docker compose -f deploy/docker-compose.dev.yml config` if compose files change.
- `docker compose -f deploy/docker-compose.test.yml config` if compose files change.
- Workflow syntax inspection for changed GitHub Actions files.
- `just check` before stopping, or `corepack pnpm check` if `just` is unavailable.

## Stop Conditions

Stop and record progress if:

- a change requires production credentials or server root access;
- a workflow needs repository secrets that are not already available and documented;
- Docker build behavior depends on an unavailable external registry;
- the work would deploy or mutate live infrastructure.

## Safety Boundaries

- Do not deploy.
- Do not modify production secrets.
- Do not modify `/opt/skybridge-agent-hub/.env`.
- Do not alter root-level OpenResty, Authelia, 1Panel or Docker daemon configuration.
- Do not force-push `main`.
- Do not enable auto-merge without explicit approval.

## Progress Logging Requirements

- Add a dated entry to `docs/dev/PROGRESS.md` for each completed stage.
- Include changed workflows, validation commands and check results.
- Record required manual secret or infrastructure steps as follow-up goals.
