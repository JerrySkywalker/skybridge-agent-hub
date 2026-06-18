# Cloud Deployment Parity

Cloud route parity checks the public API base, defaulting to:

```text
https://skybridge.example.com
```

Required routes:

- `GET /v1/health`
- `GET /v1/version`
- `GET /v1/summary`
- `GET /v1/manual-tasks/providers`
- `POST /v1/manual-tasks/run-next/mock`

The parity model returns:

- `ok` when all routes pass;
- `server_online_but_outdated` when health works but manual-task routes are unavailable;
- `failed` for broader route or connectivity failures.

Web and Desktop Connectivity Doctor surfaces show `server_version`, `commit_sha`, `image_tag`, `route_set_version`, `manual_task_routes_available` and `deployment_parity_status`.

If the cloud server is online but missing `/v1/manual-tasks/providers`, the user-facing warning is:

```text
Cloud server online but outdated; deploy server >= v2.4.
```
