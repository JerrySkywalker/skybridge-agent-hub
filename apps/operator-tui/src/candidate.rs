use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::Context;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

use crate::{
    actions::{active_action_statuses, disabled_action_statuses},
    model::{ActionStatus, OperatorState},
    render::PANELS,
};

pub const CANDIDATE_STATE_SCHEMA: &str = "skybridge.operator_tui_candidate_state.v1";
pub const CANDIDATE_REPORT_SCHEMA: &str = "skybridge.operator_tui_candidate_flow_report.v1";
pub const REVIEW_CONFIRMATION: &str = "I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION";
pub const APPEND_CONFIRMATION: &str =
    "I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION";

const GOAL_APPEND_APPROVE_CONFIRMATION: &str =
    "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION";
const GOAL_APPEND_APPEND_CONFIRMATION: &str =
    "I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION";
const DEFAULT_CANDIDATE_GOAL_ID: &str = "hermes-fixture-goal-366c";
const DEFAULT_CANDIDATE_TITLE: &str = "MG367A Vite Chunk Remediation Plan Candidate";
const DEFAULT_CAMPAIGN_ID: &str = "operator-tui-candidate-flow-368c";

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum CandidateAction {
    None,
    Generate,
    Validate,
    ReviewPreview,
    ReviewApprove,
    AppendPreview,
    AppendApplyFixture,
}

