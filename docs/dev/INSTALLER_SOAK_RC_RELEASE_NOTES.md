# Installer Soak RC Release Notes

Version: `v1.8.0-sandboxed-installer-soak-rc`

Highlights:

- Classified tag workflow side effects before release tagging.
- Added a sandboxed installer candidate under `.agent/tmp/installer-candidate/`.
- Added sandbox-installed runtime rehearsal for launcher, doctor, demo, and safe summary paths.
- Added bounded install, upgrade, rollback soak reports.
- Added crash/restart/recovery sandbox preview and cleanup hardening.
- Added operator acceptance v3 and read-only Web/Desktop installer acceptance surfaces.

Known limits:

- no host installer
- no network update
- no signed archive
- no manual GitHub Release creation
- existing workflows may publish images/artifacts after a tag

`token_printed=false`
