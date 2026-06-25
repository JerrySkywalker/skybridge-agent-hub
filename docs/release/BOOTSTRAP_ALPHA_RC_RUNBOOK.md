# Bootstrap Alpha RC Runbook

This runbook verifies Bootstrap Alpha RC without creating tasks, claiming
tasks, executing Codex or MATLAB, starting a worker loop, mutating production
infrastructure, creating a tag, or creating a GitHub release.

## Cloud Deploy Verification

Verify the deployed server image and route parity:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-alpha-rc-gate.ps1 -Command cloud -ApiBase https://skybridge.jerryskywalker.space -ExpectedCommit 8499ccba39894fdfccb7b29ddfe72db142ddb711 -ExpectedImageRef ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-8499ccba39894fdfccb7b29ddfe72db142ddb711 -Json
```

The cloud check reads `/v1/version`, route parity, operator report, review
gate, and self-bootstrap convergence summaries. It does not deploy, change
server configuration, create tasks, claim tasks, or execute work.

For a post-MG340 deploy audit, pass the deployed MG340 merge SHA and image ref
to `-ExpectedCommit` and `-ExpectedImageRef`; the release notes and tag plan
still record the MG339 runtime baseline that the RC gate packages.

## Local Desktop Start And Check

For browser-only Desktop rendering:

```powershell
corepack pnpm -C apps/desktop dev
```

For the full Tauri app:

```powershell
corepack pnpm -C apps/desktop tauri:dev
```

The Bootstrap Alpha panels should remain status/preview oriented. Live apply
controls for safe task, MATLAB, and Codex proof paths remain disabled in
Desktop and are PowerShell exact-confirmation only.

## Worker Identity And Heartbeat Check

Preview worker identity:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-identity.ps1 -Command preview -WorkerId jerry-win-local-01 -WorkerName "Jerry Windows Local Worker" -Provider local-windows -Json
```

Preview live heartbeat:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-live-heartbeat.ps1 -Command preview -Json
```

The RC gate may look up the cloud worker status if the API base and token file
are configured. It does not perform a task claim check.

## Worker Service Status Check

Use the existing local status and doctor checks:

```powershell
corepack pnpm smoke:worker-identity-preview
corepack pnpm smoke:worker-live-heartbeat-preview
```

These are preview-only and must keep claim, execution, Codex, MATLAB, worker
loop, arbitrary shell, and project-control mutations disabled.

## Chat-To-Task Draft Check

```powershell
corepack pnpm smoke:chat-to-task-draft
```

Expected boundary: draft preview only. No server task creation, no campaign
creation, no raw prompt persistence, no Codex, no MATLAB, and
`token_printed=false`.

## Template Registry Check

```powershell
corepack pnpm smoke:task-template-registry
```

Expected boundary: read-only template metadata. No task creation, claim,
Codex, MATLAB, arbitrary shell, or worker loop.

## Draft Submit Preview Check

```powershell
corepack pnpm smoke:draft-submit-preview
```

Expected boundary: preview creates nothing. Any apply path remains exact
confirmation only and does not execute the queued record.

## Live Safe Task Evidence Check

Read-only report:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-safe-task-pilot.ps1 -Command report -Json
```

Expected task: `live-safe-template-task-332-001`, final state `completed`, safe
evidence present, no Codex, no MATLAB, no arbitrary shell, no worker loop, no
project-control unpause, and `token_printed=false`.

## MATLAB Golden Evidence Check

Read-only report:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-matlab-golden-success.ps1 -Command report -Json
```

Expected task: `live-matlab-golden-task-336-001`, final state `completed`,
manifest/summary/metrics exist, `completed_count=2`, `failed_count=0`,
`expected_combination_count=2`, no raw stdout/stderr, no Codex, no arbitrary
shell, no worker loop, and `token_printed=false`.

## Codex Native Report Evidence Check

Read-only report:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-codex-analysis-report-native-success.ps1 -Command report -Json
```

Expected task: `live-codex-analysis-report-task-339-001`, final state
`completed`, `final_report_source=codex_native`, `fallback_report_used=false`,
`native_report_valid=true`, `validation_status=passed`,
`codex_failure_category=none`, report exists, and `token_printed=false`.

## RC Gate And Report

Run the full audit and write safe local artifacts:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-alpha-rc-gate.ps1 -Command audit -WriteReport -Json
```

Safe local report paths:

- `.agent/tmp/bootstrap-alpha-rc/bootstrap-alpha-rc-report.md`
- `.agent/tmp/bootstrap-alpha-rc/bootstrap-alpha-rc-report.json`

The reports must not contain raw logs, raw prompts, stdout/stderr dumps, token
values, runtime snapshots, provider auth headers, cookies, or proxy profiles.

## Recovery Guidance

- If cloud version or image does not match the expected RC baseline, stop and
  verify deploy state through the existing Deploy Cloud workflow. Do not invent
  a new deploy path.
- If route parity fails, inspect the route parity report and keep the RC gate
  blocked until the deployed server is healthy.
- If worker lookup is unavailable, verify worker identity and heartbeat config.
  Do not claim tasks as part of RC validation.
- If live safe task, MATLAB, or Codex evidence is missing, preserve the failed
  or recovery task state. Do not requeue old tasks.
- If any evidence includes raw prompt/log/stdout/stderr/token material, keep the
  RC blocked and repair evidence sanitization before tag approval.

## Forbidden Actions In RC

- No task creation.
- No task claim.
- No task execution.
- No Codex execution.
- No MATLAB execution.
- No worker loop start.
- No notification send.
- No arbitrary shell execution surface.
- No unbounded run.
- No daemon auto-expansion.
- No project-control unpause.
- No old task requeue.
- No tag creation.
- No GitHub release creation.

## Proceeding To RC Tag

After operator review, a future explicitly authorized goal may create the tag
from [Bootstrap Alpha Tag Plan](BOOTSTRAP_ALPHA_TAG_PLAN.md). MG340 itself
must leave `tag_created=false`.
