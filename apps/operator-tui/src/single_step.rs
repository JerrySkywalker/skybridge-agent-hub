use std::{
    fs,
    path::{Path, PathBuf},
};

use anyhow::Context;
use serde::{Deserialize, Serialize};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

use crate::{
    actions::{active_action_statuses, disabled_action_statuses},
    candidate::load_candidate_state,
    model::{ActionStatus, OperatorState},
    render::PANELS,
};

pub const SINGLE_STEP_STATE_SCHEMA: &str = "skybridge.operator_tui_single_step_state.v1";
pub const SINGLE_STEP_REPORT_SCHEMA: &str = "skybridge.operator_tui_single_step_report.v1";
pub const START_CONFIRMATION: &str = "I_UNDERSTAND_START_ONE_GOAL_SINGLE_STEP_ONLY_NO_QUEUE_LOOP";
pub const PAUSE_CONFIRMATION: &str = "I_UNDERSTAND_SAFE_PAUSE_SINGLE_STEP_PIPELINE_WITH_REASON";
pub const ABORT_CONFIRMATION: &str =
    "I_UNDERSTAND_ABORT_TERMINATE_PREVIEW_OR_FIXTURE_ONLY_NO_PROCESS_KILL";
pub const DEFAULT_SINGLE_STEP_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/single-step";
pub const DEFAULT_CANDIDATE_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/candidate-flow";

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum SingleStepAction {
    None,
    PreviewBoundedAction,
    StartOneFixture,
    SafePause,
    AbortPreview,
    AbortApplyFixture,
}

