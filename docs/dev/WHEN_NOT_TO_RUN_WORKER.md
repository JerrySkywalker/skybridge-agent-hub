# When Not To Run Worker

Do not run a worker when any of these is true:

- the goal is release, docs, audit or report consolidation only
- `active_tasks` is not zero
- `stale_leases` is not zero
- `runner_lock` is not `none`
- an open task PR exists
- remote execution would be required
- arbitrary command dispatch would be required
- generic bounded queue apply would be required
- human review or finalizer evidence is missing
- evidence retention, audit/redaction, safe export or failure budget is not passing

Bootstrap-complete release work must not execute new workunits, create tasks, create claims or create task PRs.

`token_printed=false`

