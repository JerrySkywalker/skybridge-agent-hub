# Bootstrap Alpha Tag Plan

This is a preview-only tag plan. MG340 must not create a real git tag or a
GitHub release.

Proposed tag: `v0.1.0-bootstrap-alpha-rc1`

Target commit: `8499ccba39894fdfccb7b29ddfe72db142ddb711`

Image ref:
`ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-8499ccba39894fdfccb7b29ddfe72db142ddb711`

## Required Checks Before Tag

- PR CI green for the RC gate branch.
- Deploy Cloud verification completed through the existing workflow if a merged
  commit is deployed.
- `/v1/version` matches the expected commit and image for the RC baseline being
  tagged.
- Cloud route parity is ok.
- Operator report is ok.
- Review gate is ok.
- Self-bootstrap convergence is ok or has only documented non-execution
  warnings.
- Live evidence confirms:
  - `live-safe-template-task-332-001` completed.
  - `live-matlab-golden-task-336-001` completed with two expected combinations.
  - `live-codex-analysis-report-task-339-001` completed with
    `final_report_source=codex_native` and `fallback_report_used=false`.
- RC gate returns `status=pass`, `release_candidate_ready=true`, and
  `tag_created=false`.

## Exact Command Preview

Do not run this command during MG340:

```powershell
git tag -a v0.1.0-bootstrap-alpha-rc1 8499ccba39894fdfccb7b29ddfe72db142ddb711 -m "Bootstrap Alpha RC"
git push origin v0.1.0-bootstrap-alpha-rc1
```

## Rollback Notes

The tag should point to the proven Bootstrap Alpha RC baseline. If the operator
rejects the RC after preview, do not delete task evidence or requeue old tasks.
Prepare a follow-up fix goal and a new tag plan.

If a tag is created on the wrong commit in a future authorized goal, stop and
ask the operator before deleting or moving it.

## Authorization Boundary

- `tag_created=false` for MG340.
- Real tag creation requires explicit operator authorization after MG340.
- No GitHub release is created by this goal.
