# MG362 Campaign-Driven Managed Development

MG362 proves the campaign-driven managed-dev end-to-end path.

A reviewed development goal is represented as one campaign metadata step. The
bounded loop selects one managed-dev action. The controller-native Git/GH path
then creates a docs-only draft PR and observes CI. The PR remains held for human
review.

This document is intentionally small because the detailed operator contract is
in [MANAGED_DEV_CAMPAIGN_E2E.md](MANAGED_DEV_CAMPAIGN_E2E.md).

Safety state:

- reviewed goal appended as campaign metadata;
- one bounded managed-dev action selected;
- controller-native Git/GH path used;
- draft PR remains a human review hold;
- no auto-merge;
- no release, tag or asset creation;
- no deployment or production infrastructure mutation;
- no worker loop or queue runner;
- no Codex, MATLAB, Hermes or MCP execution;
- `manual_fallback_used=false`;
- `token_printed=false`.
