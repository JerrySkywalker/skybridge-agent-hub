use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

use crate::{
    actions::Action,
    app::App,
    model::{timeline_steps, OperatorState},
};

pub const PANELS: [&str; 5] = [
    "Header / Global Status",
    "Pipeline Timeline",
    "Current Object",
    "Action Menu",
    "Safety Footer",
];

pub fn draw(frame: &mut Frame<'_>, app: &App) {
    let outer = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(9),
            Constraint::Min(10),
            Constraint::Length(11),
            Constraint::Length(12),
            Constraint::Length(5),
        ])
        .split(frame.area());

    draw_header(frame, outer[0], &app.state);
    draw_timeline(frame, outer[1], &app.state);
    draw_current_object(frame, outer[2], &app.state);
    draw_action_menu(frame, outer[3]);
    draw_safety_footer(frame, outer[4], &app.state);
}

pub fn render_snapshot_text(state: &OperatorState) -> String {
    let mut lines = Vec::new();

    lines.push(format!(
        "SkyBridge Operator Console - MG368C Candidate Review/Append Snapshot ({})",
        state.mode
    ));
    lines.push("".to_string());
    lines.push(format!("## {}", PANELS[0]));
    lines.extend(header_lines(state));
    lines.push("".to_string());

    lines.push(format!("## {}", PANELS[1]));
    for step in timeline_steps(state) {
        lines.push(format!("- [{}] {}", step.status, step.label));
    }
    lines.push("".to_string());

    lines.push(format!("## {}", PANELS[2]));
    lines.extend(current_object_lines(state));
    lines.push("".to_string());

    lines.push(format!("## {}", PANELS[3]));
    for action in Action::all() {
        let suffix = if action.enabled() {
            ""
        } else {
            " [disabled until MG368D]"
        };
        lines.push(format!("- {} {}{}", action.key(), action.label(), suffix));
        if !action.enabled() {
            lines.push(format!(
                "  reasons: {}",
                action.disabled_reasons().join(", ")
            ));
        }
    }
    lines.push("".to_string());

    lines.push(format!("## {}", PANELS[4]));
    lines.extend(safety_footer_lines(state));
    lines.push("".to_string());

    lines.join("\n")
}

pub fn render_report_markdown(app: &App, snapshot_path: &str, state_path: &str) -> String {
    let report = app.report(false);
    let disabled = report
        .disabled_actions
        .iter()
        .map(|action| format!("{} ({})", action.action, action.disabled_reasons.join(", ")))
        .collect::<Vec<_>>()
        .join("\n- ");
    let active = report
        .active_actions
        .iter()
        .map(|action| action.action)
        .collect::<Vec<_>>()
        .join(", ");

    format!(
        "# Operator TUI MG368B Snapshot Report\n\n- schema: {}\n- mode: {}\n- fixture_used: {}\n- local_state_loaded: {}\n- cloud_state_loaded: {}\n- local_cloud_parity_checked: {}\n- interactive_started: {}\n- snapshot: {}\n- state: {}\n- panels_rendered: {}\n- active_actions: {}\n- disabled_actions:\n- {}\n- mutation_attempted: false\n- append_attempted: false\n- approval_attempted: false\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- worker_loop_started: false\n- queue_runner_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- token_printed: false\n",
        report.schema,
        report.mode,
        report.fixture_used,
        report.local_state_loaded,
        report.cloud_state_loaded,
        report.local_cloud_parity_checked,
        report.interactive_started,
        snapshot_path,
        state_path,
        report.panels_rendered.join(", "),
        active,
        disabled
    )
}

fn draw_header(frame: &mut Frame<'_>, area: Rect, state: &OperatorState) {
    let paragraph = Paragraph::new(header_lines(state).join("\n"))
        .block(panel_block(PANELS[0]))
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, area);
}

fn draw_timeline(frame: &mut Frame<'_>, area: Rect, state: &OperatorState) {
    let items = timeline_steps(state)
        .into_iter()
        .map(|step| {
            let color = match step.status {
                "done" => Color::Green,
                "ready" => Color::Yellow,
                "blocked" => Color::Red,
                _ => Color::Gray,
            };
            ListItem::new(Line::from(vec![
                Span::styled(format!("[{}] ", step.status), Style::default().fg(color)),
                Span::raw(step.label),
            ]))
        })
        .collect::<Vec<_>>();
    let list = List::new(items).block(panel_block(PANELS[1]));
    frame.render_widget(list, area);
}

fn draw_current_object(frame: &mut Frame<'_>, area: Rect, state: &OperatorState) {
    let paragraph = Paragraph::new(current_object_lines(state).join("\n"))
        .block(panel_block(PANELS[2]))
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, area);
}

