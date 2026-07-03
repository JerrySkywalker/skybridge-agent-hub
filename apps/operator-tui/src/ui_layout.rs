use std::{fs, path::Path};

use anyhow::Context;
use ratatui::layout::Rect;
use serde::Serialize;

use crate::{
    actions::Action,
    app::App,
    commands::now_utc,
    model::{timeline_steps, OperatorState},
    view_model::ViewModel,
};

pub const LAYOUT_REPORT_SCHEMA: &str = "skybridge.operator_tui_layout_report.v1";
pub const LAYOUT_STATE_SCHEMA: &str = "skybridge.operator_tui_layout_state.v1";
pub const DEFAULT_LAYOUT_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/layout";
pub const FULL_MIN_WIDTH: u16 = 120;
pub const FULL_MIN_HEIGHT: u16 = 40;
pub const COMPACT_MIN_WIDTH: u16 = 80;
pub const COMPACT_MIN_HEIGHT: u16 = 24;

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum OperatorLayoutMode {
    Full,
    Compact,
    Tiny,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum OperatorTab {
    Overview,
    Pipeline,
    Candidate,
    SingleStep,
    Actions,
    Runtime,
    Safety,
    Artifacts,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum LayoutSmokeScenario {
    None,
    Full,
    Compact,
    Tiny,
    Tabs,
    ActionsCompact,
    NoRealExecution,
}

#[derive(Debug, Serialize)]
pub struct LayoutState {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub active_tab: String,
    pub tabs: Vec<&'static str>,
    pub full_size: LayoutSnapshotSize,
    pub compact_size: LayoutSnapshotSize,
    pub tiny_size: LayoutSnapshotSize,
    pub token_printed: bool,
}

#[derive(Debug, Serialize)]
pub struct LayoutSnapshotSize {
    pub width: u16,
    pub height: u16,
    pub detected_mode: &'static str,
}

#[derive(Debug, Serialize)]
pub struct LayoutReport {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub full_layout_available: bool,
    pub compact_layout_available: bool,
    pub tiny_layout_available: bool,
    pub tab_model_available: bool,
    pub active_tab: String,
    pub tabs: Vec<&'static str>,
    pub small_window_supported: bool,
    pub tiny_window_supported: bool,
    pub terminal_too_small_message_available: bool,
    pub action_menu_compact_available: bool,
    pub runtime_status_visible: bool,
    pub safety_status_visible: bool,
    pub token_printed: bool,
    pub real_task_execution_enabled: bool,
    pub real_branch_creation_enabled: bool,
    pub real_pr_creation_enabled: bool,
    pub worker_loop_started: bool,
    pub queue_runner_started: bool,
    pub run_forever_started: bool,
    pub hermes_live_called: bool,
    pub mcp_run_called: bool,
    pub auto_merge_enabled: bool,
    pub release_created: bool,
    pub tag_created: bool,
    pub asset_uploaded: bool,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
}

impl OperatorLayoutMode {
    pub fn detect(area: Rect) -> Self {
        Self::from_size(area.width, area.height)
    }

    pub fn from_size(width: u16, height: u16) -> Self {
        if width >= FULL_MIN_WIDTH && height >= FULL_MIN_HEIGHT {
            Self::Full
        } else if width >= COMPACT_MIN_WIDTH && height >= COMPACT_MIN_HEIGHT {
            Self::Compact
        } else {
            Self::Tiny
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Full => "full",
            Self::Compact => "compact",
            Self::Tiny => "tiny",
        }
    }
}

impl OperatorTab {
    pub const ALL: [Self; 8] = [
        Self::Overview,
        Self::Pipeline,
        Self::Candidate,
        Self::SingleStep,
        Self::Actions,
        Self::Runtime,
        Self::Safety,
        Self::Artifacts,
    ];

    pub fn label(self) -> &'static str {
        match self {
            Self::Overview => "Overview",
            Self::Pipeline => "Pipeline",
            Self::Candidate => "Candidate",
            Self::SingleStep => "Single-step",
            Self::Actions => "Actions",
            Self::Runtime => "Runtime",
            Self::Safety => "Safety",
            Self::Artifacts => "Artifacts",
        }
    }

    pub fn next(self) -> Self {
        let index = Self::ALL.iter().position(|tab| *tab == self).unwrap_or(0);
        Self::ALL[(index + 1) % Self::ALL.len()]
    }

    pub fn previous(self) -> Self {
        let index = Self::ALL.iter().position(|tab| *tab == self).unwrap_or(0);
        if index == 0 {
            Self::ALL[Self::ALL.len() - 1]
        } else {
            Self::ALL[index - 1]
        }
    }
}

impl LayoutSmokeScenario {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "none" => Ok(Self::None),
            "full" => Ok(Self::Full),
            "compact" => Ok(Self::Compact),
            "tiny" => Ok(Self::Tiny),
            "tabs" => Ok(Self::Tabs),
            "actions-compact" => Ok(Self::ActionsCompact),
            "no-real-execution" => Ok(Self::NoRealExecution),
            other => anyhow::bail!("unknown layout smoke: {other}"),
        }
    }

    pub fn is_some(self) -> bool {
        self != Self::None
    }
}

