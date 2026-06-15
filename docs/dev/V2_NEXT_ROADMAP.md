# v2 Next Roadmap

The v2 RC is a preview control-plane security baseline, not a production identity or host mutation release.

## Next Recommended Goals

- Graduate a real authenticated local server only after preserving fixture-to-production migration gates.
- Keep real installer preview disabled until a future explicit installer goal.
- Keep real host mutation behind a future explicit authorization goal.
- Keep worker execution separately gated by resource, failure, evidence, audit, and human-review controls.
- Keep remote execution disabled.
- Keep arbitrary command dispatch disabled.
- Add stronger browser-origin integration tests for the real localhost server when it graduates.
- Add production signing key policy only when key storage, rotation, and CI access are explicitly designed.

## Non-goals For This RC

- No remote execution.
- No arbitrary command dispatch.
- No real host mutation.
- No real install/update flow.
- No manual GitHub Release creation.
- No manual artifact upload.
