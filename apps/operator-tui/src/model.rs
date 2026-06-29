use serde::Serialize;

pub const STATE_SCHEMA: &str = "skybridge.operator_tui_state.v1";
pub const REPORT_SCHEMA: &str = "skybridge.operator_tui_report.v1";
pub const FIXTURE_GENERATED_AT: &str = "2026-06-29T00:00:00Z";
pub const BASELINE_HEAD: &str = "9303808ce06789bc918f49f41277ba287bceb7e2";
pub const STAGE_S1_1_HEAD: &str = "c2bd551370f68950c2cd759de6a4f30b5e0396d8";
pub const CLOUD_IMAGE_REF: &str =
    "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-9303808ce06789bc918f49f41277ba287bceb7e2";

#[derive(Debug, Clone, Serialize)]
pub struct OperatorState {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: String,
    pub local_state_source: String,
    pub cloud_state_source: String,
    pub local_state_loaded: bool,
    pub cloud_state_loaded: bool,
    pub read_only: bool,
    pub repo: RepoState,
    pub cloud: CloudState,
    pub status_freshness: StatusFreshness,
    pub stage_close: StageCloseState,
    pub worker: WorkerState,
    pub campaign: CampaignState,
    pub hermes_candidate: HermesCandidateState,
    pub managed_dev: ManagedDevState,
    pub safety: SafetyState,
}

