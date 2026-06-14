# Local Productization RC

The local productization RC is `v1.1.0-local-productization-rc`.

It covers:
- bounded non-worker local runtime candidate metadata;
- process lifecycle, PID, lock, port, cleanup, and stale detection metadata;
- desktop artifact candidate detection and checksum previews;
- first-run config wizard preview with validation and redaction;
- safe diagnostics and product readiness reports.

The RC does not authorize worker execution, workunit apply, task claims, queue apply, remote execution, arbitrary command dispatch, installer writes, services, registry changes, startup entries, network updates, uploads, or GitHub releases.
