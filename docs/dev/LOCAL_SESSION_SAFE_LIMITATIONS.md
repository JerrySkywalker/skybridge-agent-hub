# Local Session Safe Limitations

This RC is not a worker launcher and not a remote execution surface.

Forbidden and disabled:

- Codex worker execution;
- workunit apply;
- task creation;
- task claim;
- task PR creation;
- generic queue apply;
- remote command execution;
- arbitrary command dispatch;
- Windows service, scheduled task, Startup folder, registry or powercfg mutation;
- raw prompt, transcript, stdout, stderr, worker log or CI log persistence.

The Web and Desktop panels show preview/status only. Start and stop buttons are disabled placeholders. token_printed=false
