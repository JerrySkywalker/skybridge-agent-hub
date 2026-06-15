# Loopback Origin Policy

The loopback origin policy is schema `skybridge.loopback_origin_policy.v1`.

Allowed sources:

- `http://localhost:*` for local development
- `http://127.0.0.1:*` for local development
- `http://[::1]:*` for local development
- `repo-local-dev-fixture` for static smoke fixtures

Remote origins are rejected. A local auth request from a remote host is classified as `remote_origin_forbidden`.

The policy does not grant execution, queue apply, worker claim, installer, release upload, or host mutation privileges.
