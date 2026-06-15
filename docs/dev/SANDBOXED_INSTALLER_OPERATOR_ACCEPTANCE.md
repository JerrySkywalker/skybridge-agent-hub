# Sandboxed Installer Operator Acceptance

The operator acceptance checklist for the sandboxed installer candidate is:

- release workflow side effects classified
- tag safety gate passes
- installer candidate manifest verifies
- sandbox-installed runtime rehearsal passes
- install, upgrade, rollback soak passes
- recovery sandbox report passes
- Web and Desktop installer acceptance panels remain read-only
- disabled capabilities remain disabled

No real install, uninstall, update, worker execute, apply, start, start-queue, resume, or claim controls are enabled.

`token_printed=false`
