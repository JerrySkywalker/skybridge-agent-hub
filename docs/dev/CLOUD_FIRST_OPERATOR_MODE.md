# Cloud-first Operator Mode

SkyBridge Web and Desktop support `cloud_operator` mode for operators who connect to a cloud SkyBridge server instead of a local development server.

The selected API base is the only endpoint used by the frontend for REST and server-mediated Hermes provider status. Cloud mode does not auto-start a local backend and does not tell the operator to run the local server command when health fails.

Failure guidance in this mode is:

```text
Cloud API unreachable. Check API base and network access.
```

Safety boundaries:

- no secrets are stored in mode settings;
- no token, auth header, cookie, private key or raw response is persisted;
- no host, registry, service, scheduled-task or power settings are mutated;
- `token_printed=false`.

