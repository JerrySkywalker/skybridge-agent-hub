# Signed Manifest And Attestation Preview

The attestation preview emits safe local metadata for future release signing work.

Current schemas:

- `skybridge.signed_manifest_preview.v1`
- `skybridge.attestation_preview.v1`
- `skybridge.attestation_verification_preview.v1`

This goal uses hash-only fixture signing metadata:

- preview only: `true`
- fixture signature: `true`
- production signing key present: `false`
- private key committed: `false`
- private key generated into tracked files: `false`
- token_printed=false

Reports are written under `.agent/tmp/attestation/`.
