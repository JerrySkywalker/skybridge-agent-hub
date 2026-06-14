# Local Release Artifact Policy

Local release artifact planning is allowed only as safe metadata.

Allowed:

- preview build commands
- sanitized expected output paths
- package names and versions
- target OS and architecture metadata
- local verification summaries

Forbidden by default:

- artifact upload
- GitHub release creation
- global package installation
- registry, Startup, service, scheduled task or power setting mutation
- secret persistence

token_printed=false
