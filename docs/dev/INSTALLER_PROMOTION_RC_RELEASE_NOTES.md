# Installer Promotion RC Release Notes

This RC prepares SkyBridge for a future real installer while keeping all actions sandboxed.

The release candidate introduces promotion gates, provenance, artifact validation, offline update planning, rollback preview, and host-mutation blockers. Existing tag-triggered workflows may still publish images or artifacts if the tag safety gate classifies those side effects as safe existing workflow behavior.

`token_printed=false`.
