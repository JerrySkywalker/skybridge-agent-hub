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

For a private operator cloud, load the SkyBridge API endpoint from a local,
untracked file before running the verifier:

```powershell
. "$HOME\.skybridge\skybridge.env.ps1"
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-verify-cloud-autodeploy.ps1
```

`$HOME\.skybridge\skybridge.env.ps1` should contain `SKYBRIDGE_API_BASE` and
point to the SkyBridge Server API. It must not contain the Hermes API key.
`$HOME\.skybridge\hermes.env.ps1` is separate; it contains `HERMES_API_BASE`
and `HERMES_API_KEY` for Hermes. `SKYBRIDGE_API_BASE` is not
`HERMES_API_BASE`.

The verifier resolves ApiBase in this order: explicit `-ApiBase`,
`$env:SKYBRIDGE_API_BASE`, then the public placeholder
`https://skybridge.example.com`. Placeholder, empty and invalid values fail
early for live runs. The verifier also probes `/v1/version` and fails early if
the endpoint looks like Hermes instead of SkyBridge.

For GitHub Actions deploy runs, the public SkyBridge API base belongs in the
repository variable `SKYBRIDGE_PUBLIC_API_BASE` or an equivalent secret-backed
workflow expression. Public workflow files should use `vars.*` or `secrets.*`
indirection and must not commit Jerry-specific deployment hostnames.

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
In non-JSON mode it prints the verification stages from repository/commit
resolution through workflow waits, deploy report validation, route parity and
`/v1/version`. In `-Json` mode stdout remains parseable JSON only. Failure
reports include the stage and a sanitized error summary; they must not include
tokens, cookies, private keys, auth headers, webhooks, raw logs, env dumps or
private endpoint values.

## GitHub Field Compatibility

The scripts intentionally avoid `displayTitle` and `display_title` in `gh run list` JSON fields because local PowerShell JSON parsing failed on that field in the verified manual flow. The verifier uses only stable run fields:

```text
databaseId,headSha,status,conclusion,event,createdAt
```

Workflow selection is done with `gh run list -w "Docker Images"` and `gh run list -w "Deploy Cloud"` rather than parsing title fields.
GitHub Actions `databaseId` values are large identifiers and must be treated as 64-bit values or strings, not 32-bit integers.

## GitHub Actions Runtime Hygiene

Keep official actions on Node 24-compatible major versions. Current workflow
baselines use `actions/checkout@v6`, `actions/setup-node@v6` and
`actions/upload-artifact@v6`. GitHub-hosted `ubuntu-latest` is supported. If a
trusted workflow later moves to self-hosted runners, the runner must be at
least `v2.327.1`; do not add `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION`.

## Release Workflow Note

The current `Release` workflow publishes release images and validation artifacts, but it does not create GitHub Release objects. `skybridge-create-rc-tag.ps1` creates and pushes an annotated Git tag only; it does not create a GitHub Release manually.

## Safety Boundaries

These scripts do not mutate cloud server state, production secrets, DNS, TLS, firewall, OpenResty, Authelia, Hermes or host packages. `skybridge-verify-cloud-autodeploy.ps1` and `skybridge-current-pr-status.ps1` are read-only. `skybridge-create-rc-tag.ps1` is the only script here that mutates state, and its mutation is limited to creating and pushing the explicit annotated tag after verification unless `-SkipVerify` is passed.
