# Installer Host Mutation Boundary

The sandboxed installer candidate is confined to `.agent/tmp/installer-candidate/`.

It must not write to:

- Program Files
- AppData
- Start Menu
- Desktop
- PATH
- registry
- Startup folders
- scheduled tasks
- services
- powercfg or sleep settings

Install, uninstall, upgrade, rollback, recovery, and demo commands are previews or sandbox-only rehearsals. Any future host installer requires a separate explicit goal.

`token_printed=false`
