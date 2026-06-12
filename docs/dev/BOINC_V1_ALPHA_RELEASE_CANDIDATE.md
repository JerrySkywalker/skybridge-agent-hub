# BOINC v1 Alpha Release Candidate

- alpha id: boinc-v1-alpha-215
- Workunit A: PR #157, merge commit 274f05d4fd2b96b8962089dfc083d39bde0a75c8
- Workunit B: PR #159, merge commit 0822e76067590491299d36d8e20c2b1234377e80
- Workunit A finalizer evidence hash: d71f83a89d43fcc87c119860614fe08931089b44743ed87fed15643f5fcf9f57
- Workunit B finalizer evidence hash: b7ec5343612f8c8eb64905bbafba7663001c78d4d8f1b5a3c9029758539b8ae9
- resource gate: can_run_one_at_a_time=True
- drain/pause: drain_after_current=true; pause_after_current=true; pause_new_claims=true
- failure budget: policy_gap_remaining_for_v1
- evidence retention: safe summary artifacts retained under .agent/tmp/boinc-v1-alpha-215
- audit: release candidate safe artifacts only
- apply boundary: general bounded queue apply disabled; no_next_execution_authorized=true
- remaining gaps to v1: desktop resident enforcement; server control plane; failure budget policy; audit retention; operator approval flow; packaging/installer
- token_printed=false