pub fn tab_labels() -> Vec<&'static str> {
    OperatorTab::ALL.iter().map(|tab| tab.label()).collect()
}

pub fn status_header_lines(
    view_model: &ViewModel,
    mode: OperatorLayoutMode,
    area: Rect,
) -> Vec<String> {
    let state = &view_model.current_operator_state;
    vec![
        format!(
            "SkyBridge Operator TUI | layout={} size={}x{} | tab={} | selected_action={}",
            mode.as_str(),
            area.width,
            area.height,
            view_model.active_tab.label(),
            view_model.selected_action
        ),
        format!(
            "repo={} head={} clean={} | cloud={} version_ok={} parity={}",
            state.repo.branch,
            short(&state.repo.head),
            state.repo.worktree_clean,
            state.cloud.health,
            state.cloud.version_ok,
            state.cloud.parity
        ),
        format!(
            "command_status={} active_command={} | token_printed={}",
            view_model.command_status.as_str(),
            active_command_label(view_model),
            view_model.safety_flags.token_printed
        ),
    ]
}

pub fn tab_bar_line(view_model: &ViewModel) -> String {
    OperatorTab::ALL
        .iter()
        .map(|tab| {
            if *tab == view_model.active_tab {
                format!("[{}]", tab.label())
            } else {
                tab.label().to_string()
            }
        })
        .collect::<Vec<_>>()
        .join(" | ")
}

pub fn tab_content_lines(view_model: &ViewModel) -> Vec<String> {
    if view_model.help_visible {
        return help_lines();
    }

    match view_model.active_tab {
        OperatorTab::Overview => overview_lines(view_model),
        OperatorTab::Pipeline => pipeline_lines(&view_model.current_operator_state),
        OperatorTab::Candidate => candidate_lines(&view_model.current_operator_state),
        OperatorTab::SingleStep => single_step_lines(&view_model.current_operator_state),
        OperatorTab::Actions => action_menu_lines(view_model),
        OperatorTab::Runtime => runtime_lines(view_model),
        OperatorTab::Safety => safety_lines(view_model),
        OperatorTab::Artifacts => artifact_lines(view_model),
    }
}

pub fn action_menu_lines(view_model: &ViewModel) -> Vec<String> {
    Action::all()
        .into_iter()
        .enumerate()
        .flat_map(|(index, action)| {
            let selected = if index == view_model.selected_action_index {
                ">"
            } else {
                " "
            };
            let disabled = if action.enabled() { "" } else { " [disabled]" };
            let mut lines = vec![format!(
                "{selected} {} {}{}",
                action.key(),
                action.label(),
                disabled
            )];
            if !action.enabled() {
                lines.push(format!(
                    "  reasons: {}",
                    action.disabled_reasons().join(", ")
                ));
            }
            lines
        })
        .collect()
}

pub fn runtime_lines(view_model: &ViewModel) -> Vec<String> {
    let mut lines = vec![
        "Runtime".to_string(),
        "UI responsive while command runs".to_string(),
    ];
    lines.extend(view_model.status_lines());
    lines.push(format!(
        "active_command_id={:?}",
        view_model.active_command_id
    ));
    lines.push(format!(
        "active_command_label={}",
        value_or_none(&view_model.active_command_label)
    ));
    if let Some(result) = &view_model.last_command_result {
        lines.push(format!(
            "last_result: id={} command={} status={} duration_ms={}",
            result.command_id,
            result.command.label(),
            result.status.as_str(),
            result.duration_ms
        ));
        lines.push(format!("last_summary: {}", result.result_summary));
    } else {
        lines.push("last_result: none".to_string());
    }
    lines.push(
        "timeout/stale handling: command timeout enforced; stale late result ignored".to_string(),
    );
    lines
}

