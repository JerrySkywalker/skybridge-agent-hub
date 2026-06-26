# Bootstrap Alpha Tag Plan

This plan records the MG341 operator authorization to create the real Bootstrap
Alpha RC git tag. It must not create a GitHub Release, release assets, worker
task, Codex run, MATLAB run, worker loop, project-control unpause, or deployment
infrastructure change.

Tag name: `v0.1.0-bootstrap-alpha-rc1`

Operator-authorized starting target commit:
`1f78d8def2862a145b54f207a3ab926115a0d002`

Operator-authorized starting image ref:
`ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-1f78d8def2862a145b54f207a3ab926115a0d002`

MG340 packaged Bootstrap Alpha baseline commit:
`8499ccba39894fdfccb7b29ddfe72db142ddb711`

MG340 packaged Bootstrap Alpha baseline image ref:
`ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-8499ccba39894fdfccb7b29ddfe72db142ddb711`

MG340 RC gate status: `pass`

MG340 release candidate ready: `true`

Tag creation authorization: `granted in MG341`

GitHub Release after MG341 tag creation: `not created`

MG343 later created the GitHub Release for
`v0.1.0-bootstrap-alpha-rc1` as a pre-release with no assets. The RC1 tag was
not moved, deleted, or recreated.

Because this documentation update is created before tag creation, the final tag
target must be retargeted to the final merged MG341 documentation commit only
after PR CI, Deploy Cloud, `/v1/version`, cloud parity, and RC gate audit pass.
The exact final tag target commit and image ref are recorded in the post-tag
audit report under `.agent/tmp/bootstrap-alpha-rc/`.

MG340 tag preview left `tag_created=false` before operator authorization.

MG341 tag result: `tag_created=true` after the annotated tag was created
locally, pushed to origin, verified on origin, and confirmed to point at
`4473257548bd0fc26e05002d968f8525b37bac8b`.

Post-tag audit result: passed with the expected
`tag_already_exists_on_target_commit` warning after tag creation. The handoff
summary is in [BOOTSTRAP_ALPHA_RC1_HANDOFF.md](BOOTSTRAP_ALPHA_RC1_HANDOFF.md).

## Required Checks Before Tag

- `main` is clean and aligned with `origin/main`.
- The final tag target is `HEAD` after any MG341 documentation PR merges.
- PR CI is green if a documentation PR is used:
  - Project check
  - Docker build server
  - Docker build web
- Deploy Cloud passes through the existing workflow.
- `/v1/version` matches the final tag target commit and image ref.
- Cloud route parity is ok.
- Operator report is ok.
- Review gate is ok.
- Self-bootstrap convergence is ok.
- Live evidence confirms:
  - `live-safe-template-task-332-001` completed.
  - `live-matlab-golden-task-336-001` completed with two expected combinations.
  - `live-codex-analysis-report-task-339-001` completed with
    `final_report_source=codex_native` and `fallback_report_used=false`.
- RC gate returns `status=pass`, `release_candidate_ready=true`, and
  `tag_created=false` before the tag is created.

## Exact Command Preview

The final command uses the final verified MG341 target commit:

```powershell
git tag -a v0.1.0-bootstrap-alpha-rc1 <final-mg341-target-commit> -m "Bootstrap Alpha RC1"
git push origin v0.1.0-bootstrap-alpha-rc1
```

## Tag Message Summary

The annotated tag message should summarize:

- cloud task to local worker to safe task evidence;
- MATLAB fixed runner golden success;
- Codex native analysis report success;
- Bootstrap Alpha RC gate pass;
- disabled features documented;
- tag created after MG340 RC gate approval and MG341 operator authorization;
- safety: no arbitrary shell, no worker loop, no unbounded run, no
  project-control unpause, no PR auto-creation, no raw logs/prompts/tokens in
  evidence.

## Rollback Notes

If the tag is created on the wrong commit, stop and ask the operator before
deleting or moving it. Do not delete task evidence or requeue old tasks.

If post-tag audit fails after the tag is pushed, keep the tag immutable until an
operator explicitly authorizes a follow-up correction plan.

## Authorization Boundary

- Real tag creation is authorized only for
  `v0.1.0-bootstrap-alpha-rc1`.
- GitHub Release creation is not authorized.
- Release asset creation is not authorized.
- Task creation, claim, and execution are not authorized.
- Codex and MATLAB execution are not authorized.
- Worker loop start is not authorized.
- Project-control unpause is not authorized.
- Deployment infrastructure changes are not authorized.
- Raw prompts, raw logs, stdout, stderr, credentials, cookies, tokens, provider
  auth headers, proxy profiles, and process-environment snapshots must not be
  included in reports.
- `token_printed=false`
