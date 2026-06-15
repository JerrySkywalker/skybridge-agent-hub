# Host Mutation Disabled By Default

SkyBridge installer promotion work remains sandbox-only until a future explicit goal authorizes host mutation.

Current commands may write safe reports and staged artifacts under `.agent/tmp`. They must not write registry keys, startup entries, scheduled tasks, services, PATH, power settings, Program Files, AppData, Desktop, Start Menu, or other host locations.

Any future host installer work must add an explicit permission model and acceptance gate before mutation is possible.
