# Hermes Tunnel Recovery

SkyBridge reaches the cloud Hermes API through a local loopback SSH tunnel. The tunnel keeps Hermes private and avoids exposing the cloud API port publicly.

## Check Status

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-hermes-tunnel.ps1 -CheckOnly
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-tunnel.ps1 -CheckOnly
```

The helper checks whether `127.0.0.1:18642` is listening and reports matching tunnel processes without printing `HERMES_API_KEY`.

## Start Or Restart

Start the tunnel:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-hermes-tunnel.ps1 -Start
```

Restart after laptop sleep, network change or stale SSH state:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-hermes-tunnel.ps1 -Restart
```

The command shape is:

```powershell
ssh -N -L 18642:127.0.0.1:8642 -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 <PRIVATE_DEPLOY_HOST>
```

The script does not start a duplicate tunnel when the local port is already listening.

## Sleep Or Resume Breakage

If health checks fail after sleep or a network transition:

1. Run the check-only smoke.
2. Restart the tunnel with `start-hermes-tunnel.ps1 -Restart`.
3. Verify SSH access with `ssh <PRIVATE_DEPLOY_HOST>` if restart fails.
4. Re-run the Hermes health smoke.

Keep the tunnel bound to loopback. Do not publish the Hermes API port on the server firewall, OpenResty, Authelia or 1Panel.