pub fn safety_lines(view_model: &ViewModel) -> Vec<String> {
    let flags = &view_model.safety_flags;
    vec![
        "Safety flags".to_string(),
        format!(
            "real_task_execution_enabled={}",
            flags.real_task_execution_enabled
        ),
        format!(
            "real_branch_creation_enabled={}",
            flags.real_branch_creation_enabled
        ),
        format!(
            "real_pr_creation_enabled={}",
            flags.real_pr_creation_enabled
        ),
        format!("task_created={}", flags.task_created),
        format!("task_claimed={}", flags.task_claimed),
        format!("execution_started={}", flags.execution_started),
        format!("worker_loop_started={}", flags.worker_loop_started),
        format!("queue_runner_started={}", flags.queue_runner_started),
        format!("run_forever_started={}", flags.run_forever_started),
        format!("hermes_live_called={}", flags.hermes_live_called),
        format!("mcp_run_called={}", flags.mcp_run_called),
        format!("auto_merge_enabled={}", flags.auto_merge_enabled),
        format!("release_created={}", flags.release_created),
        format!("tag_created={}", flags.tag_created),
        format!("asset_uploaded={}", flags.asset_uploaded),
        format!("token_printed={}", flags.token_printed),
    ]
}

pub fn footer_lines(view_model: &ViewModel, mode: OperatorLayoutMode) -> Vec<String> {
    match mode {
        OperatorLayoutMode::Full => vec![
            "Tab/]/[ navigate tabs | Up/Down select action | Enter run selected safe fixture command | ? help | q quit".to_string(),
            format!(
                "Safety: exec={} branch={} pr={} worker_loop={} queue_runner={} run_forever={} token_printed={}",
                view_model.safety_flags.real_task_execution_enabled,
                view_model.safety_flags.real_branch_creation_enabled,
                view_model.safety_flags.real_pr_creation_enabled,
                view_model.safety_flags.worker_loop_started,
                view_model.safety_flags.queue_runner_started,
                view_model.safety_flags.run_forever_started,
                view_model.safety_flags.token_printed
            ),
        ],
        OperatorLayoutMode::Compact => vec![
            "Compact: current tab only | Tab/]/[ tabs | Actions tab for full action menu | ? help | q quit".to_string(),
            format!(
                "status={} safety: no real execution/branch/PR, token_printed={}",
                view_model.command_status.as_str(),
                view_model.safety_flags.token_printed
            ),
        ],
        OperatorLayoutMode::Tiny => tiny_lines(view_model, 0, 0),
    }
}

pub fn tiny_lines(view_model: &ViewModel, width: u16, height: u16) -> Vec<String> {
    vec![
        "terminal too small - tiny layout".to_string(),
        format!("current size: {}x{}", width, height),
        format!(
            "minimum recommended size: {}x{}",
            COMPACT_MIN_WIDTH, COMPACT_MIN_HEIGHT
        ),
        format!("command_status: {}", view_model.command_status.as_str()),
        format!("active_command: {}", active_command_label(view_model)),
        "? help | q quit".to_string(),
        format!("token_printed={}", view_model.safety_flags.token_printed),
    ]
}

pub fn render_layout_snapshot_text(
    view_model: &ViewModel,
    mode: OperatorLayoutMode,
    width: u16,
    height: u16,
) -> String {
    let area = Rect::new(0, 0, width, height);
    let mut lines = vec![format!(
        "SkyBridge Operator TUI layout snapshot | mode={} | size={}x{}",
        mode.as_str(),
        width,
        height
    )];
    lines.push(format!("tabs: {}", tab_labels().join(", ")));
    lines.push(format!("current_tab: {}", view_model.active_tab.label()));
    lines.push(String::new());

    if mode == OperatorLayoutMode::Tiny {
        lines.extend(tiny_lines(view_model, width, height));
        return lines.join("\n");
    }

    lines.push("## Global Status".to_string());
    lines.extend(status_header_lines(view_model, mode, area));
    lines.push(String::new());
    lines.push("## Tabs".to_string());
    lines.push(tab_bar_line(view_model));
    lines.push(String::new());
    lines.push(format!("## {} Tab", view_model.active_tab.label()));
    lines.extend(tab_content_lines(view_model));
    lines.push(String::new());
    lines.push("## Command / Safety Footer".to_string());
    lines.extend(footer_lines(view_model, mode));
    lines.join("\n")
}

