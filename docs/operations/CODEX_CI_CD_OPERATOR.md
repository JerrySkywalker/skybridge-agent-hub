# Codex CI/CD Operator Flow

This runbook captures the Goal 305 operator path for verifying SkyBridge cloud auto deploys without manually filling PR numbers, workflow run IDs or commit SHAs.

## Normal Flow

1. Codex opens a focused PR from a Goal branch.
2. `scripts/powershell/skybridge-current-pr-status.ps1` verifies the current branch has exactly one open PR and that its checks are green.
3. A human/operator merges the PR.
4. `scripts/powershell/skybridge-verify-cloud-autodeploy.ps1` waits for the merged commit's `Docker Images` workflow and the auto-triggered `Deploy Cloud` workflow, downloads the sanitized deploy report artifact and verifies cloud metadata.
5. `scripts/powershell/skybridge-create-rc-tag.ps1` re-runs the verifier by default, then creates and pushes the annotated RC tag.

Use the scripts from repository root:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-current-pr-status.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-verify-cloud-autodeploy.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-create-rc-tag.ps1
```

## Evidence Rules

`Deploy Cloud` evidence must come from the `workflow_run` trigger after `Docker Images` succeeds on `main`. Do not manually trigger `Deploy Cloud` for release evidence, because the goal is to prove the main-branch auto deploy chain.

The verifier checks the deploy report artifact and `/v1/version`. Release evidence is clean only when:

- deploy report `status=succeeded`;
- deploy report `reason=deployed`;
- deploy report `rollback_status=not_used`;
- deploy report `compose_source_provided=true`;
- deploy report `compose_install_status=installed`;
- deploy report image metadata equals `ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-<commit>`;
- `/v1/version.commit_sha=<commit>`;
- `/v1/version.image_tag=sha-<commit>`;
- `/v1/version.image_ref=ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-<commit>`;
- every checked surface reports `token_printed=false`.

The verifier also runs `skybridge-cloud-parity-check.ps1` and fails if cloud route parity is not `ok`.

## GitHub Field Compatibility

The scripts intentionally avoid `displayTitle` and `display_title` in `gh run list` JSON fields because local PowerShell JSON parsing failed on that field in the verified manual flow. The verifier uses only stable run fields:

```text
databaseId,headSha,status,conclusion,event,createdAt
```

Workflow selection is done with `gh run list -w "Docker Images"` and `gh run list -w "Deploy Cloud"` rather than parsing title fields.
GitHub Actions `databaseId` values are large identifiers and must be treated as 64-bit values or strings, not 32-bit integers.

## Release Workflow Note

The current `Release` workflow publishes release images and validation artifacts, but it does not create GitHub Release objects. `skybridge-create-rc-tag.ps1` creates and pushes an annotated Git tag only; it does not create a GitHub Release manually.

## Safety Boundaries

These scripts do not mutate cloud server state, production secrets, DNS, TLS, firewall, OpenResty, Authelia, Hermes or host packages. `skybridge-verify-cloud-autodeploy.ps1` and `skybridge-current-pr-status.ps1` are read-only. `skybridge-create-rc-tag.ps1` is the only script here that mutates state, and its mutation is limited to creating and pushing the explicit annotated tag after verification unless `-SkipVerify` is passed.
