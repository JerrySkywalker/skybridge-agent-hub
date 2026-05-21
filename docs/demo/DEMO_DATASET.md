# Demo Dataset

Generate a safe multi-agent fixture dataset:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\generate-demo-dataset.ps1
```

The dataset includes:

- Codex run and tool completion;
- OpenCode completed run;
- Hermes failed run;
- runner stale state;
- approval request;
- notification sent, skipped and failed samples;
- sidecar node heartbeat.

The generated JSON uses `skybridge.agent_event.v1` and intentionally omits prompts, patches, stdout, stderr, command output, private paths and secrets.
