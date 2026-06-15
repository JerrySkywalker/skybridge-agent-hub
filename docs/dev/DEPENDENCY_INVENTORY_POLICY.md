# Dependency Inventory Policy

The dependency inventory is generated from local `package.json` metadata only.

Allowed data:

- package names
- package versions
- dependency names
- dependency specifiers from package metadata
- dependency category
- local package file path relative to the repo

Forbidden data:

- environment dumps
- tokens or secret-like values
- raw CI logs
- raw worker logs
- upload payloads
- network-resolved package metadata

License resolution is marked unresolved when it would require network access.
