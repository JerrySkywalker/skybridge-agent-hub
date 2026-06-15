# Local Auth Model

SkyBridge local auth is a v2.0 preview boundary for loopback-only control-plane reads. It is not production identity.

Current invariants:

- schema: `skybridge.local_auth_model.v1`
- allowed origins: `localhost`, `127.0.0.1`, `::1` and repo-local dev fixtures
- remote origins allowed: `false`
- raw token persistence: `false`
- token hash fixture state: `true`
- auth header persistence: `false`
- cookie persistence: `false`
- private key persistence: `false`
- execution enabled: `false`
- queue apply enabled: `false`
- remote execution enabled: `false`
- arbitrary command enabled: `false`
- token_printed=false

The auth gate only allows safe metadata preview reads. It must still require release, resource, failure, evidence, audit and human-review gates for any future operation that could mutate repository or host state.

Reports are written under `.agent/tmp/local-auth/`.