impl SingleStepAction {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "preview" | "preview-bounded-action" => Ok(Self::PreviewBoundedAction),
            "start-fixture" | "start-one-fixture" | "start-one-goal" => Ok(Self::StartOneFixture),
            "safe-pause" | "pause" => Ok(Self::SafePause),
            "abort-preview" | "abort-terminate-preview" => Ok(Self::AbortPreview),
            "abort-apply-fixture" | "abort-terminate" => Ok(Self::AbortApplyFixture),
            other => anyhow::bail!("unknown single-step action: {other}"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct SingleStepOptions {
    pub output_dir: PathBuf,
    pub action: SingleStepAction,
    pub mode: String,
    pub start_confirm: String,
    pub pause_confirm: String,
    pub abort_confirm: String,
    pub pause_reason: String,
    pub abort_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SingleStepState {
    pub schema: String,
    pub generated_at: String,
    pub mode: String,
    pub local_state_loaded: bool,
    pub cloud_state_loaded: bool,
    pub cloud_parity_shown: bool,
    pub candidate_state_loaded: bool,
    pub candidate_appended: bool,
    pub appended_step_id: String,
    pub next_bounded_action_previewed: bool,
    pub next_bounded_action_type: String,
    pub next_bounded_action_allowed: bool,
    pub next_bounded_action_blockers: Vec<String>,
    pub start_one_requested: bool,
    pub start_one_confirmed: bool,
    pub start_one_performed: bool,
    pub start_one_mode: String,
    pub start_one_result: String,
    pub safe_pause_requested: bool,
    pub safe_pause_reason: String,
    pub safe_pause_confirmed: bool,
    pub safe_pause_performed: bool,
    pub abort_requested: bool,
    pub abort_reason: String,
    pub abort_previewed: bool,
    pub abort_confirmed: bool,
    pub abort_performed: bool,
    pub task_created: bool,
    pub task_claimed: bool,
    pub execution_started: bool,
    pub branch_created: bool,
    pub pr_created: bool,
    pub draft_pr_created: bool,
    pub worker_loop_started: bool,
    pub queue_runner_started: bool,
    pub run_forever_started: bool,
    pub hermes_live_called: bool,
    pub mcp_run_called: bool,
    pub merge_performed: bool,
    pub deploy_triggered: bool,
    pub auto_merge_enabled: bool,
    pub release_created: bool,
    pub tag_created: bool,
    pub asset_uploaded: bool,
    pub token_printed: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct SingleStepReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub local_state_loaded: bool,
    pub cloud_state_loaded: bool,
    pub cloud_parity_shown: bool,
    pub candidate_appended: bool,
    pub appended_step_id: String,
    pub preview_bounded_action_performed: bool,
    pub preview_bounded_action_result: String,
    pub start_one_goal_attempted: bool,
    pub start_one_goal_performed: bool,
    pub start_one_goal_result: String,
    pub safe_pause_attempted: bool,
    pub safe_pause_performed: bool,
    pub safe_pause_result: String,
    pub abort_terminate_attempted: bool,
    pub abort_terminate_performed: bool,
    pub abort_terminate_result: String,
    pub panels_rendered: Vec<&'static str>,
    pub active_actions: Vec<ActionStatus>,
    pub disabled_actions: Vec<ActionStatus>,
    pub exact_confirmations_required: Vec<&'static str>,
    pub exact_confirmations_matched: Vec<&'static str>,
    pub task_created: bool,
    pub task_claimed: bool,
    pub execution_started: bool,
    pub branch_created: bool,
    pub pr_created: bool,
    pub draft_pr_created: bool,
    pub merge_performed: bool,
    pub deploy_triggered: bool,
    pub worker_loop_started: bool,
    pub queue_runner_started: bool,
    pub run_forever_started: bool,
    pub hermes_live_called: bool,
    pub mcp_run_called: bool,
    pub auto_merge_enabled: bool,
    pub release_created: bool,
    pub tag_created: bool,
    pub asset_uploaded: bool,
    pub token_printed: bool,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
}

impl SingleStepState {
    pub fn empty() -> Self {
        Self {
            schema: SINGLE_STEP_STATE_SCHEMA.to_string(),
            generated_at: now_utc(),
            mode: "fixture".to_string(),
            local_state_loaded: false,
            cloud_state_loaded: false,
            cloud_parity_shown: false,
            candidate_state_loaded: false,
            candidate_appended: false,
            appended_step_id: String::new(),
            next_bounded_action_previewed: false,
            next_bounded_action_type: "not_previewed".to_string(),
            next_bounded_action_allowed: false,
            next_bounded_action_blockers: Vec::new(),
            start_one_requested: false,
            start_one_confirmed: false,
            start_one_performed: false,
            start_one_mode: "fixture".to_string(),
            start_one_result: "not_requested".to_string(),
            safe_pause_requested: false,
            safe_pause_reason: String::new(),
            safe_pause_confirmed: false,
            safe_pause_performed: false,
            abort_requested: false,
            abort_reason: String::new(),
            abort_previewed: false,
            abort_confirmed: false,
            abort_performed: false,
            task_created: false,
            task_claimed: false,
            execution_started: false,
            branch_created: false,
            pr_created: false,
            draft_pr_created: false,
            worker_loop_started: false,
            queue_runner_started: false,
            run_forever_started: false,
            hermes_live_called: false,
            mcp_run_called: false,
            merge_performed: false,
            deploy_triggered: false,
            auto_merge_enabled: false,
            release_created: false,
            tag_created: false,
            asset_uploaded: false,
            token_printed: false,
        }
    }
}

pub fn load_single_step_state(output_dir: &Path) -> SingleStepState {
    let state_path = output_dir.join("operator-tui-single-step-state.json");
    fs::read_to_string(state_path)
        .ok()
        .and_then(|text| serde_json::from_str::<SingleStepState>(&text).ok())
        .unwrap_or_else(SingleStepState::empty)
}

pub fn run_single_step_action(
    options: &SingleStepOptions,
    operator_state: &OperatorState,
) -> SingleStepState {
    let mut state = load_single_step_state(&options.output_dir);
    state.generated_at = now_utc();
    state.mode = normalize_mode(&options.mode).to_string();
    sync_from_operator(&mut state, operator_state);

    match options.action {
        SingleStepAction::None => {}
        SingleStepAction::PreviewBoundedAction => preview_bounded_action(&mut state),
        SingleStepAction::StartOneFixture => start_one_fixture(&mut state, options),
        SingleStepAction::SafePause => safe_pause(&mut state, options),
        SingleStepAction::AbortPreview => abort_preview(&mut state, options),
        SingleStepAction::AbortApplyFixture => abort_apply_fixture(&mut state, options),
    }

    force_no_real_execution_flags(&mut state);
    state
}

pub fn single_step_report(operator_state: &OperatorState) -> SingleStepReport {
    let step = &operator_state.single_step;
    let mut blockers = step.next_bounded_action_blockers.clone();
    if !step.candidate_appended {
        push_unique(&mut blockers, "candidate_step_not_appended");
    }

    let mut warnings = Vec::new();
    if step.start_one_performed {
        push_unique(
            &mut warnings,
            "fixture_single_step_gate_exercised_no_real_execution",
        );
    }
    if step.abort_previewed && !step.abort_performed {
        push_unique(&mut warnings, "abort_preview_only_no_process_kill");
    }

    SingleStepReport {
        schema: SINGLE_STEP_REPORT_SCHEMA,
        generated_at: operator_state.generated_at.clone(),
        mode: "single-step-control",
        local_state_loaded: step.local_state_loaded,
        cloud_state_loaded: step.cloud_state_loaded,
        cloud_parity_shown: step.cloud_parity_shown,
        candidate_appended: step.candidate_appended,
        appended_step_id: step.appended_step_id.clone(),
        preview_bounded_action_performed: step.next_bounded_action_previewed,
        preview_bounded_action_result: preview_result(step),
        start_one_goal_attempted: step.start_one_requested,
        start_one_goal_performed: step.start_one_performed,
        start_one_goal_result: step.start_one_result.clone(),
        safe_pause_attempted: step.safe_pause_requested,
        safe_pause_performed: step.safe_pause_performed,
        safe_pause_result: pause_result(step),
        abort_terminate_attempted: step.abort_requested,
        abort_terminate_performed: step.abort_performed,
        abort_terminate_result: abort_result(step),
        panels_rendered: PANELS.to_vec(),
        active_actions: active_action_statuses(),
        disabled_actions: disabled_action_statuses(),
        exact_confirmations_required: vec![
            START_CONFIRMATION,
            PAUSE_CONFIRMATION,
            ABORT_CONFIRMATION,
        ],
        exact_confirmations_matched: matched_confirmations(step),
        task_created: false,
        task_claimed: false,
        execution_started: false,
        branch_created: false,
        pr_created: false,
        draft_pr_created: false,
        merge_performed: false,
        deploy_triggered: false,
        worker_loop_started: false,
        queue_runner_started: false,
        run_forever_started: false,
        hermes_live_called: false,
        mcp_run_called: false,
        auto_merge_enabled: false,
        release_created: false,
        tag_created: false,
        asset_uploaded: false,
        token_printed: false,
        blockers,
        warnings,
    }
}

pub fn write_single_step_artifacts(
    output_dir: &Path,
    operator_state: &OperatorState,
    snapshot_text: &str,
) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let state_json = serde_json::to_string_pretty(&operator_state.single_step)?;
    let report = single_step_report(operator_state);
    let report_json = serde_json::to_string_pretty(&report)?;
    let report_md = render_single_step_report_markdown(&report);
    let preview_json = render_preview_json(&operator_state.single_step)?;
    let preview_md = render_preview_markdown(&operator_state.single_step);

    write_text(
        &output_dir.join("operator-tui-single-step-snapshot.txt"),
        snapshot_text,
    )?;
    write_text(
        &output_dir.join("operator-tui-single-step-state.json"),
        &format!("{state_json}\n"),
    )?;
    write_text(
        &output_dir.join("operator-tui-single-step-report.json"),
        &format!("{report_json}\n"),
    )?;
    write_text(
        &output_dir.join("operator-tui-single-step-report.md"),
        &report_md,
    )?;
    write_text(
        &output_dir.join("operator-tui-single-step-preview.json"),
        &format!("{preview_json}\n"),
    )?;
    write_text(
        &output_dir.join("operator-tui-single-step-preview.md"),
        &preview_md,
    )?;

    Ok(())
}

pub fn load_default_candidate_state() -> crate::candidate::CandidateState {
    load_candidate_state(Path::new(DEFAULT_CANDIDATE_OUTPUT_DIR))
}

fn sync_from_operator(state: &mut SingleStepState, operator_state: &OperatorState) {
    let candidate = &operator_state.candidate_flow;
    state.local_state_loaded = operator_state.local_state_loaded;
    state.cloud_state_loaded = operator_state.cloud_state_loaded;
    state.cloud_parity_shown = operator_state.cloud_state_loaded && operator_state.cloud.parity_ok;
    state.candidate_state_loaded = !candidate.candidate_path.is_empty();
    state.candidate_appended = candidate.append_performed;
    state.appended_step_id = candidate.appended_step_id.clone();
}

fn preview_bounded_action(state: &mut SingleStepState) {
    state.next_bounded_action_previewed = true;
    state.next_bounded_action_type = "fixture_single_step_start_gate".to_string();
    state.next_bounded_action_allowed =
        state.candidate_appended && state.cloud_parity_shown && state.local_state_loaded;
    state.next_bounded_action_blockers.clear();
    if !state.candidate_appended {
        state
            .next_bounded_action_blockers
            .push("candidate_step_not_appended".to_string());
    }
    if !state.local_state_loaded {
        state
            .next_bounded_action_blockers
            .push("local_state_not_loaded".to_string());
    }
    if !state.cloud_parity_shown {
        state
            .next_bounded_action_blockers
            .push("cloud_parity_not_shown".to_string());
    }
}

fn start_one_fixture(state: &mut SingleStepState, options: &SingleStepOptions) {
    state.start_one_requested = true;
    state.start_one_mode = "fixture".to_string();
    if !state.next_bounded_action_previewed {
        preview_bounded_action(state);
    }
    if options.start_confirm != START_CONFIRMATION {
        state.start_one_result = "start_confirmation_required".to_string();
        return;
    }
    state.start_one_confirmed = true;
    if !state.next_bounded_action_allowed {
        state.start_one_result = "next_bounded_action_not_allowed".to_string();
        return;
    }

    state.start_one_performed = true;
    state.start_one_result = "fixture_single_step_gate_exercised_no_execution".to_string();
}

fn safe_pause(state: &mut SingleStepState, options: &SingleStepOptions) {
    state.safe_pause_requested = true;
    state.safe_pause_reason = sanitize_reason(&options.pause_reason);
    if state.safe_pause_reason.is_empty() {
        push_unique(
            &mut state.next_bounded_action_blockers,
            "safe_pause_reason_required",
        );
        return;
    }
    if options.pause_confirm != PAUSE_CONFIRMATION {
        push_unique(
            &mut state.next_bounded_action_blockers,
            "safe_pause_confirmation_required",
        );
        return;
    }
    state.safe_pause_confirmed = true;
    state.safe_pause_performed = true;
}

fn abort_preview(state: &mut SingleStepState, options: &SingleStepOptions) {
    state.abort_requested = true;
    state.abort_reason = sanitize_reason(&options.abort_reason);
    state.abort_previewed = true;
}

fn abort_apply_fixture(state: &mut SingleStepState, options: &SingleStepOptions) {
    state.abort_requested = true;
    state.abort_reason = sanitize_reason(&options.abort_reason);
    state.abort_previewed = true;
    if state.abort_reason.is_empty() {
        push_unique(
            &mut state.next_bounded_action_blockers,
            "abort_reason_required",
        );
        return;
    }
    if options.abort_confirm != ABORT_CONFIRMATION {
        push_unique(
            &mut state.next_bounded_action_blockers,
            "abort_confirmation_required",
        );
        return;
    }
    state.abort_confirmed = true;
    state.abort_performed = true;
}

fn force_no_real_execution_flags(state: &mut SingleStepState) {
    state.task_created = false;
    state.task_claimed = false;
    state.execution_started = false;
    state.branch_created = false;
    state.pr_created = false;
    state.draft_pr_created = false;
    state.worker_loop_started = false;
    state.queue_runner_started = false;
    state.run_forever_started = false;
    state.hermes_live_called = false;
    state.mcp_run_called = false;
    state.merge_performed = false;
    state.deploy_triggered = false;
    state.auto_merge_enabled = false;
    state.release_created = false;
    state.tag_created = false;
    state.asset_uploaded = false;
    state.token_printed = false;
}

fn preview_result(step: &SingleStepState) -> String {
    if !step.next_bounded_action_previewed {
        "not_previewed".to_string()
    } else if step.next_bounded_action_allowed {
        "allowed_fixture_single_step".to_string()
    } else {
        "blocked".to_string()
    }
}

fn pause_result(step: &SingleStepState) -> String {
    if !step.safe_pause_requested {
        "not_requested".to_string()
    } else if step.safe_pause_performed {
        "fixture_pause_metadata_recorded".to_string()
    } else if step.safe_pause_reason.is_empty() {
        "safe_pause_reason_required".to_string()
    } else {
        "safe_pause_confirmation_required".to_string()
    }
}

fn abort_result(step: &SingleStepState) -> String {
    if !step.abort_requested {
        "not_requested".to_string()
    } else if step.abort_performed {
        "fixture_abort_metadata_recorded_no_process_kill".to_string()
    } else if step.abort_previewed {
        "abort_preview_only_no_process_kill".to_string()
    } else {
        "not_previewed".to_string()
    }
}

fn matched_confirmations(step: &SingleStepState) -> Vec<&'static str> {
    let mut values = Vec::new();
    if step.start_one_confirmed {
        values.push(START_CONFIRMATION);
    }
    if step.safe_pause_confirmed {
        values.push(PAUSE_CONFIRMATION);
    }
    if step.abort_confirmed {
        values.push(ABORT_CONFIRMATION);
    }
    values
}

fn normalize_mode(mode: &str) -> &str {
    match mode {
        "manual" => "manual",
        "preview" => "preview",
        _ => "fixture",
    }
}

fn sanitize_reason(value: &str) -> String {
    let mut safe = value.trim().replace(['\r', '\n', '\t'], " ");
    for marker in ["Authorization", "Bearer ", "token=", "secret=", "password="] {
        if safe
            .to_ascii_lowercase()
            .contains(&marker.to_ascii_lowercase())
        {
            safe = "redacted_reason".to_string();
            break;
        }
    }
    if safe.len() > 180 {
        safe.truncate(180);
    }
    safe
}

fn render_preview_json(step: &SingleStepState) -> anyhow::Result<String> {
    let value = serde_json::json!({
        "schema": "skybridge.operator_tui_single_step_preview.v1",
        "generated_at": step.generated_at,
        "candidate_appended": step.candidate_appended,
        "appended_step_id": step.appended_step_id,
        "next_bounded_action_previewed": step.next_bounded_action_previewed,
        "next_bounded_action_type": step.next_bounded_action_type,
        "next_bounded_action_allowed": step.next_bounded_action_allowed,
        "next_bounded_action_blockers": step.next_bounded_action_blockers,
        "task_created": false,
        "task_claimed": false,
        "execution_started": false,
        "worker_loop_started": false,
        "queue_runner_started": false,
        "run_forever_started": false,
        "token_printed": false
    });
    Ok(serde_json::to_string_pretty(&value)?)
}

fn render_preview_markdown(step: &SingleStepState) -> String {
    format!(
        "# Operator TUI MG368D Single-Step Preview\n\n- candidate_appended: {}\n- appended_step_id: {}\n- next_bounded_action_previewed: {}\n- next_bounded_action_type: {}\n- next_bounded_action_allowed: {}\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- token_printed: false\n",
        step.candidate_appended,
        value_or_none(&step.appended_step_id),
        step.next_bounded_action_previewed,
        step.next_bounded_action_type,
        step.next_bounded_action_allowed
    )
}

fn render_single_step_report_markdown(report: &SingleStepReport) -> String {
    let active = report
        .active_actions
        .iter()
        .map(|action| action.action)
        .collect::<Vec<_>>()
        .join(", ");
    let disabled = if report.disabled_actions.is_empty() {
        "none".to_string()
    } else {
        report
            .disabled_actions
            .iter()
            .map(|action| format!("{} ({})", action.action, action.disabled_reasons.join(", ")))
            .collect::<Vec<_>>()
            .join("\n- ")
    };

    format!(
        "# Operator TUI MG368D Single-Step Report\n\n- schema: {}\n- mode: {}\n- local_state_loaded: {}\n- cloud_state_loaded: {}\n- cloud_parity_shown: {}\n- candidate_appended: {}\n- appended_step_id: {}\n- preview_bounded_action_performed: {}\n- preview_bounded_action_result: {}\n- start_one_goal_attempted: {}\n- start_one_goal_performed: {}\n- start_one_goal_result: {}\n- safe_pause_attempted: {}\n- safe_pause_performed: {}\n- safe_pause_result: {}\n- abort_terminate_attempted: {}\n- abort_terminate_performed: {}\n- abort_terminate_result: {}\n- panels_rendered: {}\n- active_actions: {}\n- disabled_actions: {}\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- branch_created: false\n- pr_created: false\n- draft_pr_created: false\n- merge_performed: false\n- deploy_triggered: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- token_printed: false\n",
        report.schema,
        report.mode,
        report.local_state_loaded,
        report.cloud_state_loaded,
        report.cloud_parity_shown,
        report.candidate_appended,
        value_or_none(&report.appended_step_id),
        report.preview_bounded_action_performed,
        report.preview_bounded_action_result,
        report.start_one_goal_attempted,
        report.start_one_goal_performed,
        report.start_one_goal_result,
        report.safe_pause_attempted,
        report.safe_pause_performed,
        report.safe_pause_result,
        report.abort_terminate_attempted,
        report.abort_terminate_performed,
        report.abort_terminate_result,
        report.panels_rendered.join(", "),
        active,
        disabled
    )
}

fn write_text(path: &Path, text: &str) -> anyhow::Result<()> {
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

fn push_unique(values: &mut Vec<String>, value: &str) {
    if !values.iter().any(|existing| existing == value) {
        values.push(value.to_string());
    }
}

fn value_or_none(value: &str) -> &str {
    if value.is_empty() {
        "none"
    } else {
        value
    }
}

fn now_utc() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}