impl CandidateAction {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "generate" | "generate-candidate-fixture" => Ok(Self::Generate),
            "validate" | "validate-candidate" => Ok(Self::Validate),
            "review-preview" => Ok(Self::ReviewPreview),
            "review-approve" | "review-candidate" => Ok(Self::ReviewApprove),
            "append-preview" => Ok(Self::AppendPreview),
            "append-apply-fixture" | "append-candidate" => Ok(Self::AppendApplyFixture),
            other => anyhow::bail!("unknown candidate action: {other}"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct CandidateFlowOptions {
    pub output_dir: PathBuf,
    pub action: CandidateAction,
    pub review_confirm: String,
    pub append_confirm: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateState {
    pub schema: String,
    pub generated_at: String,
    pub candidate_source: String,
    pub candidate_path: String,
    pub candidate_hash: String,
    pub candidate_title: String,
    pub candidate_goal_id: String,
    pub candidate_validated: bool,
    pub validation_result: String,
    pub validation_warnings: Vec<String>,
    pub validation_blockers: Vec<String>,
    pub review_required: bool,
    pub reviewed_by_human: bool,
    pub review_status: String,
    pub append_previewed: bool,
    pub append_allowed: bool,
    pub append_performed: bool,
    pub appended_step_id: String,
    pub appended_campaign_id: String,
    pub execution_started: bool,
    pub task_created: bool,
    pub task_claimed: bool,
    pub branch_created: bool,
    pub pr_created: bool,
    pub token_printed: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct CandidateFlowReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub local_state_loaded: bool,
    pub cloud_state_loaded: bool,
    pub cloud_parity_shown: bool,
    pub candidate_generated: bool,
    pub candidate_validated: bool,
    pub candidate_reviewed: bool,
    pub candidate_approved_for_append: bool,
    pub append_previewed: bool,
    pub append_performed: bool,
    pub appended_step_id: String,
    pub appended_campaign_id: String,
    pub panels_rendered: Vec<&'static str>,
    pub active_actions: Vec<ActionStatus>,
    pub disabled_actions: Vec<ActionStatus>,
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

#[derive(Debug)]
struct CandidatePaths {
    hermes_output_dir: String,
    goal_append_output_dir: String,
    candidate_path: String,
}

impl CandidateState {
    pub fn empty() -> Self {
        Self {
            schema: CANDIDATE_STATE_SCHEMA.to_string(),
            generated_at: now_utc(),
            candidate_source: "hermes_fixture".to_string(),
            candidate_path: default_candidate_path_for_slug("operator-tui-candidate-flow"),
            candidate_hash: String::new(),
            candidate_title: DEFAULT_CANDIDATE_TITLE.to_string(),
            candidate_goal_id: DEFAULT_CANDIDATE_GOAL_ID.to_string(),
            candidate_validated: false,
            validation_result: "not_validated".to_string(),
            validation_warnings: Vec::new(),
            validation_blockers: Vec::new(),
            review_required: true,
            reviewed_by_human: false,
            review_status: "not_reviewed".to_string(),
            append_previewed: false,
            append_allowed: false,
            append_performed: false,
            appended_step_id: String::new(),
            appended_campaign_id: DEFAULT_CAMPAIGN_ID.to_string(),
            execution_started: false,
            task_created: false,
            task_claimed: false,
            branch_created: false,
            pr_created: false,
            token_printed: false,
        }
    }
}

pub fn load_candidate_state(output_dir: &Path) -> CandidateState {
    let state_path = output_dir.join("operator-tui-candidate-state.json");
    fs::read_to_string(state_path)
        .ok()
        .and_then(|text| serde_json::from_str::<CandidateState>(&text).ok())
        .unwrap_or_else(CandidateState::empty)
}

pub fn run_candidate_action(options: &CandidateFlowOptions) -> CandidateState {
    let mut state = load_candidate_state(&options.output_dir);
    state.generated_at = now_utc();
    let paths = candidate_paths(&options.output_dir);
    state.candidate_path = paths.candidate_path.clone();

    match options.action {
        CandidateAction::None => {}
        CandidateAction::Generate => run_generate(&mut state, &paths),
        CandidateAction::Validate => run_validate(&mut state, &paths),
        CandidateAction::ReviewPreview => run_review_preview(&mut state, &paths),
        CandidateAction::ReviewApprove => run_review_approve(&mut state, &paths, options),
        CandidateAction::AppendPreview => run_append_preview(&mut state, &paths),
        CandidateAction::AppendApplyFixture => {
            run_append_apply_fixture(&mut state, &paths, options)
        }
    }

    state.execution_started = false;
    state.task_created = false;
    state.task_claimed = false;
    state.branch_created = false;
    state.pr_created = false;
    state.token_printed = false;
    state
}

pub fn candidate_report(operator_state: &OperatorState) -> CandidateFlowReport {
    let candidate = &operator_state.candidate_flow;
    let candidate_generated =
        !candidate.candidate_path.is_empty() && !candidate.candidate_hash.is_empty();
    let approval_attempted = candidate.reviewed_by_human;
    let append_attempted = candidate.append_previewed || candidate.append_performed;
    let blockers = candidate.validation_blockers.clone();
    let mut warnings = candidate.validation_warnings.clone();
    if candidate.review_required && candidate.review_status == "not_reviewed" {
        push_unique(&mut warnings, "candidate_requires_human_review");
    }
    if !candidate.append_performed {
        push_unique(&mut warnings, "candidate_append_stops_before_execution");
    }

    CandidateFlowReport {
        schema: CANDIDATE_REPORT_SCHEMA,
        generated_at: operator_state.generated_at.clone(),
        mode: "candidate-flow",
        local_state_loaded: operator_state.local_state_loaded,
        cloud_state_loaded: operator_state.cloud_state_loaded,
        cloud_parity_shown: operator_state.cloud_state_loaded && operator_state.cloud.parity_ok,
        candidate_generated,
        candidate_validated: candidate.candidate_validated,
        candidate_reviewed: candidate.reviewed_by_human,
        candidate_approved_for_append: candidate.append_allowed,
        append_previewed: candidate.append_previewed,
        append_performed: candidate.append_performed,
        appended_step_id: candidate.appended_step_id.clone(),
        appended_campaign_id: candidate.appended_campaign_id.clone(),
        panels_rendered: PANELS.to_vec(),
        active_actions: active_action_statuses(),
        disabled_actions: disabled_action_statuses(),
        mutation_attempted: candidate.append_performed,
        append_attempted,
        approval_attempted,
        task_created: false,
        task_claimed: false,
        execution_started: false,
        branch_created: false,
        pr_created: false,
        merge_performed: false,
        deploy_triggered: false,
        worker_loop_started: false,
        queue_runner_started: false,
        hermes_live_called: false,
        mcp_run_called: false,
        token_printed: false,
        blockers,
        warnings,
    }
}

pub fn write_candidate_artifacts(
    output_dir: &Path,
    operator_state: &OperatorState,
    snapshot_text: &str,
) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let state_json = serde_json::to_string_pretty(&operator_state.candidate_flow)?;
    let report = candidate_report(operator_state);
    let report_json = serde_json::to_string_pretty(&report)?;
    let report_md = render_candidate_report_markdown(&report);
    let generated_ref = render_generated_candidate_reference(&operator_state.candidate_flow);

    write_text(
        &output_dir.join("operator-tui-candidate-snapshot.txt"),
        snapshot_text,
    )?;
    write_text(
        &output_dir.join("operator-tui-candidate-state.json"),
        &format!("{state_json}\n"),
    )?;
    write_text(
        &output_dir.join("operator-tui-candidate-report.json"),
        &format!("{report_json}\n"),
    )?;
    write_text(
        &output_dir.join("operator-tui-candidate-report.md"),
        &report_md,
    )?;

    write_text(&output_dir.join("generated-candidate.md"), &generated_ref)?;
    write_text(
        &output_dir.join("candidate-state.json"),
        &format!("{state_json}\n"),
    )?;
    write_text(&output_dir.join("candidate-report.md"), &report_md)?;

    Ok(())
}

fn run_generate(state: &mut CandidateState, paths: &CandidatePaths) {
    let args = vec![
        "-Command".to_string(),
        "fixture-plan".to_string(),
        "-OutputDir".to_string(),
        paths.hermes_output_dir.clone(),
        "-CandidatePath".to_string(),
        paths.candidate_path.clone(),
        "-WriteReport".to_string(),
    ];
    match run_json_script("skybridge-hermes-planner-provider.ps1", &args) {
        Ok(value) => apply_hermes_report(state, &value),
        Err(reason) => block(state, reason),
    }
}

fn run_validate(state: &mut CandidateState, paths: &CandidatePaths) {
    let mut args = vec![
        "-Command".to_string(),
        "validate-candidate".to_string(),
        "-OutputDir".to_string(),
        paths.hermes_output_dir.clone(),
        "-CandidatePath".to_string(),
        paths.candidate_path.clone(),
        "-WriteReport".to_string(),
    ];
    if !state.candidate_hash.is_empty() {
        args.push("-ExpectedHash".to_string());
        args.push(state.candidate_hash.clone());
    }
    match run_json_script("skybridge-hermes-planner-provider.ps1", &args) {
        Ok(value) => apply_hermes_report(state, &value),
        Err(reason) => block(state, reason),
    }
}

fn run_review_preview(state: &mut CandidateState, paths: &CandidatePaths) {
    run_validate(state, paths);
    if !state.candidate_validated {
        block(state, "candidate_not_validated_for_review_preview");
        return;
    }

    let args = goal_append_args("review-preview", paths, state, Vec::new());
    match run_json_script("skybridge-goal-append.ps1", &args) {
        Ok(value) => {
            apply_goal_append_report(state, &value);
            if state.review_status == "not_reviewed" {
                state.review_status = "previewed".to_string();
            }
        }
        Err(reason) => block(state, reason),
    }
}

fn run_review_approve(
    state: &mut CandidateState,
    paths: &CandidatePaths,
    options: &CandidateFlowOptions,
) {
    run_validate(state, paths);
    if !state.candidate_validated {
        block(state, "candidate_not_validated_for_review_approval");
        return;
    }
    if options.review_confirm != REVIEW_CONFIRMATION {
        block(state, "review_confirmation_required");
        return;
    }

    let extra = vec![
        "-ApprovalReason".to_string(),
        "Operator reviewed candidate for append only; no execution authorized.".to_string(),
        "-Confirm".to_string(),
        GOAL_APPEND_APPROVE_CONFIRMATION.to_string(),
    ];
    let args = goal_append_args("approve", paths, state, extra);
    match run_json_script("skybridge-goal-append.ps1", &args) {
        Ok(value) => {
            apply_goal_append_report(state, &value);
            if bool_prop(&value, "approved") && bool_prop(&value, "approval_performed") {
                state.reviewed_by_human = true;
                state.review_status = "approved_for_append".to_string();
                state.append_allowed = true;
            }
        }
        Err(reason) => block(state, reason),
    }
}

fn run_append_preview(state: &mut CandidateState, paths: &CandidatePaths) {
    if !state.candidate_validated {
        run_validate(state, paths);
    }
    let args = goal_append_args("append-preview", paths, state, Vec::new());
    match run_json_script("skybridge-goal-append.ps1", &args) {
        Ok(value) => {
            apply_goal_append_report(state, &value);
            state.append_previewed = bool_prop(&value, "append_preview_valid");
        }
        Err(reason) => block(state, reason),
    }
}

fn run_append_apply_fixture(
    state: &mut CandidateState,
    paths: &CandidatePaths,
    options: &CandidateFlowOptions,
) {
    if !state.candidate_validated {
        run_validate(state, paths);
    }
    if !state.append_allowed {
        block(state, "candidate_not_approved_for_append");
        return;
    }
    if options.append_confirm != APPEND_CONFIRMATION {
        block(state, "append_confirmation_required");
        return;
    }

    let extra = vec![
        "-AppendReason".to_string(),
        "Operator appended reviewed candidate metadata only; no execution authorized.".to_string(),
        "-Confirm".to_string(),
        GOAL_APPEND_APPEND_CONFIRMATION.to_string(),
    ];
    let args = goal_append_args("append-apply", paths, state, extra);
    match run_json_script("skybridge-goal-append.ps1", &args) {
        Ok(value) => {
            apply_goal_append_report(state, &value);
            state.append_previewed = bool_prop(&value, "append_preview_valid");
            state.append_performed = bool_prop(&value, "append_performed");
            state.execution_started = false;
            state.task_created = false;
            state.task_claimed = false;
            state.branch_created = false;
            state.pr_created = false;
        }
        Err(reason) => block(state, reason),
    }
}

fn apply_hermes_report(state: &mut CandidateState, value: &Value) {
    state.generated_at = string_prop(value, "generated_at").unwrap_or_else(now_utc);
    state.candidate_source = "hermes_fixture".to_string();
    if let Some(path) = string_prop(value, "candidate_goal_path_safe") {
        state.candidate_path = path;
    }
    if let Some(hash) = string_prop(value, "candidate_goal_hash") {
        state.candidate_hash = hash;
    }
    state.candidate_goal_id = DEFAULT_CANDIDATE_GOAL_ID.to_string();
    state.candidate_title = DEFAULT_CANDIDATE_TITLE.to_string();
    state.candidate_validated = bool_prop(value, "candidate_validated");
    state.validation_result = if state.candidate_validated {
        "valid".to_string()
    } else {
        "blocked".to_string()
    };
    state.validation_warnings = string_array_prop(value, "warnings");
    state.validation_blockers = string_array_prop(value, "blockers");
    state.review_required = true;
    state.token_printed = false;
}

fn apply_goal_append_report(state: &mut CandidateState, value: &Value) {
    if let Some(path) = string_prop(value, "candidate_path_safe") {
        state.candidate_path = path;
    }
    if let Some(hash) = string_prop(value, "candidate_hash") {
        state.candidate_hash = hash;
    }
    if let Some(goal_id) = string_prop(value, "generated_goal_id") {
        state.candidate_goal_id = goal_id;
    }
    if let Some(title) = string_prop(value, "generated_goal_title") {
        state.candidate_title = title;
    }
    state.candidate_validated =
        bool_prop(value, "metadata_valid") && bool_prop(value, "safety_valid");
    state.validation_result = if state.candidate_validated {
        "valid".to_string()
    } else {
        "blocked".to_string()
    };
    state.validation_warnings = string_array_prop(value, "warnings");
    state.validation_blockers = string_array_prop(value, "blockers");
    state.review_required = bool_prop(value, "human_review_required");
    if bool_prop(value, "approved") {
        state.reviewed_by_human = true;
        state.review_status = "approved_for_append".to_string();
        state.append_allowed = true;
    } else if string_prop(value, "review_state").as_deref() == Some("rejected") {
        state.reviewed_by_human = true;
        state.review_status = "rejected".to_string();
        state.append_allowed = false;
    }
    if bool_prop(value, "append_preview_valid") {
        state.append_previewed = true;
    }
    if bool_prop(value, "append_performed") {
        state.append_performed = true;
        state.append_allowed = true;
        state.reviewed_by_human = true;
        state.review_status = "approved_for_append".to_string();
    }
    if let Some(step_id) = string_prop(value, "appended_step_id") {
        state.appended_step_id = step_id;
    }
    if let Some(campaign_id) = string_prop(value, "campaign_id") {
        state.appended_campaign_id = campaign_id;
    }
    state.execution_started = false;
    state.task_created = false;
    state.task_claimed = false;
    state.branch_created = false;
    state.pr_created = false;
    state.token_printed = false;
}

fn goal_append_args(
    command: &str,
    paths: &CandidatePaths,
    state: &CandidateState,
    extra: Vec<String>,
) -> Vec<String> {
    let mut args = vec![
        "-Command".to_string(),
        command.to_string(),
        "-CandidatePath".to_string(),
        paths.candidate_path.clone(),
        "-OutputDir".to_string(),
        paths.goal_append_output_dir.clone(),
        "-CampaignId".to_string(),
        state.appended_campaign_id.clone(),
        "-ExpectedHash".to_string(),
        state.candidate_hash.clone(),
        "-WriteReport".to_string(),
    ];
    args.extend(extra);
    args
}

fn run_json_script(script: &str, args: &[String]) -> Result<Value, String> {
    let mut command = Command::new("pwsh");
    command
        .arg("-NoProfile")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(Path::new("scripts/powershell").join(script));
    for arg in args {
        command.arg(arg);
    }
    command.arg("-Json");

    let output = command
        .output()
        .map_err(|_| format!("{}_unavailable", script.trim_end_matches(".ps1")))?;
    if !output.status.success() {
        return Err(format!("{}_failed", script.trim_end_matches(".ps1")));
    }

    serde_json::from_slice::<Value>(&output.stdout)
        .map_err(|_| format!("{}_invalid_json", script.trim_end_matches(".ps1")))
}

fn candidate_paths(output_dir: &Path) -> CandidatePaths {
    let slug = output_slug(output_dir);
    let hermes_output_dir = format!(".agent/tmp/hermes-planner-provider/{slug}");
    let goal_append_output_dir = format!(".agent/tmp/goal-append/{slug}");
    let candidate_path = default_candidate_path_for_slug(&slug);
    CandidatePaths {
        hermes_output_dir,
        goal_append_output_dir,
        candidate_path,
    }
}

fn default_candidate_path_for_slug(slug: &str) -> String {
    format!(".agent/tmp/hermes-planner-provider/{slug}/candidates/{DEFAULT_CANDIDATE_GOAL_ID}.md")
}

fn output_slug(output_dir: &Path) -> String {
    let normalized = output_dir.to_string_lossy().replace('\\', "/");
    if normalized.trim_end_matches('/') == ".agent/tmp/operator-tui/candidate-flow" {
        return "operator-tui-candidate-flow".to_string();
    }

    let mut slug = normalized
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' {
                ch
            } else {
                '_'
            }
        })
        .collect::<String>()
        .trim_matches('_')
        .to_string();
    if slug.is_empty() {
        slug = "operator-tui-candidate-flow".to_string();
    }
    if slug.len() > 96 {
        slug.truncate(96);
    }
    slug
}

