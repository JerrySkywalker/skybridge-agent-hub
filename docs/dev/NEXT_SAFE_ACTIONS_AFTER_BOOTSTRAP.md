# Next Safe Actions After Bootstrap

Safe next actions:

- inspect product readiness
- run preview-only local runtime plans
- review packaging candidate metadata
- review update and rollback previews
- review backup/restore policy
- run smokes and CI

Unsafe without a future explicit goal:

- execute Codex as a worker
- create or claim tasks
- create workunits or task PRs
- start unbounded loops
- install services or autostart entries
- perform network updates or artifact uploads

token_printed=false
