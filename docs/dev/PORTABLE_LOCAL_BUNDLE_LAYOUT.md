# Portable Local Bundle Layout

The portable local bundle is a repo-local model for using a clean checkout without installing services or mutating host settings.

Included components:

- repo-local launcher: `skybridge.ps1`, `skybridge.cmd`
- launcher, session, doctor, diagnostics and smoke-matrix PowerShell scripts
- safe demo fixtures under `fixtures/demo`
- read-only Web/Desktop preview surfaces
- docs and runbooks under `docs/dev`
- safe metadata directories under `.agent/tmp`

Excluded content:

- `node_modules`, `target`, build caches and generated dependency folders
- raw logs, prompts, transcripts, stdout/stderr captures and env dumps
- secrets, tokens, Authorization headers, cookies, private keys and raw pairing codes

The bundle does not install, upload, enable execution or mutate registry/startup/scheduled-task/service/powercfg settings. `token_printed=false`
