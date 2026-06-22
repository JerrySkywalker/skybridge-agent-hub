# Run-Until-Hold Pilot 002

Mega Goal 321 uses this file as a docs-only pilot note for a bounded
run-until-hold flow. The pilot validates that a selected local worker can make
one narrow documentation update, then stop for human review without continuing
into runtime, deployment, or infrastructure work.

## Authorized Pilot

- Task: `run-until-hold-pilot-docs-002`
- Worker: `jerry-win-local-01`
- Mode: docs-only validation
- Expected result: hold after the note is updated and locally reviewed

## Bounds

The pilot may update this note only. It must not edit code, scripts, secrets,
deployment files, GitHub settings, server-root configuration, Docker daemon
configuration, OpenResty, Authelia, 1Panel, DNS, or other infrastructure.

The pilot summary should export only coarse facts such as task id, worker id,
changed file count, validation status, hold reason, and `token_printed=false`.
It must not include credentials, tokens, cookies, raw prompts, raw transcripts,
command output, worker logs, CI logs, GitHub logs, or raw diffs.

## Hold Conditions

The run must hold after this docs-only note is changed and reviewed locally. It
must also hold on any scope mismatch, missing authorization, failed local
validation, dirty state that affects this file, or any request to perform
deployment, infrastructure, secret, runtime, or GitHub settings work.

## Completion Evidence

A completed pilot should leave only this file changed, with a final report that
includes:

- `task_id=run-until-hold-pilot-docs-002`
- `worker_id=jerry-win-local-01`
- `scope=docs_only`
- `hold_state=human_review`
- `token_printed=false`
