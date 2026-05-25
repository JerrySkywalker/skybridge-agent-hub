# ntfy Provider

Status: `stable`

Role: `NotificationProvider`

ntfy is the first notification provider and the direct bootstrap phone-notification path used during SkyBridge development. It is optional: when credentials are missing, SkyBridge records skipped placeholder notification attempts.

Core boundary:

- Core owns notification jobs and routing decisions.
- ntfy-specific topic URLs, tokens and delivery calls stay in provider code and config examples.
- Alternative providers should implement the same notification-provider boundary.

Related docs:

- [../../notifications/PROVIDERS.md](../../notifications/PROVIDERS.md)
- [../../notifications/BOOTSTRAP_NOTIFICATIONS.md](../../notifications/BOOTSTRAP_NOTIFICATIONS.md)
