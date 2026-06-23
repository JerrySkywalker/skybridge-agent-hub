# Bootstrap Alpha Scope

Bootstrap Alpha is the product-flow freeze for SkyBridge Agent Hub. It narrows
near-term development toward a usable cloud server, Desktop client, local
Windows worker service, chat-to-task planner, template registry, and reviewed
worker execution loop.

## Included

- cloud server install, deploy, and parity checks;
- local Desktop client install target;
- local worker service install target;
- local worker service status, doctor, install-preview, and repair-preview
  visibility for Bootstrap Alpha;
- chat-to-task draft target;
- task template registry target;
- reviewed draft submit target;
- worker template runner target;
- golden path trial target.

## Excluded

- general remote shell;
- production deployment automation for other projects;
- notification center productization;
- unbounded run;
- daemon auto-expansion;
- arbitrary task execution;
- multi-user permissions;
- mobile or watch client;
- automatic merge without operator review.

MG325 covers local worker service visibility only. Worker task claim, Codex
execution, MATLAB execution, worker loop start, notification send, and apply
installation remain disabled or future reviewed work.

MG326 covers natural-language-to-draft visibility only. It may produce local
preview records for task, campaign, clarifying-question, and blocked-request
drafts, but it does not create server tasks or campaigns, claim tasks, run
Codex, run MATLAB, start worker loops, send notifications, or persist raw
prompts.

MG327 covers task template registry visibility only. It defines
`skybridge.task_template_registry.v1` metadata for the first Bootstrap Alpha
templates and lets Desktop/planner scripts query that metadata. It does not
create server tasks or campaigns, claim tasks, run Codex, run MATLAB, start
worker loops, send notifications, expose arbitrary shell, or persist raw
prompts.

MG328 covers reviewed queued-record submit only. Submit preview creates
nothing. Confirmed submit may create one queued task or one non-running draft
campaign after exact operator confirmation. It does not claim tasks, run
Codex, run MATLAB, start worker loops, send notifications, expose arbitrary
shell, unpause project control, or persist raw prompts or raw responses.

## Release Principle

Bootstrap Alpha is complete only when the golden path is understandable,
reviewable, bounded by templates, and validated by safe reports. It does not
need broad policy expansion or new safety/reporting layers beyond the acceptance
checks required to keep the product boundary clear.

token_printed=false
