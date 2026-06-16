# v2.1 Next Roadmap

The v2.1 RC remains a local rehearsal. Future goals should keep the same safety boundaries.

## Recommended Goals

- Graduate from fixture loopback server to real local server only after adding durable server lifecycle controls.
- Add browser-driven E2E tests against the real local server when it exists.
- Keep worker execution behind separate resource, failure, evidence, audit, and human-review gates.
- Keep host mutation behind a future explicit goal.
- Keep remote execution disabled.
- Keep arbitrary command dispatch disabled.
- Add production identity only after token storage, rotation, redaction, and logout semantics are explicitly designed.

## Non-goals

- No real installer/update flow.
- No host mutation.
- No queue worker loop.
- No generic apply route.
- No manual release object creation.
