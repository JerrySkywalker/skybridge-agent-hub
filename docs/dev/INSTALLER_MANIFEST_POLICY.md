# Installer Manifest Policy

The installer manifest schema is `skybridge.installer_manifest.v1`.

Required fields include:

- `candidate_version`
- `source_commit`
- `source_package`
- `staged_root_sanitized`
- `install_root_sanitized`
- `entrypoints`
- `docs_runbooks`
- `forbidden_paths_absent`
- `host_mutation_allowed=false`
- `registry_write_allowed=false`
- `startup_write_allowed=false`
- `scheduled_task_allowed=false`
- `service_install_allowed=false`
- `powercfg_allowed=false`
- `upload_allowed=false`
- `github_release_allowed=false`
- `token_printed=false`

Manifest paths must be sanitized repo-relative paths. Secret values, raw logs, transcripts, environment dumps, and local private paths are not allowed.
