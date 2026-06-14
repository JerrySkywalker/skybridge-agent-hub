# Server-approved Workunit Human Review And Finalizer

Goal 225 separates workunit execution from finalizer completion.

- `finalizer-preview` reports `held_waiting_human_review_server_approved_run_225` while the task PR is open.
- `finalizer-apply` refuses to run unless the task PR is already merged.
- The finalizer verifies one execution, one workunit, one task, one task PR, approval consumed, no auto-merge, and no raw artifacts.
- Goal 225 must not run finalizer apply after creating the task PR.
- A later goal may run the finalizer only after human review merges the task PR.
- `token_printed=false`.
