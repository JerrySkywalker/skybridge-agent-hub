# Managed Mode Codex Invocation Diagnostics

Goal 208G adds safe, non-mutating diagnostics for the Managed Mode Pilot 208 Codex invocation path. Goal 209C extends the same launcher/profile contract to repeatable managed-mode runs.

## Invocation profiles

- `profile_ephemeral_cd`: `codex exec --ephemeral --cd <repo> -`. This was the previous managed-mode pilot profile.
- `profile_workspace_write_workdir`: `codex exec --sandbox workspace-write -` with the process working directory set to the repository root. Managed-mode pilot execution and repeatable managed-mode run execution select this profile because it matches the previously successful bootstrap executor.
- `profile_readonly_smoke`: read-only help/version diagnostics only. Output is counted and discarded.
- `profile_disabled_unknown`: fail-closed profile for unknown invocation shapes.

## Safety rules

Diagnostics do not persist raw help output, version output, stdout, stderr, prompts, transcripts, environment variables or worker logs. Results report only bounded metadata such as launcher kind, host executable name, profile id, exit codes and discarded character counts.

The previous retry is classified as `invocation_failed_no_mutation` only when the retry result is present, no PR or changed files exist, no executor or finalizer evidence exists, no raw artifacts are present and `token_printed=false`.

Replacement retry remains separate from normal timeout retry. It is allowed only after the repaired workspace-write profile is selected and readiness confirms the previous retry failed without mutation.

## Repeatable run diagnostics

Repeatable managed-mode runs expose the same safe metadata through:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-invocation-diagnostics -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-invocation-profile -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-failure-state -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-replacement-readiness -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-replacement-preview -Json
```

For `managed-mode-run-209`, `run-failure-state` may classify the first failed 209B attempt as `invocation_failed_no_mutation` or `run_failed_no_mutation` only when the safe result exists, Codex execution started once, no PR or changed files were produced, no finalizer evidence exists, no raw artifacts are present and `token_printed=false`.

The repeatable runner hosts `codex.ps1` through `pwsh` or `powershell.exe`, hosts `codex.cmd` and `codex.bat` through `cmd.exe /d /s /c`, and directly invokes `codex.exe` or extensionless commands. Diagnostics never persist the raw command line, prompt, transcript, stdout, stderr, environment variables or worker logs.

Finalizer foundation commands are preview-first:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-finalizer-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-finalizer-apply -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-finalizer-evidence -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command run-finalizer-report -Json
```

`run-finalizer-apply` refuses unless the task PR is already merged, exactly one workunit/task/claim/Codex execution/PR exists, the changed file is present on `main`, no raw artifacts exist and local task/lease/lock gates are clear.
