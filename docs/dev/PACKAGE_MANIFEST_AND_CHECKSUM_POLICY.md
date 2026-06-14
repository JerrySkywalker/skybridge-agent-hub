# Package Manifest and Checksum Policy

The package manifest is preview metadata for local release-candidate planning.

Schemas:
- `skybridge.desktop_artifact_candidate.v1`
- `skybridge.desktop_artifact_manifest.v1`
- `skybridge.desktop_artifact_verification.v1`
- `skybridge.desktop_artifact_checksum_preview.v1`

Checksums are SHA-256 previews over repo-local artifacts that already exist from normal build commands. They are not upload credentials, signatures, installer receipts, or release records.

The policy forbids artifact upload, installation, signing, GitHub release creation, and writes outside the repository.
