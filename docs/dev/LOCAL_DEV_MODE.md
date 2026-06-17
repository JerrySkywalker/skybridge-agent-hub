# Local Dev Mode

SkyBridge Web and Desktop support `local_dev` mode for local development against:

```text
http://127.0.0.1:8787
```

The frontend never auto-starts the server. If REST health fails in `local_dev`, the Connectivity Doctor shows the explicit startup command:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
```

This guidance is only for local development mode. Cloud operator mode must not require a local server.

Stored frontend settings are limited to the API mode and API base. They must not include credentials, tokens, cookies, auth headers, raw requests or raw responses.

