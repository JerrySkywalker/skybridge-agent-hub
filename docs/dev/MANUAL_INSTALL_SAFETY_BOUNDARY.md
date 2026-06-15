# Manual Install Safety Boundary

Manual install preview is not an installer.

Forbidden actions:

- real file copy outside `.agent/tmp`
- PATH mutation
- shortcut or Start Menu writes
- registry, startup, scheduled task, service or powercfg mutation
- network update or upload

`token_printed=false`
