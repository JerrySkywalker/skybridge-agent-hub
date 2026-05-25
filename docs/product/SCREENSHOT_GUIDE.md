# Screenshot Guide

Browser visual QA is optional and fixture-only.

## Safe Command

```powershell
corepack pnpm --filter @skybridge-agent-hub/web build
corepack pnpm smoke:browser-visual-qa
```

If Playwright is unavailable, the script skips safely and writes `.agent/tmp/browser-visual-qa/manifest.json`.

## Expected Screens

- overview: `/#/overview`
- PR/CI: `/#/pr-ci`
- Hermes: `/#/hermes`
- notifications: `/#/notifications`
- compact embed: `/#/embed/compact`

Screenshots are local artifacts and should not include secrets, `.env` files, raw prompts, command output or production endpoints.

## Review Checklist

- The overview shows health, PR/CI, auto-merge, Hermes, notifications and recent failures.
- PR/CI shows required checks, eligibility and risk reasons.
- Hermes shows private tunnel/API status and `public_exposure=false`.
- Notifications show provider status and bootstrap fallback.
- Compact embed shows status, PR/CI, Hermes and last notification.

