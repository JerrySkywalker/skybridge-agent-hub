# Auth Session Store

The local auth session store is fixture-only and hash-only. It lives under `.agent/tmp/local-auth/session-store/`, which is ignored by Git.

Allowed persisted fields:

- session id
- token hash
- created time
- expiry time
- state
- scope
- allowed local origin summary

Forbidden persisted fields:

- raw auth values
- auth header values
- bearer strings
- cookies
- private keys
- environment dumps
- prompts, transcripts, stdout, stderr, worker logs, CI logs or GitHub logs

Any payload with token-like content, command text, execution request fields or `token_printed=true` must be rejected.
