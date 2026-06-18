# Self-Bootstrap Readiness Audit

`skybridge-self-bootstrap-readiness.ps1` is a read-only operator audit for the intended queue-driven, Hermes-audited SkyBridge self-bootstrap loop.

The audit answers one question: can a later, explicitly authorized operator command safely start one bounded task or continue until the next hold? It does not start Codex, claim tasks, call queue apply, advance campaign metadata, trigger Deploy Cloud, create tags or mutate the cloud host.

## Run

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-self-bootstrap-readiness.ps1 -Json
```

Useful options:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-self-bootstrap-readiness.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -CampaignId dev-queue-189-200 `
  -Json
```

For authenticated read-only status endpoints, pass `-TokenFile` or `-TokenEnvVar`. For Hermes, pass `-HermesEnvFile` or `-HermesApiBase` when the default local Hermes environment loader is not enough.

## Output Contract

The script emits:

```text
schema = skybridge.self_bootstrap_readiness.v1
status = ready | blocked | partial | unknown
can_start_one = true | false
can_run_until_hold = true | false
blockers = [...]
warnings = [...]
required_human_action = string
token_printed = false
```

It also includes safe summaries for:

- git branch, clean status, HEAD and main commit;
- cloud `/v1/version` commit and image reference;
- cloud route parity;
- latest Deploy Cloud evidence from `skybridge-verify-cloud-autodeploy.ps1`;
- project control state;
- queued, claimed, running, stale lease and stale task counts;
- worker online/stale/offline counts;
- campaign queue counts;
- Hermes health with a redacted endpoint only;
- notification provider status.

The report intentionally excludes raw prompts, raw Hermes responses, raw logs, token values, cookies, credentials and environment dumps.

## Readiness Policy

`ready` requires all of these to be true:

- current branch is `main`;
- worktree is clean;
- cloud `/v1/version` matches the local main commit;
- cloud route parity is `ok`;
- Deploy Cloud evidence is successful for the same main commit;
- project control is not running and stop is not requested;
- no queued, claimed, running or stale task residue exists;
- at least one worker is online;
- at least one campaign is ready or paused;
- Hermes health is OK over direct HTTPS;
- at least one notification provider is ready;
- `token_printed=false`.

`blocked` means at least one hard gate failed. The script reports a concise `required_human_action`; use the relevant operator flow to repair the condition. This script must not be used to repair or apply anything.

`partial` means no hard blocker was found, but one or more optional signals were unavailable or warning-only evidence needs review.

## Smokes

Run the fixture-only smoke suite:

```powershell
corepack pnpm smoke:self-bootstrap-readiness
```

The smoke covers:

- ready report;
- blocked report when the worker is offline;
- blocked report when stale leases are present;
- blocked report when Hermes is unavailable;
- `token_printed=false` and no secret-like output.

These smokes write only ignored fixture files under `.agent/tmp/self-bootstrap-readiness-smoke/`.
