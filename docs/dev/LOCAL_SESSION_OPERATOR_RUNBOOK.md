# Local Session Operator Runbook

Use `skybridge-local-session.ps1` for the manual local session.

1. Run `-Command doctor` or `skybridge-local-doctor.ps1 -Command check`.
2. Run `-Command start` to preview the start plan.
3. Run `-Command start -Apply -Profile full-local-preview -Bounded` only when you want the bounded non-worker session metadata.
4. Run `-Command status` to inspect component, port and lock state.
5. Run `-Command stop` to remove this session metadata.
6. Run `-Command cleanup` for stale lock/PID cleanup preview and recovery guidance.

Reports are written under `.agent/tmp/local-session/` and contain safe metadata only. The session does not persist stdout, stderr, worker logs, prompts, transcripts or environment dumps. token_printed=false
