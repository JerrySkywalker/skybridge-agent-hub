# Operator Daily Checklist

1. Confirm idle state:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-complete.ps1 -Command gate
```

2. Review product profile safety:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-product-profile.ps1 -Command report
```

3. Preview local launch surfaces:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-launch.ps1 -Command report
```

4. Refresh diagnostics:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-diagnostics.ps1 -Command report
```

5. Check packaging and Windows launcher previews:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-packaging-preview.ps1 -Command report
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command report
```

6. Confirm disabled capabilities:

- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `execution_enabled=false`
- `queue_apply_enabled=false`
- `no_next_execution_authorized=true`
- `token_printed=false`

Do not run worker execution, workunit creation, task creation, task claim, task PR creation, generic bounded queue apply, `start-all`, `start-queue` or `resume -Apply`.
