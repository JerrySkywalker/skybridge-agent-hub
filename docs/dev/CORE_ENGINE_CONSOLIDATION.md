# Core Engine Consolidation

Goal 214 consolidates managed-mode and BOINC-like preview helper logic behind shared PowerShell modules in `scripts/powershell/lib/`.

The consolidation is infrastructure-only. Existing script names remain compatibility wrappers and no worker execution, task claim, workunit creation, queue apply, or task PR creation is authorized by this goal.

## Modules

- `Skybridge.Core`: repo root/path helpers, safe JSON read/write, deterministic timestamps for fixtures, and `token_printed=false` helpers.
- `Skybridge.CodexExecutor`: fixture-safe Codex launcher classification and invocation plan metadata. It models stdin prompt support and output discard. It does not invoke Codex in tests.
- `Skybridge.ResourceGate`: fixture and local-safe run allowance summaries without `powercfg`, registry, or admin mutation.
- `Skybridge.WorkunitRegistry`: completed run registry reads, open-run summary, next-run metadata, and two-workunit dependency graph helpers.
- `Skybridge.EvidenceStore`: `.agent/tmp/**` evidence path enforcement, SHA-256 hashes, finalizer evidence lookup, and raw-artifact safety checks.
- `Skybridge.PrPackager`: changed-file discovery, README/docs allowlist enforcement, safe branch names, and safe PR body rendering.
- `Skybridge.Finalizer`: preview-only finalizer invariants, merged-PR fixture status, and duplicate finalizer prevention metadata.
- `Skybridge.QueuePolicy`: one-at-a-time, two-workunit preview, drain/pause, apply-disabled, and `no_next_execution_authorized` policy structures.
- `Skybridge.SafetyScanner`: token-looking text, raw artifact, secret JSON, environment dump, and unsafe command detection.
- `Skybridge.SmokeHarness`: smoke invocation, `token_printed=false`, no-mutation, and stable pass/fail helpers.

## Compatibility

The migrated scripts keep their existing command names and JSON fields. Importing shared modules happens at startup and fails closed if a module is unavailable. Wrapper smokes validate old command names through read-only/status paths only.

## No-Execution Boundary

Goal 214 does not run Codex as a worker, create workunits/tasks/claims, create task PRs, run `start-all`, run start-queue apply, run bounded queue apply, or resume apply. Future goals must explicitly authorize any apply path and must keep the shared safety checks intact.

## Future Use

New managed-mode or BOINC-like scripts should import the relevant `Skybridge.*` modules and keep raw prompts, transcripts, stdout, stderr, worker logs, CI logs, and secrets out of persisted evidence. Store only counts, hashes, paths under `.agent/tmp/**`, and safe summaries with `token_printed=false`.
