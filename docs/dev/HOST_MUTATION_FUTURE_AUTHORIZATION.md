# Host Mutation Future Authorization

Real host mutation is reserved for a future explicit goal.

A future goal must define:

- exact host paths and system surfaces
- operator consent UX
- rollback and backup plan
- validation and smoke plan
- secret handling and log redaction
- failure and audit gates
- human-review gates

Until then, the consent gate reports `host_mutation_allowed=false` and `future_explicit_goal_required=true`.

Current local auth, installer and consent previews must not mutate registry, startup folders, scheduled tasks, services, power settings, PATH, Program Files, Desktop, Start Menu, AppData or other system/user startup locations.
