# v2 Security Hardening Summary

The v2 local control-plane RC hardens the preview surface in four areas.

## Local Auth

- Loopback origin policy is explicit.
- Session state is hash-only and fixture-only.
- Unsafe auth payloads are rejected.
- Authenticated reads are safe metadata only.
- Auth does not enable execution, queue apply, remote execution, arbitrary command dispatch, or host mutation.

## Evidence Hygiene

- Rehearsal and soak reports are safe summaries.
- Raw logs, prompts, transcripts, authorization headers, cookies, private keys, and raw auth values are not persisted.
- Generated report writers reject unsafe text patterns.

## Supply Chain Preview

- Attestation preview uses hash-only or fixture-safe signature metadata.
- No production private key is committed or generated into tracked files.
- SBOM preview reads local dependency metadata only.
- SBOM preview performs no network install or upload.

## Host And Installer Safety

- Host consent remains blocked by default.
- Installer interlock blocks real mutation by default.
- Registry/startup/scheduled-task/service/PATH/power settings remain unavailable.
- Future host mutation requires an explicit future goal.
