# v2.1 Authenticated Live-local RC

Version: `v2.1.0-authenticated-live-local-rc`

This release candidate adds a bounded authenticated live-local loopback rehearsal on top of the v2.0 local auth control-plane RC.

## Included

- Loopback-only fixture server.
- Authenticated safe metadata request rehearsal using hash-only fixture session state.
- Route hardening for status, readiness, and metadata routes.
- Remote origin rejection.
- Command-shaped payload rejection.
- Web/Desktop read-only live-local panels.
- E2E preview smoke pack.
- v2.1 RC report.

## Excluded

- Production identity.
- Worker execution.
- Workunit apply.
- Task claim.
- Queue apply.
- Remote execution.
- Arbitrary command dispatch.
- Host mutation.
- Manual GitHub Release creation.
- Manual artifact upload.

## Evidence

- `.agent/tmp/live-local/live-local-server-report.json`
- `.agent/tmp/live-local/live-local-e2e-report.json`
- `.agent/tmp/live-local/v2.1-live-local-rc-report.json`
