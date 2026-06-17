# Cloud Deploy Rollback

Rollback is automatic inside `deploy-skybridge-server.sh` when:

- `docker compose up -d skybridge-server` fails;
- health wait fails;
- route parity fails.

The script captures the previous running container image for `skybridge-server`, restores that image through the same service-only compose command and waits for `/v1/health`.

Rollback status values in the sanitized report:

- `not_used`
- `succeeded`
- `failed`

If rollback fails, stop and investigate on the server. Do not mutate Hermes, OpenResty, Authelia, DNS, TLS, firewall, host packages or production secrets from this workflow.
