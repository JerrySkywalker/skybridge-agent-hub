# Metrics And Audit

SkyBridge exposes lightweight operational metrics at `GET /v1/metrics`.

## Current Metrics

- total events;
- runs by status;
- runs by source;
- notifications by status;
- notifications by severity;
- node status counts;
- recent failed runs.

## Audit Trail Direction

Future audit records should include:

- who or what triggered an action;
- source adapter and node;
- run/session correlation;
- safety decision and approval state;
- redaction policy version;
- timestamp and immutable event id.

Remote execution remains disabled until audit, approval and authentication boundaries are complete.
