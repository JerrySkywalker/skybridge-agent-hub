# Controlled Release Install And Launch

Current supported mode is manual local development launch.

Install and validate:

```powershell
corepack enable
corepack pnpm install
corepack pnpm check
```

Desktop preview:

```powershell
corepack pnpm -C apps/desktop build
corepack pnpm -C apps/desktop dev
```

Web control plane:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
corepack pnpm --filter @skybridge-agent-hub/web dev
```

Installer packaging is deferred and is not a release blocker for the controlled release because execution is still disabled by default.
