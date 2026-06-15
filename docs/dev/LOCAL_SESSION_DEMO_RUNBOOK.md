# Local Session Demo Runbook

1. Run `skybridge-local-session.ps1 -Command demo`.
2. Open the Web Operator Console local-session route and show the Manual Local Session panel.
3. Open Desktop and show the Manual Local Session card.
4. Run `skybridge-local-doctor.ps1 -Command report` to generate the safe doctor report.
5. Run `skybridge-local-session.ps1 -Command report` to generate the local session report.

Do not run worker, queue, workunit, task claim or task PR commands during the demo. token_printed=false
