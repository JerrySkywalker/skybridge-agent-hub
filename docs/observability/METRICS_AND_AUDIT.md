# Metrics And Audit

SkyBridge exposes lightweight operational metrics at `GET /v1/metrics` and a safe audit trail at `GET /v1/audit`.

## Current Metrics

- total events;
- runs by status;
- runs by source;
- notifications by status;
- notifications by severity;
- node status counts;
- recent failed runs.

## Audit Trail Foundation

The audit endpoint returns durable append-only records when SQLite persistence is enabled. If a store has no durable audit rows yet, the endpoint falls back to the older derived summary from already-redacted events for backward compatibility.

Audit records include:

- who or what triggered an action;
- source adapter and node;
- run/session correlation;
- safety decision and approval state;
- timestamp and immutable event reference;
- redaction policy version used at write time;
- `raw_payload_included: false` to make clear that prompts, patches, stdout and stderr are not returned.

The endpoint currently covers approval, node, notification and failed-run events. Query filters are available for `action`, `actor`, `run_id`, `from`, `to` and `limit`.

Durable audit records intentionally omit raw prompts, patches, stdout, stderr, command output, private paths and secrets. They are local operator metadata and are not uploaded to external services by default.

Remote execution remains disabled until audit, approval and authentication boundaries are complete.
