# SBOM Preview

The SBOM preview summarizes local package metadata without network access, package installation or upload.

Current schemas:

- `skybridge.sbom_preview.v1`
- `skybridge.dependency_inventory.v1`
- `skybridge.license_summary.v1`

Rules:

- network used: `false`
- package install performed: `false`
- upload performed: `false`
- env dump persisted: `false`
- token persistence: `false`
- token_printed=false

Reports are written under `.agent/tmp/sbom/`.
