# GitHub Actions Node Runtime Hygiene

MG366B addresses the known non-failing GitHub Actions Node.js 20 deprecation
annotation recorded by MG365. MG365 inventoried the warning only; MG366B is the
narrow remediation goal for action runtime hygiene.

## Policy

- Do not suppress warnings.
- Do not weaken CI.
- Do not expand workflow permissions.
- Do not change workflow triggers.
- Do not change secrets, deploy targets, image names, image tags, Docker build
  contexts, Dockerfiles, or deploy scripts.
- Do not create releases, tags, or assets.
- `token_printed=false`

## Workflows Inspected

- `.github/workflows/ai-branch-ci.yml`
- `.github/workflows/build-image.yml`
- `.github/workflows/deploy-cloud.yml`
- `.github/workflows/deploy-staging.yml`
- `.github/workflows/pr-ci.yml`
- `.github/workflows/release.yml`

## Actions Identified

The recent Docker Images annotation named these Docker actions as Node.js 20
runtime sources:

- `docker/metadata-action@v5`
- `docker/login-action@v3`
- `docker/setup-buildx-action@v3`
- `docker/build-push-action@v6`

Official action metadata inspected during MG366B showed the following Node.js
24 runtime candidates:

- `docker/metadata-action@v6`
- `docker/login-action@v4`
- `docker/setup-buildx-action@v4`
- `docker/build-push-action@v7`

## Changes Applied

MG366B updates only Docker action major versions:

- `.github/workflows/build-image.yml`
  - `docker/metadata-action@v5` to `docker/metadata-action@v6`
  - `docker/login-action@v3` to `docker/login-action@v4`
  - `docker/setup-buildx-action@v3` to `docker/setup-buildx-action@v4`
  - `docker/build-push-action@v6` to `docker/build-push-action@v7`
- `.github/workflows/release.yml`
  - `docker/metadata-action@v5` to `docker/metadata-action@v6`
  - `docker/login-action@v3` to `docker/login-action@v4`
  - `docker/build-push-action@v6` to `docker/build-push-action@v7`

The workflow topology, permissions, triggers, secrets, deploy targets, Docker
build context, image tags, push behavior, and artifact behavior remain
unchanged.

## Actions Left Unchanged

The repository already uses Node 24-capable major versions for first-party
GitHub actions and pnpm setup in the inspected workflows:

- `actions/checkout@v6`
- `actions/setup-node@v6`
- `actions/upload-artifact@v6`
- `pnpm/action-setup@v6`

These actions were not part of the observed Docker Images deprecation
annotation and are intentionally left unchanged.

## Validation

Use the local audit:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-actions-node-runtime-hygiene.ps1 -Command audit -Json -WriteReport
```

Required post-change checks:

- `smoke:actions-node-runtime-hygiene-status`
- `smoke:actions-node-runtime-hygiene-audit`
- `smoke:actions-node-runtime-hygiene-no-suppression`
- `smoke:actions-node-runtime-hygiene-no-permission-expansion`
- `smoke:actions-node-runtime-hygiene-doc-present`
- PR CI Docker Images check

If any upgraded Docker action requires semantic changes, stop and open a future
goal instead of changing workflow structure in MG366B.

`token_printed=false`
