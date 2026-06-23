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

## Release Principle

Bootstrap Alpha is complete only when the golden path is understandable,
reviewable, bounded by templates, and validated by safe reports. It does not
need broad policy expansion or new safety/reporting layers beyond the acceptance
checks required to keep the product boundary clear.

token_printed=false