#[derive(Debug, Clone, Serialize)]
pub struct RepoState {
    pub branch: String,
    pub head: String,
    pub local_main_commit: String,
    pub origin_main_commit: String,
    pub main_aligned: bool,
    pub worktree_clean: bool,
    pub origin_aligned: bool,
    pub git_status_summary: Vec<String>,
    pub repository_root: String,
    pub package_manager_marker: String,
    pub known_warning_state: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct CloudState {
    pub health: String,
    pub version: String,
    pub image_ref: String,
    pub parity: String,
    pub health_ok: bool,
    pub version_ok: bool,
    pub commit_sha: String,
    pub image_tag: String,
    pub parity_ok: bool,
    pub missing_routes: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct StatusFreshness {
    pub generated_at: String,
    pub local_age_seconds: Option<u64>,
    pub cloud_age_seconds: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct StageCloseState {
    pub source: String,
    pub baseline_commit: String,
    pub baseline_image_ref: String,
    pub tracked_warning: String,
    pub resolved_warning: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkerState {
    pub worker_id: String,
    pub local_status: String,
    pub remote_status: String,
    pub stale: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct CampaignState {
    pub campaign_id: String,
    pub current_step: String,
    pub current_goal_id: String,
    pub current_goal_status: String,
    pub pending_steps: Vec<String>,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct HermesCandidateState {
    pub candidate_path: String,
    pub candidate_hash: String,
    pub candidate_validated: bool,
    pub candidate_approved: bool,
    pub candidate_appended: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct ManagedDevState {
    pub branch: Option<String>,
    pub pr_number: Option<u32>,
    pub pr_status: String,
    pub ci_status: String,
    pub merge_gate: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct SafetyState {
    pub read_only: bool,
    pub mutation_attempted: bool,
    pub append_attempted: bool,
    pub approval_attempted: bool,
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
    pub branch_created: bool,
    pub pr_created: bool,
    pub merge_performed: bool,
    pub deploy_triggered: bool,
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
    pub generated_at: String,
    pub mode: String,
    pub fixture_used: bool,
    pub interactive_started: bool,
    pub state_schema: &'static str,
    pub local_state_loaded: bool,
    pub cloud_state_loaded: bool,
    pub local_cloud_parity_checked: bool,
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
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
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
    let generated_at = FIXTURE_GENERATED_AT.to_string();
    OperatorState {
        schema: STATE_SCHEMA,
        generated_at: generated_at.clone(),
        mode: "fixture".to_string(),
        local_state_source: "fixture".to_string(),
        cloud_state_source: "fixture".to_string(),
        local_state_loaded: false,
        cloud_state_loaded: false,
        read_only: true,
        repo: RepoState {
            branch: "main".to_string(),
            head: BASELINE_HEAD.to_string(),
            local_main_commit: BASELINE_HEAD.to_string(),
            origin_main_commit: BASELINE_HEAD.to_string(),
            main_aligned: true,
            worktree_clean: true,
            origin_aligned: true,
            git_status_summary: vec!["fixture_clean".to_string()],
            repository_root: "fixture://skybridge-agent-hub".to_string(),
            package_manager_marker: "pnpm".to_string(),
            known_warning_state: vec![
                "tracked: Vite chunk-size warning non-failing".to_string(),
                "resolved: GitHub Actions Node.js 20 deprecation resolved".to_string(),
            ],
        },
        cloud: CloudState {
            health: "ok".to_string(),
            version: BASELINE_HEAD.to_string(),
            image_ref: CLOUD_IMAGE_REF.to_string(),
            parity: "ok".to_string(),
            health_ok: true,
            version_ok: true,
            commit_sha: BASELINE_HEAD.to_string(),
            image_tag: format!("sha-{BASELINE_HEAD}"),
            parity_ok: true,
            missing_routes: Vec::new(),
        },
        status_freshness: StatusFreshness {
            generated_at,
            local_age_seconds: None,
            cloud_age_seconds: None,
        },
        stage_close: StageCloseState {
            source: "docs/release/STAGE_S1_1_CLOSE.md".to_string(),
            baseline_commit: STAGE_S1_1_HEAD.to_string(),
            baseline_image_ref: format!(
                "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-{STAGE_S1_1_HEAD}"
            ),
            tracked_warning: "Vite chunk-size warning non-failing".to_string(),
            resolved_warning: "GitHub Actions Node.js 20 deprecation resolved".to_string(),
        },
        worker: WorkerState {
            worker_id: "jerry-win-local-01".to_string(),
            local_status: "idle".to_string(),
            remote_status: "paired_read_only".to_string(),
            stale: false,
        },
        campaign: CampaignState {
            campaign_id: "mg368-manual-hosted-dev-simulation".to_string(),
            current_step: "MG368B Ratatui read-only local/cloud monitor".to_string(),
            current_goal_id: "MG368B".to_string(),
            current_goal_status: "read_only_monitor".to_string(),
            pending_steps: vec![
                "MG368C candidate review/append console".to_string(),
                "MG368D single-step goal control gate".to_string(),
                "MG369 manual single-step hosted-dev experiment".to_string(),
            ],
            blockers: vec![
                "requires_later_reviewed_gate".to_string(),
                "execution_apply_disabled".to_string(),
                "mutation_not_allowed_in_read_only_monitor".to_string(),
            ],
            warnings: vec![
                "pipeline operations remain disabled until MG368C/MG368D".to_string(),
                "all mutation-capable actions are visible but disabled".to_string(),
            ],
        },
        hermes_candidate: HermesCandidateState {
            candidate_path:
                ".agent/tmp/hermes-planner-provider/candidates/mg368a-fixture-candidate.md"
                    .to_string(),
            candidate_hash:
                "sha256:368a000000000000000000000000000000000000000000000000000000000001"
                    .to_string(),
            candidate_validated: true,
            candidate_approved: false,
            candidate_appended: false,
        },
        managed_dev: ManagedDevState {
            branch: None,
            pr_number: None,
            pr_status: "not_created".to_string(),
            ci_status: "not_started".to_string(),
            merge_gate: "human_review_required".to_string(),
        },
        safety: SafetyState::read_only(),
    }
}

impl SafetyState {
    pub fn read_only() -> Self {
        Self {
            read_only: true,
            mutation_attempted: false,
            append_attempted: false,
            approval_attempted: false,
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
            branch_created: false,
            pr_created: false,
            merge_performed: false,
            deploy_triggered: false,
            hermes_live_called: false,
            mcp_run_called: false,
        }
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
            status: "blocked",
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
