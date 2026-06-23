# Client, Worker, Server Architecture

Bootstrap Alpha separates the operator surface, durable state, planning, and
local execution plane.

## Rust/Tauri Desktop Client

The Desktop client is the local operator application. It is responsible for:

- installer and repair flows for local components;
- worker service manager and status surface;
- Bootstrap Alpha worker service setup status using
  `skybridge.local_worker_service_status.v1`;
- natural-language chat UI using `skybridge.task_draft_preview.v1` for MG326
  deterministic local draft previews;
- preview and review UI for planner drafts;
- server report, worker health, and evidence review surfaces.

The client is not an arbitrary shell. It must not expose hidden command
execution controls. Desktop execution controls are future reviewed work, not
current hidden behavior.

## SkyBridge Server

The SkyBridge Server is the source of truth, queue, state store, evidence store,
and API surface. It owns:

- project, goal, campaign, task, worker, lease, and evidence records;
- task queue visibility and claim state;
- safe operator reports;
- API contracts consumed by Desktop, web views, and workers.

The server does not directly execute arbitrary commands. The server does not
directly remote-control the worker. It stores intended work and safe evidence,
then workers pull compatible tasks.

## Windows Worker

The Windows worker is the local execution plane. It is responsible for:

- registering worker identity and capabilities;
- polling the server for compatible template-bound tasks;
- claiming one task through a lease;
- running only approved template runners;
- returning safe evidence, PR, CI, smoke, and audit summaries.

Worker pulls tasks from Server. The worker must not run an unbounded loop or
daemon expansion unless a future reviewed goal explicitly enables that behavior.
MG325 adds Desktop and PowerShell visibility for install/repair readiness only;
task claim, Codex execution, MATLAB execution, and the worker loop remain
disabled.

## Hermes Or Planner

Hermes, or another planner adapter, transforms natural-language operator intent
into structured drafts. The planner may propose template selection, parameters,
validation, and evidence requirements.

The planner does not execute work. Planner output remains a draft until the
operator confirms it and the server creates the task or campaign.
MG326 keeps the planner local and deterministic, with no raw prompt persistence,
no server task or campaign creation, and no execution.

## Execution Tools

Codex, MATLAB, Git, gh, and similar tools are execution tools invoked only by
worker template runners. They are not server plugins, direct Desktop shell
controls, or planner-side execution surfaces.

All adapter output that reaches the server must normalize into
`skybridge.agent_event.v1` and preserve redaction boundaries.

token_printed=false
