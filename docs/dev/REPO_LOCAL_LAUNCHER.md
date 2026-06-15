# Repo-local Launcher

Use the repo-local launcher from the repository root:

```powershell
.\skybridge.ps1
.\skybridge.ps1 status
.\skybridge.ps1 start-preview
.\skybridge.ps1 doctor
.\skybridge.ps1 demo
```

`skybridge.ps1` without arguments prints safe status/help only. `start-preview` is the safe default mode. `start-local` routes only to the existing bounded manual local session profile:

```powershell
.\skybridge.ps1 start-local
```

The launcher is not an installer. It does not mutate registry, Startup folders, scheduled tasks, services, power settings, production settings or GitHub settings. token_printed=false
