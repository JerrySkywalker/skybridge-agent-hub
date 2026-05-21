# Metrics And Audit

SkyBridge exposes lightweight operational metrics at `GET /v1/metrics` and a derived audit summary at `GET /v1/audit`.

## Current Metrics

- total events;
- runs by status;
- runs by source;
- notifications by status;
- notifications by severity;
- node status counts;
- recent failed runs.

## Audit Trail Foundation

The current audit endpoint derives records from already-redacted events. It includes:

- who or what triggered an action;
- source adapter and node;
- run/session correlation;
- safety decision and approval state;
- timestamp and immutable event id;
- `raw_payload_included: false` to make clear that prompts, patches, stdout and stderr are not returned.

The endpoint currently covers approval, node, notification and failed-run events. A durable append-only audit store remains a follow-up release task.

Remote execution remains disabled until audit, approval and authentication boundaries are complete.
