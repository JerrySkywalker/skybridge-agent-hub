# API Examples

## Curl

```bash
curl http://127.0.0.1:8787/v1/health
curl http://127.0.0.1:8787/v1/sources
curl http://127.0.0.1:8787/v1/metrics
curl http://127.0.0.1:8787/v1/approvals
```

## PowerShell

```powershell
Invoke-RestMethod http://127.0.0.1:8787/v1/health
Invoke-RestMethod http://127.0.0.1:8787/v1/sources
Invoke-RestMethod http://127.0.0.1:8787/v1/metrics
Invoke-RestMethod http://127.0.0.1:8787/v1/notifications/providers
```

## Embed HTML

```html
<script type="module" src="./skybridge-status-card.js"></script>
<skybridge-status-card api-base="http://127.0.0.1:8787"></skybridge-status-card>
```

## Local Demo Workflow

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
corepack pnpm --filter @skybridge-agent-hub/web dev
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\generate-demo-dataset.ps1
```

The generated demo events are safe fixtures. They do not include prompts, command output, patches, private paths or secrets.
