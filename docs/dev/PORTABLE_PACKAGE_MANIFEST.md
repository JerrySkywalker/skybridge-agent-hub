# Portable Package Manifest

The manifest schema is `skybridge.portable_package_manifest.v1`.

It records package id, version, source commit, sanitized package/stage paths, included entrypoints/docs/scripts/fixtures, excluded paths and artifact hash when a zip exists.

All capability flags remain false:

- `install_allowed=false`
- `upload_allowed=false`
- `github_release_allowed=false`
- `host_mutation_allowed=false`
- `execution_enabled=false`
- `queue_apply_enabled=false`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `token_printed=false`
