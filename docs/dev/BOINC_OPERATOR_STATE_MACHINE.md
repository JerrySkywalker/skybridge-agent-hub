# BOINC Operator State Machine

| State | Required gate | Failure state | Evidence produced | Execution allowed | Human review required |
| --- | --- | --- | --- | --- | --- |
| Idle | active/stale/lock clear | Blocked | status report | no | yes |
| Paired | durable pairing gate | Blocked | pairing record | no | yes |
| Approval pending | approval request | Blocked | approval preview | no | yes |
| Approved preview | durable approval gate | Blocked | approval record | no | yes |
| Ready for controlled workunit | release, pairing, approval, resident polling, resource and failure budget gates | Blocked | gate report | only under explicit future scope | yes |
| Workunit running | exact scoped workunit approval | Blocked | workunit evidence | only under explicit future scope | yes |
| Task PR held | task PR exists and CI pending/review held | Blocked | hold report | no | yes |
| Task PR merged | scoped docs-only or manual merge evidence | Blocked | merge audit | no | yes |
| Finalizer running | merged task PR and finalizer gate | Blocked | finalizer evidence | no worker execution | yes |
| Completed | finalizer and evidence retention pass | Blocked | readiness report | no | yes |
| Blocked | any gate fails | Blocked | blocker report | no | yes |
| Emergency stop preview | stop preview gate | Blocked | stop preview | no | yes |
| Drain preview | drain preview gate | Blocked | drain preview | no | yes |

Every transition preserves disabled remote execution, arbitrary command dispatch, global execution and queue apply unless a future goal explicitly scopes a narrow controlled operation.

`token_printed=false`