fn block(state: &mut CandidateState, reason: impl Into<String>) {
    let reason = reason.into();
    if !state.validation_blockers.contains(&reason) {
        state.validation_blockers.push(reason);
    }
    state.validation_result = "blocked".to_string();
    state.token_printed = false;
}

fn push_unique(values: &mut Vec<String>, value: &str) {
    if !values.iter().any(|existing| existing == value) {
        values.push(value.to_string());
    }
}

fn bool_prop(value: &Value, name: &str) -> bool {
    value.get(name).and_then(Value::as_bool).unwrap_or(false)
}

fn string_prop(value: &Value, name: &str) -> Option<String> {
    value
        .get(name)
        .and_then(Value::as_str)
        .map(ToString::to_string)
}

fn string_array_prop(value: &Value, name: &str) -> Vec<String> {
    value
        .get(name)
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn render_generated_candidate_reference(candidate: &CandidateState) -> String {
    format!(
        "# Generated Candidate Reference\n\n- schema: {}\n- candidate_source: {}\n- candidate_path: {}\n- candidate_hash: {}\n- candidate_title: {}\n- candidate_goal_id: {}\n- raw_candidate_content_duplicated: false\n- review_required: {}\n- execution_started: false\n- task_created: false\n- task_claimed: false\n- branch_created: false\n- pr_created: false\n- token_printed: false\n",
        CANDIDATE_STATE_SCHEMA,
        candidate.candidate_source,
        candidate.candidate_path,
        candidate.candidate_hash,
        candidate.candidate_title,
        candidate.candidate_goal_id,
        candidate.review_required
    )
}

fn render_candidate_report_markdown(report: &CandidateFlowReport) -> String {
    let active = report
        .active_actions
        .iter()
        .map(|action| action.action)
        .collect::<Vec<_>>()
        .join(", ");
    let disabled = report
        .disabled_actions
        .iter()
        .map(|action| format!("{} ({})", action.action, action.disabled_reasons.join(", ")))
        .collect::<Vec<_>>()
        .join("\n- ");

    format!(
        "# Operator TUI MG368C Candidate Flow Report\n\n- schema: {}\n- mode: {}\n- local_state_loaded: {}\n- cloud_state_loaded: {}\n- cloud_parity_shown: {}\n- candidate_generated: {}\n- candidate_validated: {}\n- candidate_reviewed: {}\n- candidate_approved_for_append: {}\n- append_previewed: {}\n- append_performed: {}\n- appended_step_id: {}\n- appended_campaign_id: {}\n- panels_rendered: {}\n- active_actions: {}\n- disabled_actions:\n- {}\n- mutation_attempted: {}\n- append_attempted: {}\n- approval_attempted: {}\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- branch_created: false\n- pr_created: false\n- merge_performed: false\n- deploy_triggered: false\n- worker_loop_started: false\n- queue_runner_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- token_printed: false\n",
        report.schema,
        report.mode,
        report.local_state_loaded,
        report.cloud_state_loaded,
        report.cloud_parity_shown,
        report.candidate_generated,
        report.candidate_validated,
        report.candidate_reviewed,
        report.candidate_approved_for_append,
        report.append_previewed,
        report.append_performed,
        report.appended_step_id,
        report.appended_campaign_id,
        report.panels_rendered.join(", "),
        active,
        disabled,
        report.mutation_attempted,
        report.append_attempted,
        report.approval_attempted
    )
}

fn write_text(path: &Path, text: &str) -> anyhow::Result<()> {
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

fn now_utc() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}
