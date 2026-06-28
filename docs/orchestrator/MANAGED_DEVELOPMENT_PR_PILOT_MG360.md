# MG360 Managed Dev Git/GH Provider Repair

MG359A proved real managed-development PR creation with a bounded manual Git/GH fallback after the managed-dev controller reported `git_unavailable` before mutation.

MG360 repairs the controller-native Git/GH provider path so `manual-managed-dev-pr-pilot.ps1` can drive preview, local apply, draft PR creation, and CI observation through `skybridge-managed-dev-pilot.ps1` itself.

The controller-native path is required before broader managed development because branch creation, allowed-path enforcement, draft PR creation, and CI observation must be reported by one audited controller rather than by an external fallback sequence.

The MG360 pilot PR remains draft. Human review decides whether it is merged.

Safety boundaries remain unchanged:

- no auto-merge
- no release, tag, or asset creation
- no deployment or production infrastructure mutation
- no worker loop or queue runner
- no task creation or task claim
- no Codex generation or execution
- no MATLAB, Hermes, or MCP execution
- token_printed=false