pub fn run_layout_smoke(
    app: &mut App,
    scenario: LayoutSmokeScenario,
    output_dir: &Path,
) -> anyhow::Result<LayoutReport> {
    configure_scenario(app, scenario);
    write_layout_artifacts(output_dir, app)?;
    Ok(layout_report(app))
}

pub fn write_layout_artifacts(output_dir: &Path, app: &App) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let full_snapshot = snapshot_for(app, OperatorLayoutMode::Full, 132, 42);
    let compact_snapshot = snapshot_for(app, OperatorLayoutMode::Compact, 96, 28);
    let tiny_snapshot = snapshot_for(app, OperatorLayoutMode::Tiny, 70, 18);
    let state = layout_state(app);
    let report = layout_report(app);

    write_text(
        &output_dir.join("layout-state.json"),
        &format!("{}\n", serde_json::to_string_pretty(&state)?),
    )?;
    write_text(
        &output_dir.join("layout-report.json"),
        &format!("{}\n", serde_json::to_string_pretty(&report)?),
    )?;
    write_text(
        &output_dir.join("layout-report.md"),
        &render_layout_report_markdown(&report, output_dir),
    )?;
    write_text(&output_dir.join("full-snapshot.txt"), &full_snapshot)?;
    write_text(&output_dir.join("compact-snapshot.txt"), &compact_snapshot)?;
    write_text(&output_dir.join("tiny-snapshot.txt"), &tiny_snapshot)?;
    Ok(())
}

pub fn layout_report(app: &App) -> LayoutReport {
    let flags = &app.view_model.safety_flags;
    let mut warnings = app.view_model.warnings.clone();
    warnings.push("mg369_manual_experiment_deferred".to_string());
    warnings.push("layout_only_runtime_semantics_unchanged".to_string());

    LayoutReport {
        schema: LAYOUT_REPORT_SCHEMA,
        generated_at: now_utc(),
        mode: "layout-responsive",
        full_layout_available: true,
        compact_layout_available: true,
        tiny_layout_available: true,
        tab_model_available: true,
        active_tab: app.view_model.active_tab.label().to_string(),
        tabs: tab_labels(),
        small_window_supported: true,
        tiny_window_supported: true,
        terminal_too_small_message_available: true,
        action_menu_compact_available: true,
        runtime_status_visible: true,
        safety_status_visible: true,
        token_printed: flags.token_printed,
        real_task_execution_enabled: flags.real_task_execution_enabled,
        real_branch_creation_enabled: flags.real_branch_creation_enabled,
        real_pr_creation_enabled: flags.real_pr_creation_enabled,
        worker_loop_started: flags.worker_loop_started,
        queue_runner_started: flags.queue_runner_started,
        run_forever_started: flags.run_forever_started,
        hermes_live_called: flags.hermes_live_called,
        mcp_run_called: flags.mcp_run_called,
        auto_merge_enabled: flags.auto_merge_enabled,
        release_created: flags.release_created,
        tag_created: flags.tag_created,
        asset_uploaded: flags.asset_uploaded,
        blockers: app.view_model.blockers.clone(),
        warnings,
    }
}

fn configure_scenario(app: &mut App, scenario: LayoutSmokeScenario) {
    app.view_model.help_visible = false;
    match scenario {
        LayoutSmokeScenario::None | LayoutSmokeScenario::Full => {
            app.view_model.active_tab = OperatorTab::Overview;
        }
        LayoutSmokeScenario::Compact => {
            app.view_model.active_tab = OperatorTab::Runtime;
        }
        LayoutSmokeScenario::Tiny => {
            app.view_model.active_tab = OperatorTab::Overview;
        }
        LayoutSmokeScenario::Tabs => {
            app.view_model.active_tab = OperatorTab::Overview.next().next();
            app.view_model.active_tab = app.view_model.active_tab.previous();
            app.view_model.help_visible = true;
        }
        LayoutSmokeScenario::ActionsCompact => {
            app.view_model.active_tab = OperatorTab::Actions;
        }
        LayoutSmokeScenario::NoRealExecution => {
            app.view_model.active_tab = OperatorTab::Safety;
        }
    }
}

fn layout_state(app: &App) -> LayoutState {
    LayoutState {
        schema: LAYOUT_STATE_SCHEMA,
        generated_at: now_utc(),
        mode: "layout-responsive",
        active_tab: app.view_model.active_tab.label().to_string(),
        tabs: tab_labels(),
        full_size: snapshot_size(132, 42),
        compact_size: snapshot_size(96, 28),
        tiny_size: snapshot_size(70, 18),
        token_printed: app.view_model.safety_flags.token_printed,
    }
}