fn draw_action_menu(frame: &mut Frame<'_>, area: Rect) {
    let items = Action::all()
        .into_iter()
        .map(|action| {
            let disabled = !action.enabled();
            let mut label = format!("{} {}", action.key(), action.label());
            if disabled {
                label.push_str(" [disabled until MG368D]");
            }
            let style = if disabled {
                Style::default().fg(Color::DarkGray)
            } else {
                Style::default().fg(Color::Cyan)
            };
            ListItem::new(Line::from(Span::styled(label, style)))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(panel_block(PANELS[3])), area);
}

fn draw_safety_footer(frame: &mut Frame<'_>, area: Rect, state: &OperatorState) {
    let paragraph = Paragraph::new(safety_footer_lines(state).join("\n"))
        .block(panel_block(PANELS[4]))
        .style(
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        )
        .wrap(Wrap { trim: true });
    frame.render_widget(paragraph, area);
}

fn panel_block(title: &'static str) -> Block<'static> {
    Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
}

fn header_lines(state: &OperatorState) -> Vec<String> {
    vec![
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
            "cloud detail: commit={} parity={} missing_routes={}",
            short(&state.cloud.commit_sha),
            state.cloud.parity,
            state.cloud.missing_routes.len()
        ),
        format!(
            "sources: local={} cloud={} read_only={}",
            state.local_state_source, state.cloud_state_source, state.read_only
        ),
        format!(
            "freshness: local_age_seconds={} cloud_age_seconds={}",
            format_age(state.status_freshness.local_age_seconds),
            format_age(state.status_freshness.cloud_age_seconds)
        ),
        format!(
            "worker: id={} local={} remote={} stale={}",
            state.worker.worker_id,
            state.worker.local_status,
            state.worker.remote_status,
            state.worker.stale
        ),
        format!(
            "campaign: {} goal={} status={}",
            state.campaign.campaign_id,
            state.campaign.current_goal_id,
            state.campaign.current_goal_status
        ),
        format!("token_printed={}", state.safety.token_printed),
    ]
}

fn current_object_lines(state: &OperatorState) -> Vec<String> {
    if state.mode == "candidate-flow" {
        let candidate = &state.candidate_flow;
        return vec![
            "Candidate review/append flow".to_string(),
            format!("candidate_path: {}", candidate.candidate_path),
            format!(
                "candidate_hash: {}",
                value_or_unknown(&candidate.candidate_hash)
            ),
            format!("candidate_title: {}", candidate.candidate_title),
            format!("candidate_goal_id: {}", candidate.candidate_goal_id),
            format!("validation_result: {}", candidate.validation_result),
            format!("validated: {}", candidate.candidate_validated),
            format!("review_status: {}", candidate.review_status),
            format!("append_allowed: {}", candidate.append_allowed),
            format!("append_previewed: {}", candidate.append_previewed),
            format!("append_performed: {}", candidate.append_performed),
            format!(
                "appended_step_id: {}",
                value_or_unknown(&candidate.appended_step_id)
            ),
            "safety: no execution, no task claim, no branch/PR creation".to_string(),
            format!("token_printed={}", candidate.token_printed),
        ];
    }

    if state.mode == "fixture" {
        return vec![
            "Hermes candidate summary".to_string(),
            format!("candidate_path: {}", state.hermes_candidate.candidate_path),
            format!("candidate_hash: {}", state.hermes_candidate.candidate_hash),
            format!(
                "validated: {}",
                if state.hermes_candidate.candidate_validated {
                    "yes"
                } else {
                    "no"
                }
            ),
            format!(
                "approved/appended: {}/{}",
                state.hermes_candidate.candidate_approved,
                state.hermes_candidate.candidate_appended
            ),
        ];
    }

    vec![
        "Read-only local/cloud monitor".to_string(),
        format!(
            "local: branch={} head={} root={} package_manager={}",
            state.repo.branch,
            short(&state.repo.head),
            state.repo.repository_root,
            state.repo.package_manager_marker
        ),
        format!(
            "main: local={} origin={} aligned={}",
            short(&state.repo.local_main_commit),
            short(&state.repo.origin_main_commit),
            state.repo.main_aligned
        ),
        format!(
            "git_status: clean={} summary={}",
            state.repo.worktree_clean,
            state.repo.git_status_summary.join(" | ")
        ),
        format!(
            "cloud: health_ok={} version_ok={} commit={} image_tag={} parity_ok={}",
            state.cloud.health_ok,
            state.cloud.version_ok,
            short(&state.cloud.commit_sha),
            value_or_unknown(&state.cloud.image_tag),
            state.cloud.parity_ok
        ),
        format!(
            "stage close: baseline={} image={}",
            short(&state.stage_close.baseline_commit),
            state.stage_close.baseline_image_ref
        ),
        format!("tracked warning: {}", state.stage_close.tracked_warning),
        format!("resolved warning: {}", state.stage_close.resolved_warning),
        "candidate flow enabled in MG368C; execution disabled until MG368D".to_string(),
    ]
}

fn safety_footer_lines(state: &OperatorState) -> Vec<String> {
    if state.mode == "candidate-flow" {
        return vec![
            "CANDIDATE REVIEW/APPEND ONLY | no execution | no task claim".to_string(),
            "no worker loop | no branch/PR creation | no Hermes live | no MCP".to_string(),
            format!("token_printed={}", state.candidate_flow.token_printed),
        ];
    }

    vec![
        format!(
            "READ ONLY LOCAL/CLOUD MONITOR | mode={} | no mutation",
            state.mode
        ),
        format!(
            "no worker loop={} | no task claim={} | no Hermes live={} | no MCP={}",
            !state.safety.worker_loop_started,
            !state.safety.task_claimed,
            !state.safety.hermes_live_called,
            !state.safety.mcp_run_called
        ),
        format!("token_printed={}", state.safety.token_printed),
    ]
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

fn format_age(value: Option<u64>) -> String {
    value
        .map(|seconds| seconds.to_string())
        .unwrap_or_else(|| "not_loaded".to_string())
}
