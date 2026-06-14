# Artifact Manifest Preview

Manifest schemas:

- `skybridge.release_artifact_manifest.v1`
- `skybridge.release_artifact_candidate.v1`
- `skybridge.artifact_verification_report.v1`

Required fields:

- `artifact_id`
- `package_name`
- `version`
- `target_os`
- `target_arch`
- `build_command_preview`
- `expected_output_path_sanitized`
- `checksum_present=false` unless a safe artifact exists
- `upload_planned=false`
- `install_planned=false`
- `token_printed=false`

The preview does not upload artifacts, install binaries or create GitHub releases.
