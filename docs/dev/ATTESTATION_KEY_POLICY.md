# Attestation Key Policy

No production signing key is used in the preview.

Rules:

- Do not commit private keys.
- Do not generate private keys into tracked files.
- Mark fixture signatures explicitly with `fixture_signature=true`.
- Use `signing_key_present=false` for hash-only preview attestations.
- Keep attestation reports to safe metadata and hashes.
- Do not persist secrets, env dumps, CI logs or raw release logs.
- Keep token_printed=false.

Future signing key introduction requires a separate explicit goal and operator review.