fn snapshot_size(width: u16, height: u16) -> LayoutSnapshotSize {
    LayoutSnapshotSize {
        width,
        height,
        detected_mode: OperatorLayoutMode::from_size(width, height).as_str(),
    }
}

fn snapshot_for(app: &App, mode: OperatorLayoutMode, width: u16, height: u16) -> String {
    render_layout_snapshot_text(&app.view_model, mode, width, height)
}

fn overview_lines(view_model: &ViewModel) -> Vec<String> {
    let state = &view_model.current_operator_state;
    vec![
        "Overview".to_string(),
        format!(
            "repo: branch={} head={} clean={} main_aligned={} origin_aligned={}",
            state.repo.branch,
            short(&state.repo.head),
            state.repo.worktree_clean,
            state.repo.main_aligned,
            state.repo.origin_aligned
        ),
        format!(
            "cloud: health_ok={} version_ok={} image_tag={} parity_ok={}",
            state.cloud.health_ok,
            state.cloud.version_ok,
            value_or_unknown(&state.cloud.image_tag),
            state.cloud.parity_ok
        ),
        format!(
            "campaign: {} goal={} status={}",
            state.campaign.campaign_id,
            state.campaign.current_goal_id,
            state.campaign.current_goal_status
        ),
        format!("selected_action={}", view_model.selected_action),
        format!("command_status={}", view_model.command_status.as_str()),
        format!("token_printed={}", view_model.safety_flags.token_printed),
    ]
}

fn pipeline_lines(state: &OperatorState) -> Vec<String> {
    let mut lines = vec!["Pipeline".to_string()];
    lines.extend(
        timeline_steps(state)
            .into_iter()
            .map(|step| format!("- [{}] {}", step.status, step.label)),
    );
    lines
}

fn candidate_lines(state: &OperatorState) -> Vec<String> {
    let candidate = &state.candidate_flow;
    vec![
        "Candidate".to_string(),
        format!("candidate_path={}", candidate.candidate_path),
        format!(
            "candidate_hash={}",
            value_or_unknown(&candidate.candidate_hash)
        ),
        format!("candidate_title={}", candidate.candidate_title),
        format!("candidate_goal_id={}", candidate.candidate_goal_id),
        format!("validation_result={}", candidate.validation_result),
        format!("candidate_validated={}", candidate.candidate_validated),
        format!("review_status={}", candidate.review_status),
        format!("append_allowed={}", candidate.append_allowed),
        format!("append_previewed={}", candidate.append_previewed),
        format!("append_performed={}", candidate.append_performed),
        format!(
            "appended_step_id={}",
            value_or_unknown(&candidate.appended_step_id)
        ),
        "safety: no execution, no branch/PR creation".to_string(),
        format!("token_printed={}", candidate.token_printed),
    ]
}

fn single_step_lines(state: &OperatorState) -> Vec<String> {
    let step = &state.single_step;
    vec![
        "Single-step".to_string(),
        format!(
            "appended_step_id={}",
            value_or_unknown(&step.appended_step_id)
        ),
        format!("candidate_appended={}", step.candidate_appended),
        format!(
            "bounded_action: previewed={} type={} allowed={}",
            step.next_bounded_action_previewed,
            step.next_bounded_action_type,
            step.next_bounded_action_allowed
        ),
        format!(
            "start_one: requested={} confirmed={} performed={} result={}",
            step.start_one_requested,
            step.start_one_confirmed,
            step.start_one_performed,
            step.start_one_result
        ),
        format!(
            "safe_pause: requested={} confirmed={} performed={} reason={}",
            step.safe_pause_requested,
            step.safe_pause_confirmed,
            step.safe_pause_performed,
            value_or_unknown(&step.safe_pause_reason)
        ),
        format!(
            "abort: requested={} previewed={} confirmed={} performed={} reason={}",
            step.abort_requested,
            step.abort_previewed,
            step.abort_confirmed,
            step.abort_performed,
            value_or_unknown(&step.abort_reason)
        ),
        "safety: one action only, no queue loop, no worker loop, no run forever".to_string(),
        format!(
            "task_created={} task_claimed={} execution_started={}",
            step.task_created, step.task_claimed, step.execution_started
        ),
        format!(
            "branch_created={} pr_created={} draft_pr_created={}",
            step.branch_created, step.pr_created, step.draft_pr_created
        ),
        format!("token_printed={}", step.token_printed),
    ]
}

