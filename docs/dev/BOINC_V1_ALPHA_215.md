# BOINC v1 Alpha 215

BOINC v1 Alpha 215 is a controlled two-workunit alpha for SkyBridge Agent Hub. It is not full BOINC-like v1 and does not enable generic bounded queue apply.

## Scope

- Workunit A may run once under explicit Goal 215 authorization.
- Workunit B remains `blocked_by_unfinalized_workunit_a`.
- Repo-mutating work remains serialized.
- Human review is required before the alpha can continue.
- `token_printed=false` is required in JSON, smoke, report, and UI fixture outputs.

## Workunit A

Workunit A targets `docs/boinc-v1-alpha-workunit-a.md` and uses task type `docs/local-smoke` with low risk. It may create exactly one task PR and then must stop in `held_waiting_human_pr_review_workunit_a`.

## Workunit B

Workunit B targets `docs/boinc-v1-alpha-workunit-b.md`. It must not execute in Goal 215. It can only be considered by Goal 216 after Workunit A has been human-reviewed, merged, and finalized.

## Apply Boundary

General bounded queue apply, multi-workunit apply, `start-all`, `start-queue`, and `resume -Apply` remain disabled. The only apply path is `alpha-workunit-a-apply` in `scripts/powershell/skybridge-boinc-v1-alpha.ps1`, and it requires explicit Goal 215 authorization.
