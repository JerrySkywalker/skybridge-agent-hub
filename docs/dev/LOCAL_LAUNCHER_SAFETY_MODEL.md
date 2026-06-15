# Local Launcher Safety Model

The launcher rejects:

- unknown commands;
- shell metacharacter command strings;
- execution-related command names;
- queue apply names;
- token-like content;
- environment dump content;
- secret-bearing path hints.

All routes set `execution_enabled=false`, `queue_apply_enabled=false`, `remote_execution_enabled=false` and `arbitrary_command_enabled=false`. The router does not accept arbitrary shell commands. token_printed=false
