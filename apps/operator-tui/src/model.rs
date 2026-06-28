use serde::Serialize;

pub const STATE_SCHEMA: &str = "skybridge.operator_tui_state.v1";
pub const REPORT_SCHEMA: &str = "skybridge.operator_tui_report.v1";
pub const FIXTURE_GENERATED_AT: &str = "2026-06-29T00:00:00Z";
pub const BASELINE_HEAD: &str = "c2bd551370f68950c2cd759de6a4f30b5e0396d8";
pub const CLOUD_IMAGE_REF: &str =
    "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-c2bd551370f68950c2cd759de6a4f30b5e0396d8";

#[derive(Debug, Clone, Serialize)]
pub struct OperatorState {
    pub schema: &'static str,
    pub generated_at: &'static str,
    pub mode: &'static str,
    pub repo: RepoState,
    pub cloud: CloudState,
    pub worker: WorkerState,
    pub campaign: CampaignState,
    pub hermes_candidate: HermesCandidateState,
    pub managed_dev: ManagedDevState,
    pub safety: SafetyState,
}

#[derive(Debug, Clone, Serialize)]
pub struct RepoState {
    pub branch: &'static str,
    pub head: &'static str,
    pub worktree_clean: bool,
    pub origin_aligned: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct CloudState {
    pub health: &'static str,
    pub version: &'static str,
    pub image_ref: &'static str,
    pub parity: &'static str,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkerState {
    pub worker_id: &'static str,
    pub local_status: &'static str,
    pub remote_status: &'static str,
    pub stale: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct CampaignState {
    pub campaign_id: &'static str,
    pub current_step: &'static str,
    pub current_goal_id: &'static str,
    pub current_goal_status: &'static str,
    pub pending_steps: Vec<&'static str>,
    pub blockers: Vec<&'static str>,
    pub warnings: Vec<&'static str>,
}

#[derive(Debug, Clone, Serialize)]
pub struct HermesCandidateState {
    pub candidate_path: &'static str,
    pub candidate_hash: &'static str,
    pub candidate_validated: bool,
    pub candidate_approved: bool,
    pub candidate_appended: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct ManagedDevState {
    pub branch: Option<&'static str>,
    pub pr_number: Option<u32>,
    pub pr_status: &'static str,
    pub ci_status: &'static str,
    pub merge_gate: &'static str,
}

#[derive(Debug, Clone, Serialize)]
pub struct SafetyState {
    pub token_printed: bool,
    pub auto_merge_enabled: bool,
    pub release_created: bool,
    pub tag_created: bool,
    pub asset_uploaded: bool,
    pub worker_loop_started: bool,
    pub queue_runner_started: bool,
    pub task_created: bool,
    pub task_claimed: bool,
    pub execution_started: bool,
    pub hermes_live_called: bool,
    pub mcp_run_called: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct TimelineStep {
    pub label: &'static str,
    pub status: &'static str,
}

#[derive(Debug, Clone, Serialize)]
pub struct OperatorReport {
    pub schema: &'static str,
    pub generated_at: &'static str,
    pub mode: String,
    pub fixture_used: bool,
    pub interactive_started: bool,
    pub state_schema: &'static str,
    pub panels_rendered: Vec<&'static str>,
    pub disabled_actions: Vec<ActionStatus>,
    pub active_actions: Vec<ActionStatus>,
    pub mutation_attempted: bool,
    pub append_attempted: bool,
    pub approval_attempted: bool,
    pub task_created: bool,
    pub task_claimed: bool,
    pub execution_started: bool,
    pub branch_created: bool,
    pub pr_created: bool,
    pub merge_performed: bool,
    pub deploy_triggered: bool,
    pub worker_loop_started: bool,
    pub queue_runner_started: bool,
    pub hermes_live_called: bool,
    pub mcp_run_called: bool,
    pub token_printed: bool,
    pub blockers: Vec<&'static str>,
    pub warnings: Vec<&'static str>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ActionStatus {
    pub action: &'static str,
    pub key: &'static str,
    pub label: &'static str,
    pub enabled: bool,
    pub disabled_reasons: Vec<&'static str>,
}

pub fn fixture_state() -> OperatorState {
    OperatorState {
        schema: STATE_SCHEMA,
        generated_at: FIXTURE_GENERATED_AT,
        mode: "fixture",
        repo: RepoState {
            branch: "main",
            head: BASELINE_HEAD,
            worktree_clean: true,
            origin_aligned: true,
        },
        cloud: CloudState {
            health: "ok",
            version: BASELINE_HEAD,
            image_ref: CLOUD_IMAGE_REF,
            parity: "ok",
        },
        worker: WorkerState {
            worker_id: "jerry-win-local-01",
            local_status: "idle",
            remote_status: "paired_read_only",
            stale: false,
        },
        campaign: CampaignState {
            campaign_id: "mg368-manual-hosted-dev-simulation",
            current_step: "MG368A Ratatui fixture console skeleton",
            current_goal_id: "MG368A",
            current_goal_status: "fixture_read_only",
            pending_steps: vec![
                "MG368B read-only local/cloud monitor",
                "MG368C candidate review/append console",
                "MG368D single-step goal control gate",
                "MG369 manual single-step hosted-dev experiment",
            ],
            blockers: vec![
                "mutation_not_allowed_in_fixture",
                "requires_later_reviewed_gate",
                "execution_apply_disabled",
            ],
            warnings: vec![
                "fixture data only; no live local or cloud polling in MG368A",
                "all mutation-capable actions are visible but disabled",
            ],
        },
        hermes_candidate: HermesCandidateState {
            candidate_path:
                ".agent/tmp/hermes-planner-provider/candidates/mg368a-fixture-candidate.md",
            candidate_hash:
                "sha256:368a000000000000000000000000000000000000000000000000000000000001",
            candidate_validated: true,
            candidate_approved: false,
            candidate_appended: false,
        },
        managed_dev: ManagedDevState {
            branch: None,
            pr_number: None,
            pr_status: "not_created",
            ci_status: "not_started",
            merge_gate: "human_review_required",
        },
        safety: SafetyState {
            token_printed: false,
            auto_merge_enabled: false,
            release_created: false,
            tag_created: false,
            asset_uploaded: false,
            worker_loop_started: false,
            queue_runner_started: false,
            task_created: false,
            task_claimed: false,
            execution_started: false,
            hermes_live_called: false,
            mcp_run_called: false,
        },
    }
}

pub fn timeline_steps(state: &OperatorState) -> Vec<TimelineStep> {
    vec![
        TimelineStep {
            label: "Objective",
            status: "done",
        },
        TimelineStep {
            label: "Candidate generated",
            status: "done",
        },
        TimelineStep {
            label: "Candidate validated",
            status: if state.hermes_candidate.candidate_validated {
                "done"
            } else {
                "pending"
            },
        },
        TimelineStep {
            label: "Candidate reviewed",
            status: "ready",
        },
        TimelineStep {
            label: "Candidate appended",
            status: "blocked",
        },
        TimelineStep {
            label: "Bounded action previewed",
            status: "blocked",
        },
        TimelineStep {
            label: "Single-step started",
            status: "blocked",
        },
        TimelineStep {
            label: "Draft PR created",
            status: "blocked",
        },
        TimelineStep {
            label: "CI observed",
            status: "pending",
        },
        TimelineStep {
            label: "Human merge or hold",
            status: "pending",
        },
    ]
}
