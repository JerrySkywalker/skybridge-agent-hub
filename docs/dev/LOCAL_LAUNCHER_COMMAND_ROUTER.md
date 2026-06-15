# Local Launcher Command Router

The command router is a fixed allowlist over safe local tools:

- local session status, start preview, bounded start local, stop and restart;
- local doctor check and explain;
- diagnostics health and product readiness;
- smoke matrix fast and bootstrap-complete groups;
- product profile status;
- demo status.

Forbidden targets include arbitrary shell text, Codex worker, workunit apply, task claim, queue apply, start-all, start-queue, resume, registry, Startup, service, scheduled-task and powercfg changes.

Reports are written under `.agent/tmp/local-launcher/`. token_printed=false
