# Run-Until-Hold Pilot 001

Mega Goal 321 uses this file as a docs-only pilot note for a bounded
run-until-hold flow. The pilot exists to describe the intended control-plane
contract before any runtime, deployment, or infrastructure change is allowed.

## Authorized Pilot

- Task: `run-until-hold-pilot-docs-001`
- Worker: `jerry-win-local-01`
- Mode: docs-only validation
- Expected result: stop at hold with a concise operator summary

## Bounds

The pilot may update this note only. It must not edit code, scripts, secrets,
deployment files, GitHub settings, server-root configuration, Docker daemon
configuration, OpenResty, Authelia, 1Panel, DNS, or other infrastructure.

No command output, credentials, tokens, cookies, raw transcripts, raw prompts,
worker logs, CI logs, GitHub logs, or raw diffs should be exported. The pilot
summary should report coarse facts such as task id, worker id, hold reason,
changed file count, check status, and `token_printed=false`.

## Hold Conditions

The run must hold immediately after the docs-only note is updated and reviewed
locally. It must also hold on any scope mismatch, missing authorization, dirty
state that affects this file, failed local validation, or any request to perform
deployment, infrastructure, secret, or GitHub settings work.

## Completion Evidence

A completed pilot should leave only this file changed, with a final report that
includes:

- `task_id=run-until-hold-pilot-docs-001`
- `worker_id=jerry-win-local-01`
- `scope=docs_only`
- `hold_state=human_review`
- `token_printed=false`
