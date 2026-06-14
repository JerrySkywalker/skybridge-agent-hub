# V1 To V1.1 Roadmap

V1.0 remains future-facing because the current tag is `v0.99.0-boinc-like-v1-controlled-release`: controlled release infrastructure is ready, but execution remains disabled by default.

Path to v1.1:

- Run Goal 221 controlled trial with explicit approval.
- Expand durable worker pairing after auth and audit design.
- Add local resident polling while keeping execution disabled until approved.
- Prove one-workunit server-approved execution with finalizer and human review.
- Add installer packaging.
- Reassess trusted-docs auto-merge only behind an explicit gate.

No goal in this roadmap may bypass resource gate, failure budget, evidence retention, audit/redaction, finalizer, or human review without a separately approved design.