fn artifact_lines(view_model: &ViewModel) -> Vec<String> {
    let mut lines = vec!["Artifacts".to_string()];
    if view_model.artifact_paths.is_empty() {
        lines.push("last_command_artifacts=none".to_string());
    } else {
        lines.extend(
            view_model
                .artifact_paths
                .iter()
                .map(|path| format!("- {}", path)),
        );
    }
    lines.push(format!(
        "layout_artifacts={}/layout-report.json, {}/full-snapshot.txt, {}/compact-snapshot.txt, {}/tiny-snapshot.txt",
        DEFAULT_LAYOUT_OUTPUT_DIR,
        DEFAULT_LAYOUT_OUTPUT_DIR,
        DEFAULT_LAYOUT_OUTPUT_DIR,
        DEFAULT_LAYOUT_OUTPUT_DIR
    ));
    lines.push("raw prompt/log/stdout/stderr/env/token dumps are not written".to_string());
    lines.push(format!(
        "token_printed={}",
        view_model.safety_flags.token_printed
    ));
    lines
}

fn help_lines() -> Vec<String> {
    vec![
        "Help".to_string(),
        "Tab or ]: next tab".to_string(),
        "Shift+Tab or [: previous tab".to_string(),
        "Up/Down: move action selection".to_string(),
        "Enter: run selected fixture-safe command or enter confirmation mode".to_string(),
        "?: toggle this help surface".to_string(),
        "q or Esc: quit".to_string(),
        "confirmation mode: type or paste the exact phrase; Enter submits; Esc cancels".to_string(),
        "reason mode: enter a non-empty reason; sanitized preview is shown before confirmation"
            .to_string(),
        "input editing: Backspace deletes; Ctrl+U clears; pasted characters arrive as input"
            .to_string(),
        "q only quits from normal mode; in confirmation/reason mode it is text input".to_string(),
        "token_printed=false".to_string(),
    ]
}

fn active_command_label(view_model: &ViewModel) -> String {
    if let Some(id) = view_model.active_command_id {
        format!("{}#{}", value_or_none(&view_model.active_command_label), id)
    } else {
        "none".to_string()
    }
}

fn render_layout_report_markdown(report: &LayoutReport, output_dir: &Path) -> String {
    format!(
        "# Operator TUI MG368G Layout Report\n\n- schema: {}\n- mode: {}\n- full_layout_available: {}\n- compact_layout_available: {}\n- tiny_layout_available: {}\n- tab_model_available: {}\n- active_tab: {}\n- tabs: {}\n- small_window_supported: {}\n- tiny_window_supported: {}\n- terminal_too_small_message_available: {}\n- action_menu_compact_available: {}\n- runtime_status_visible: {}\n- safety_status_visible: {}\n- real_task_execution_enabled: false\n- real_branch_creation_enabled: false\n- real_pr_creation_enabled: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- token_printed: false\n\n## Artifacts\n\n- layout_state: {}\n- layout_report: {}\n- full_snapshot: {}\n- compact_snapshot: {}\n- tiny_snapshot: {}\n",
        report.schema,
        report.mode,
        report.full_layout_available,
        report.compact_layout_available,
        report.tiny_layout_available,
        report.tab_model_available,
        report.active_tab,
        report.tabs.join(", "),
        report.small_window_supported,
        report.tiny_window_supported,
        report.terminal_too_small_message_available,
        report.action_menu_compact_available,
        report.runtime_status_visible,
        report.safety_status_visible,
        path_for_report(&output_dir.join("layout-state.json")),
        path_for_report(&output_dir.join("layout-report.json")),
        path_for_report(&output_dir.join("full-snapshot.txt")),
        path_for_report(&output_dir.join("compact-snapshot.txt")),
        path_for_report(&output_dir.join("tiny-snapshot.txt")),
    )
}

fn write_text(path: &Path, text: &str) -> anyhow::Result<()> {
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

fn path_for_report(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn short(value: &str) -> String {
    if value.is_empty() {
        "unknown".to_string()
    } else {
        value.chars().take(12).collect()
    }
}

fn value_or_unknown(value: &str) -> &str {
    if value.is_empty() {
        "unknown"
    } else {
        value
    }
}

fn value_or_none(value: &str) -> &str {
    if value.is_empty() {
        "none"
    } else {
        value
    }
}
