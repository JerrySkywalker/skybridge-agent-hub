# Managed Mode Codex Invocation Diagnostics

Goal 208G adds safe, non-mutating diagnostics for the Managed Mode Pilot 208 Codex invocation path.

## Invocation profiles

- `profile_ephemeral_cd`: `codex exec --ephemeral --cd <repo> -`. This was the previous managed-mode pilot profile.
- `profile_workspace_write_workdir`: `codex exec --sandbox workspace-write -` with the process working directory set to the repository root. Managed-mode pilot execution now selects this profile because it matches the previously successful bootstrap executor.
- `profile_readonly_smoke`: read-only help/version diagnostics only. Output is counted and discarded.
- `profile_disabled_unknown`: fail-closed profile for unknown invocation shapes.

## Safety rules

Diagnostics do not persist raw help output, version output, stdout, stderr, prompts, transcripts, environment variables or worker logs. Results report only bounded metadata such as launcher kind, host executable name, profile id, exit codes and discarded character counts.

The previous retry is classified as `invocation_failed_no_mutation` only when the retry result is present, no PR or changed files exist, no executor or finalizer evidence exists, no raw artifacts are present and `token_printed=false`.

Replacement retry remains separate from normal timeout retry. It is allowed only after the repaired workspace-write profile is selected and readiness confirms the previous retry failed without mutation.
