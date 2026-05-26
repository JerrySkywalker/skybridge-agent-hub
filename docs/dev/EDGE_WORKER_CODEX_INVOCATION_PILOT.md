# Edge Worker Codex Invocation Pilot

- Task ID: `super-142a-codex-invocation-pilot-20260526122339`
- Scope: docs-only hardened Codex invocation pilot.
- Result: the Edge Worker can invoke Codex without a configured `codex_command` by resolving `codex` from `PATH`.
- Prompt delivery: the worker passes the task prompt through Codex stdin instead of relying on shell argument text.
- Ownership boundary: Codex edits the task branch, while commit, push and draft PR creation remain worker-owned steps after validation.
- Safety result: raw Codex logs and command output stay local under `.agent/workers/`; SkyBridge receives only safe task summaries.

This pilot keeps the first hardened invocation proof narrow: no runtime code, tests, config, secrets, deployment files, GitHub settings or environment files were changed.
