# Server-approved Workunit 225

Goal 225 introduces the first narrow server-approved one-workunit path.

- Run id: `server-approved-run-225`.
- Workunit id: `server-approved-run-225-workunit-001`.
- Task id: `server-approved-run-225-task-001`.
- Target path is fixed to `docs/server-approved-workunit-225.md`.
- Allowed paths stay limited to `README.md` and `docs/**`.
- Durable pairing, durable approval, resident polling, release, resource, failure budget, evidence retention, audit/redaction, and safe export must all pass before execution.
- Remote execution, arbitrary command dispatch, trusted-docs auto-merge, and generic queue apply remain disabled.
- Approval is consumed by the local gate when execution starts; approval does not execute work by itself.
- The run stops after creating one task PR and holds for human review.
- `token_printed=false`.
