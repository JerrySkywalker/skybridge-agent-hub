use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager};

const PROJECT_ID: &str = "skybridge-agent-hub";
const CAMPAIGN_ID: &str = "dev-queue-189-200";
const WORKER_ID: &str = "laptop-zenbookduo";
const GOAL_190_ID: &str = "super-190-campaign-run-report-evidence-ledger";
const GOAL_189_ID: &str = "super-189-ci-guardian-pr-finalizer-hardening";
const COMMAND_TIMEOUT_SECONDS: u64 = 30;
const BRIDGE_RESULT_TIMEOUT_SECONDS: u64 = COMMAND_TIMEOUT_SECONDS + 5;

#[derive(Debug, Serialize, Deserialize)]
struct DesktopStatus {
    ok: bool,
    mode_banner: String,
    mutation_scope: String,
    execution_disabled: bool,
    project_id: String,
    campaign_id: String,
    worker_id: String,
    worker_status: String,
    current_step: String,
    current_goal_id: String,
    current_goal_status: String,
    current_goal_linked_task_ids: Vec<String>,
    current_goal_linked_pr_urls: Vec<String>,
    previous_goal_id: String,
    previous_goal_status: String,
    goal_190_linked_task_ids_count: i64,
    goal_190_linked_pr_urls_count: i64,
    active_tasks: Option<i64>,
    stale_leases: Option<i64>,
    token_printed: bool,
    last_refresh_time: String,
    status_age_seconds: i64,
    pre190_readiness: Pre190Readiness,
    operator_readiness: Pre190Readiness,
    campaign_report: Value,
    worker_service_state: Value,
    safe_summary: Value,
    bridge_outcomes: Vec<BridgeOutcome>,
    report_cached: bool,
    report_age_seconds: i64,
    status_file: String,
    log_file: String,
    report_file: String,
    warnings: Vec<String>,
    errors: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Pre190Readiness {
    state: String,
    reasons: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct BridgeOutcome {
    name: String,
    ok: bool,
    warning: Option<String>,
}

struct BridgeResults {
    active: Result<Value, String>,
    campaign: Result<Value, String>,
    worker: Result<Value, String>,
    report: Result<Value, String>,
}

#[derive(Debug, Serialize)]
struct HeartbeatResult {
    ok: bool,
    token_printed: bool,
    worker_status: String,
    current_task_id: Option<String>,
    last_seen: Option<String>,
    status: DesktopStatus,
}

#[tauri::command]
async fn get_status(app: AppHandle, request_id: Option<String>) -> Result<DesktopStatus, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let mut status = collect_status(&app)?;
        if let Some(id) = request_id {
            status
                .warnings
                .push(format!("refresh_request_id={id}"));
        }
        Ok(status)
    })
    .await
    .map_err(|err| format!("desktop refresh task failed: {err}"))?
}

#[tauri::command]
fn heartbeat_now(app: AppHandle) -> Result<HeartbeatResult, String> {
    append_log(&app, "heartbeat-only register-heartbeat requested")?;
    let output = run_worker_status(&["-Command", "register-heartbeat", "-Json"])?;
    let heartbeat_json = parse_json(&output)?;
    let status = collect_status(&app)?;
    Ok(HeartbeatResult {
        ok: heartbeat_json
            .get("ok")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        token_printed: heartbeat_json
            .get("token_printed")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        worker_status: get_string(&heartbeat_json, &["remote_status"]).unwrap_or_else(|| "unknown".into()),
        current_task_id: get_string(&heartbeat_json, &["current_task_id"]),
        last_seen: get_string(&heartbeat_json, &["last_seen"]),
        status,
    })
}

#[tauri::command]
fn open_report(_app: AppHandle) -> Result<(), String> {
    let report_file = report_file_path()?;
    let safe_root = campaign_reports_dir()?;
    if !report_file.starts_with(&safe_root) {
        return Err("report path is outside the safe campaign report artifact directory".into());
    }
    if !report_file.exists() {
        return Err("campaign report artifact is missing; use Refresh to generate it in the background".into());
    }
    #[cfg(target_os = "windows")]
    {
        Command::new("explorer")
            .arg(&report_file)
            .spawn()
            .map_err(|err| err.to_string())?;
    }
    #[cfg(not(target_os = "windows"))]
    {
        Command::new("xdg-open")
            .arg(&report_file)
            .spawn()
            .map_err(|err| err.to_string())?;
    }
    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            build_tray(app.handle())?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_status, heartbeat_now, open_report])
        .run(tauri::generate_context!())
        .expect("error while running SkyBridge Desktop");
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "Open SkyBridge", true, None::<&str>)?;
    let refresh = MenuItem::with_id(app, "refresh", "Refresh Status", true, None::<&str>)?;
    let logs = MenuItem::with_id(app, "logs", "Open Logs", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open, &refresh, &logs, &quit])?;

    TrayIconBuilder::with_id("skybridge-desktop")
        .tooltip("SkyBridge Desktop")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => {
                show_main_window(app);
            }
            "refresh" => {
                let refresh_app = app.clone();
                tauri::async_runtime::spawn_blocking(move || {
                    let _ = collect_status(&refresh_app);
                });
                show_main_window(&app);
            }
            "logs" => {
                let _ = open_logs_dir(app);
            }
            "quit" => {
                app.exit(0);
            }
            _ => {}
        })
        .icon(default_icon())
        .build(app)?;
    Ok(())
}

fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn open_logs_dir(app: &AppHandle) -> Result<(), String> {
    let logs = desktop_dir(app).join("logs");
    fs::create_dir_all(&logs).map_err(|err| err.to_string())?;
    #[cfg(target_os = "windows")]
    {
        Command::new("explorer")
            .arg(&logs)
            .spawn()
            .map_err(|err| err.to_string())?;
    }
    #[cfg(not(target_os = "windows"))]
    {
        Command::new("xdg-open")
            .arg(&logs)
            .spawn()
            .map_err(|err| err.to_string())?;
    }
    Ok(())
}

fn collect_status(app: &AppHandle) -> Result<DesktopStatus, String> {
    append_log(app, "status refresh requested")?;
    let errors = Vec::new();
    let mut warnings = Vec::new();
    let bridge = collect_bridge_results();
    let mut bridge_outcomes = Vec::new();

    let active_json = bridge_value("status", bridge.active, &mut bridge_outcomes, &mut warnings);
    let campaign_json = bridge_value("campaign_status", bridge.campaign, &mut bridge_outcomes, &mut warnings);
    let worker_json = bridge_value("worker_status", bridge.worker, &mut bridge_outcomes, &mut warnings);
    let report_json = bridge_value("campaign_report", bridge.report, &mut bridge_outcomes, &mut warnings);

    detect_token_printed("active status", &active_json, &mut warnings);
    detect_token_printed("campaign status", &campaign_json, &mut warnings);
    detect_token_printed("worker status", &worker_json, &mut warnings);
    detect_token_printed("campaign report", &report_json, &mut warnings);

    let current_step_id = get_string(&campaign_json, &["campaign", "current_step_id"]).unwrap_or_else(|| "unknown".into());
    let steps = campaign_json
        .get("steps")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let current_step = steps
        .iter()
        .find(|step| get_string(step, &["campaign_step_id"]).as_deref() == Some(current_step_id.as_str()));
    let previous_step = steps
        .iter()
        .find(|step| get_string(step, &["goal_id"]).as_deref() == Some(GOAL_189_ID));
    let current_goal_id = current_step
        .and_then(|step| get_string(step, &["goal_id"]))
        .unwrap_or_else(|| "unknown".into());
    let current_goal_status = current_step
        .and_then(|step| get_string(step, &["status"]))
        .unwrap_or_else(|| "unknown".into());
    let linked_task_ids = current_step.map_or_else(Vec::new, |step| get_string_array(step, &["linked_task_ids"]));
    let linked_pr_urls = current_step.map_or_else(Vec::new, |step| get_string_array(step, &["linked_pr_urls"]));
    let active_tasks = get_i64(&active_json, &["task_summary", "active"]);
    let stale_leases = get_i64(&active_json, &["task_summary", "stale_leases"]);
    let token_printed = warnings.iter().any(|warning| warning.contains("token_printed=true"));
    let mut report_cached = false;
    let campaign_report = match report_json.get("report").cloned() {
        Some(value) => value,
        None => match read_cached_campaign_report(app) {
            Some(value) => {
                report_cached = true;
                warnings.push("campaign_report_cached_after_refresh_failure".into());
                value
            }
            None => Value::Null,
        },
    };
    let safe_summary = build_safe_summary(&campaign_report);
    let worker_service_state = campaign_report
        .get("worker_service_state")
        .cloned()
        .unwrap_or_else(|| fixture_worker_service_state(&worker_json));
    let pre190_readiness = evaluate_pre190_readiness(
        active_tasks,
        stale_leases,
        token_printed,
        &current_goal_id,
        &current_goal_status,
        linked_task_ids.len(),
        linked_pr_urls.len(),
    );

    let operator_readiness = evaluate_operator_readiness(active_tasks, stale_leases, token_printed, &campaign_report);
    let status = DesktopStatus {
        ok: !token_printed && !campaign_report.is_null(),
        mode_banner: "STANDBY / READ ONLY".into(),
        mutation_scope: "HEARTBEAT ONLY MUTATION".into(),
        execution_disabled: true,
        project_id: PROJECT_ID.into(),
        campaign_id: CAMPAIGN_ID.into(),
        worker_id: WORKER_ID.into(),
        worker_status: get_string(&worker_json, &["remote_status"]).unwrap_or_else(|| "unknown".into()),
        current_step: current_step_id,
        current_goal_id,
        current_goal_status,
        current_goal_linked_task_ids: linked_task_ids.clone(),
        current_goal_linked_pr_urls: linked_pr_urls.clone(),
        previous_goal_id: previous_step
            .and_then(|step| get_string(step, &["goal_id"]))
            .unwrap_or_else(|| "unknown".into()),
        previous_goal_status: previous_step
            .and_then(|step| get_string(step, &["status"]))
            .unwrap_or_else(|| "unknown".into()),
        goal_190_linked_task_ids_count: linked_task_ids.len() as i64,
        goal_190_linked_pr_urls_count: linked_pr_urls.len() as i64,
        active_tasks,
        stale_leases,
        token_printed,
        last_refresh_time: chrono_like_now(),
        status_age_seconds: 0,
        pre190_readiness,
        operator_readiness,
        campaign_report,
        worker_service_state,
        safe_summary,
        bridge_outcomes,
        report_cached,
        report_age_seconds: cached_report_age_seconds(),
        status_file: status_file(app).display().to_string(),
        log_file: log_file(app).display().to_string(),
        report_file: report_file_path()?.display().to_string(),
        warnings,
        errors,
    };
    write_status(app, &status)?;
    Ok(status)
}

fn run_active_status() -> Result<Value, String> {
    let repo = repo_root()?;
    let script_path = repo.join("scripts").join("powershell").join("skybridge-status.ps1");
    let token_file = home_path(".skybridge\\secrets\\worker-token.txt");
    let command_args = vec![
        "-NoProfile".to_string(),
        "-ExecutionPolicy".into(),
        "Bypass".into(),
        "-File".into(),
        script_path.display().to_string(),
        "-ApiBase".into(),
        "https://skybridge.jerryskywalker.space".into(),
        "-ProjectId".into(),
        PROJECT_ID.into(),
        "-TokenFile".into(),
        token_file.display().to_string(),
        "-ActiveOnly".into(),
        "-Json".into(),
        "-ColorMode".into(),
        "Never".into(),
    ];
    parse_json(&run_powershell(&command_args)?)
}

fn run_campaign_status() -> Result<Value, String> {
    let repo = repo_root()?;
    let script_path = repo.join("scripts").join("powershell").join("skybridge-campaign.ps1");
    let token_file = home_path(".skybridge\\secrets\\worker-token.txt");
    let command_args = vec![
        "-NoProfile".to_string(),
        "-ExecutionPolicy".into(),
        "Bypass".into(),
        "-File".into(),
        script_path.display().to_string(),
        "-ApiBase".into(),
        "https://skybridge.jerryskywalker.space".into(),
        "-ProjectId".into(),
        PROJECT_ID.into(),
        "-TokenFile".into(),
        token_file.display().to_string(),
        "status".into(),
        "-CampaignId".into(),
        CAMPAIGN_ID.into(),
        "-Json".into(),
    ];
    parse_json(&run_powershell(&command_args)?)
}

fn run_campaign_report() -> Result<Value, String> {
    let repo = repo_root()?;
    let script_path = repo.join("scripts").join("powershell").join("skybridge-campaign.ps1");
    let token_file = home_path(".skybridge\\secrets\\worker-token.txt");
    let command_args = vec![
        "-NoProfile".to_string(),
        "-ExecutionPolicy".into(),
        "Bypass".into(),
        "-File".into(),
        script_path.display().to_string(),
        "runner-report".into(),
        "-CampaignId".into(),
        CAMPAIGN_ID.into(),
        "-ApiBase".into(),
        "https://skybridge.jerryskywalker.space".into(),
        "-ProjectId".into(),
        PROJECT_ID.into(),
        "-TokenFile".into(),
        token_file.display().to_string(),
        "-Json".into(),
    ];
    parse_json(&run_powershell(&command_args)?)
}

fn run_worker_status(args: &[&str]) -> Result<String, String> {
    let repo = repo_root()?;
    let script_path = repo.join("scripts").join("powershell").join("skybridge-worker-status.ps1");
    let profile = home_path(".skybridge\\worker.laptop-zenbookduo.json");
    let mut command_args = vec![
        "-NoProfile".to_string(),
        "-ExecutionPolicy".into(),
        "Bypass".into(),
        "-File".into(),
        script_path.display().to_string(),
        "-ConfigFile".into(),
        profile.display().to_string(),
    ];
    command_args.extend(args.iter().map(|arg| arg.to_string()));
    run_powershell(&command_args)
}

fn collect_bridge_results() -> BridgeResults {
    let (sender, receiver) = mpsc::channel::<(&'static str, Result<Value, String>)>();
    for (name, task) in [
        ("active", run_active_status as fn() -> Result<Value, String>),
        ("campaign", run_campaign_status as fn() -> Result<Value, String>),
        ("report", run_campaign_report as fn() -> Result<Value, String>),
    ] {
        let sender = sender.clone();
        thread::spawn(move || {
            let _ = sender.send((name, task()));
        });
    }
    {
        let sender = sender.clone();
        thread::spawn(move || {
            let value = run_worker_status(&["-Command", "status", "-Json"]).and_then(|output| parse_json(&output));
            let _ = sender.send(("worker", value));
        });
    }
    drop(sender);

    let mut active = None;
    let mut campaign = None;
    let mut worker = None;
    let mut report = None;
    let deadline = Instant::now() + Duration::from_secs(BRIDGE_RESULT_TIMEOUT_SECONDS);
    while Instant::now() < deadline && (active.is_none() || campaign.is_none() || worker.is_none() || report.is_none()) {
        let remaining = deadline.saturating_duration_since(Instant::now());
        match receiver.recv_timeout(remaining.min(Duration::from_millis(250))) {
            Ok(("active", value)) => active = Some(value),
            Ok(("campaign", value)) => campaign = Some(value),
            Ok(("worker", value)) => worker = Some(value),
            Ok(("report", value)) => report = Some(value),
            Ok((_, _)) => {}
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }

    BridgeResults {
        active: active.unwrap_or_else(|| Err("active status bridge did not return before desktop refresh deadline".into())),
        campaign: campaign.unwrap_or_else(|| Err("campaign status bridge did not return before desktop refresh deadline".into())),
        worker: worker.unwrap_or_else(|| Err("worker status bridge did not return before desktop refresh deadline".into())),
        report: report.unwrap_or_else(|| Err("campaign report bridge did not return before desktop refresh deadline".into())),
    }
}

fn bridge_value(
    name: &str,
    result: Result<Value, String>,
    outcomes: &mut Vec<BridgeOutcome>,
    warnings: &mut Vec<String>,
) -> Value {
    match result {
        Ok(value) => {
            outcomes.push(BridgeOutcome {
                name: name.into(),
                ok: true,
                warning: None,
            });
            value
        }
        Err(error) => {
            let warning = format!("{name}: {}", redact_summary(&error));
            warnings.push(warning.clone());
            outcomes.push(BridgeOutcome {
                name: name.into(),
                ok: false,
                warning: Some(warning),
            });
            Value::Null
        }
    }
}

fn run_powershell(args: &[String]) -> Result<String, String> {
    let mut child = Command::new("pwsh")
        .args(args)
        .current_dir(repo_root()?)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| format!("failed to run pwsh: {err}"))?;
    let started = Instant::now();
    loop {
        if child.try_wait().map_err(|err| format!("failed to wait for pwsh: {err}"))?.is_some() {
            break;
        }
        if started.elapsed() > Duration::from_secs(COMMAND_TIMEOUT_SECONDS) {
            let _ = child.kill();
            let _ = child.wait();
            return Err(format!("status bridge command timed out after {COMMAND_TIMEOUT_SECONDS}s"));
        }
        thread::sleep(Duration::from_millis(100));
    }
    let output = child
        .wait_with_output()
        .map_err(|err| format!("failed to read pwsh output: {err}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        return Err(redact_summary(&format!("{stdout}\n{stderr}")));
    }
    Ok(redact(&stdout))
}

fn parse_json(text: &str) -> Result<Value, String> {
    let trimmed = text.trim();
    if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
        return Ok(value);
    }
    let object_start = trimmed.find('{');
    let array_start = trimmed.find('[');
    let start = match (object_start, array_start) {
        (Some(object), Some(array)) => Some(object.min(array)),
        (Some(object), None) => Some(object),
        (None, Some(array)) => Some(array),
        (None, None) => None,
    }
    .ok_or_else(|| "invalid bridge json: no JSON payload found".to_string())?;
    serde_json::from_str::<Value>(&trimmed[start..])
        .map_err(|err| format!("invalid bridge json: {err}"))
}

fn repo_root() -> Result<PathBuf, String> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .ok_or_else(|| "failed to resolve repo root".into())
}

fn desktop_dir(app: &AppHandle) -> PathBuf {
    if let Ok(root) = repo_root() {
        return root.join(".agent").join("desktop-client");
    }
    app.path()
        .app_data_dir()
        .unwrap_or_else(|_| PathBuf::from(".agent"))
        .join("desktop-client")
}

fn status_file(app: &AppHandle) -> PathBuf {
    desktop_dir(app).join("status.json")
}

fn log_file(app: &AppHandle) -> PathBuf {
    desktop_dir(app).join("logs").join("desktop-client.log")
}

fn write_status(app: &AppHandle, status: &DesktopStatus) -> Result<(), String> {
    let path = status_file(app);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let text = serde_json::to_string_pretty(status).map_err(|err| err.to_string())?;
    fs::write(path, text).map_err(|err| err.to_string())
}

fn campaign_reports_dir() -> Result<PathBuf, String> {
    Ok(repo_root()?.join(".agent").join("tmp").join("campaign-reports"))
}

fn report_file_path() -> Result<PathBuf, String> {
    Ok(campaign_reports_dir()?.join("dev-queue-189-200-campaign-report.md"))
}

fn report_json_path() -> Result<PathBuf, String> {
    Ok(campaign_reports_dir()?.join("dev-queue-189-200-campaign-report.json"))
}

fn read_cached_campaign_report(_app: &AppHandle) -> Option<Value> {
    let path = report_json_path().ok()?;
    let text = fs::read_to_string(path).ok()?;
    let value = serde_json::from_str::<Value>(&text).ok()?;
    value.get("report").cloned().or(Some(value))
}

fn cached_report_age_seconds() -> i64 {
    let Ok(path) = report_json_path() else {
        return -1;
    };
    let Ok(metadata) = fs::metadata(path) else {
        return -1;
    };
    let Ok(modified) = metadata.modified() else {
        return -1;
    };
    std::time::SystemTime::now()
        .duration_since(modified)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(-1)
}

fn append_log(app: &AppHandle, message: &str) -> Result<(), String> {
    let path = log_file(app);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let line = format!("{} {message}\n", chrono_like_now());
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .and_then(|mut file| std::io::Write::write_all(&mut file, line.as_bytes()))
        .map_err(|err| err.to_string())
}

fn evaluate_pre190_readiness(
    active_tasks: Option<i64>,
    stale_leases: Option<i64>,
    token_printed: bool,
    current_goal_id: &str,
    current_goal_status: &str,
    linked_task_count: usize,
    linked_pr_count: usize,
) -> Pre190Readiness {
    let mut reasons = Vec::new();
    let mut unknown = false;
    let mut blocked = false;

    match active_tasks {
        Some(0) => {}
        Some(value) => {
            blocked = true;
            reasons.push(format!("active_tasks={value}"));
        }
        None => {
            unknown = true;
            reasons.push("active_tasks=unknown".into());
        }
    }
    match stale_leases {
        Some(0) => {}
        Some(value) => {
            blocked = true;
            reasons.push(format!("stale_leases={value}"));
        }
        None => {
            unknown = true;
            reasons.push("stale_leases=unknown".into());
        }
    }
    if token_printed {
        blocked = true;
        reasons.push("token_printed=true".into());
    }
    if current_goal_id != GOAL_190_ID {
        unknown = true;
        reasons.push(format!("current_goal_id={current_goal_id}"));
    }
    if current_goal_status != "ready" {
        unknown = true;
        reasons.push(format!("current_goal_status={current_goal_status}"));
    }
    if linked_task_count > 0 {
        blocked = true;
        reasons.push(format!("goal_190_linked_task_ids_count={linked_task_count}"));
    }
    if linked_pr_count > 0 {
        blocked = true;
        reasons.push(format!("goal_190_linked_pr_urls_count={linked_pr_count}"));
    }

    if reasons.is_empty() {
        reasons.push("Goal 190 is current/ready and unexecuted; active_tasks=0; stale_leases=0; token_printed=false".into());
    }

    Pre190Readiness {
        state: if blocked {
            "BLOCK".into()
        } else if unknown {
            "WARN".into()
        } else {
            "PASS".into()
        },
        reasons,
    }
}

fn evaluate_operator_readiness(
    active_tasks: Option<i64>,
    stale_leases: Option<i64>,
    token_printed: bool,
    report: &Value,
) -> Pre190Readiness {
    let readiness = report.get("queue_control_readiness").unwrap_or(&Value::Null);
    let mut reasons = Vec::new();
    let mut blocked = false;
    let mut unknown = report.is_null();

    match active_tasks {
        Some(0) => reasons.push("active_tasks=0".into()),
        Some(value) => {
            blocked = true;
            reasons.push(format!("active_tasks={value}"));
        }
        None => {
            unknown = true;
            reasons.push("active_tasks=unknown".into());
        }
    }
    match stale_leases {
        Some(0) => reasons.push("stale_leases=0".into()),
        Some(value) => {
            blocked = true;
            reasons.push(format!("stale_leases={value}"));
        }
        None => {
            unknown = true;
            reasons.push("stale_leases=unknown".into());
        }
    }
    if token_printed {
        blocked = true;
        reasons.push("token_printed=true".into());
    } else {
        reasons.push("token_printed=false".into());
    }
    for key in ["can_start_one", "can_start_queue", "can_resume"] {
        if readiness.get(key).and_then(Value::as_bool).unwrap_or(false) {
            blocked = true;
            reasons.push(format!("{key}=true"));
        } else {
            reasons.push(format!("{key}=false"));
        }
    }
    if let Some(worker_status) = get_string(readiness, &["worker_status"]) {
        reasons.push(format!("worker_status={worker_status}"));
    }
    if let Some(mode) = get_string(report, &["worker_service_state", "mode"]) {
        reasons.push(format!("worker_service_mode={mode}"));
    }
    if get_string_array(report, &["worker_service_state", "readiness_blockers"])
        .iter()
        .any(|item| item == "execution_disabled_until_goal_195")
    {
        reasons.push("execution_disabled_until_goal_195".into());
    }
    if reasons.is_empty() {
        reasons.push("queue readiness unavailable".into());
    }

    Pre190Readiness {
        state: if blocked {
            "BLOCK".into()
        } else if unknown {
            "WARN".into()
        } else {
            "PASS".into()
        },
        reasons,
    }
}

fn detect_token_printed(label: &str, value: &Value, warnings: &mut Vec<String>) {
    if value
        .get("token_printed")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        warnings.push(format!("{label} returned token_printed=true"));
    }
}

fn get_string(value: &Value, path: &[&str]) -> Option<String> {
    let mut current = value;
    for key in path {
        current = current.get(*key)?;
    }
    current.as_str().map(ToOwned::to_owned)
}

fn get_i64(value: &Value, path: &[&str]) -> Option<i64> {
    let mut current = value;
    for key in path {
        current = current.get(*key)?;
    }
    current.as_i64()
}

fn get_string_array(value: &Value, path: &[&str]) -> Vec<String> {
    let mut current = value;
    for key in path {
        match current.get(*key) {
            Some(next) => current = next,
            None => return Vec::new(),
        }
    }
    current
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn build_safe_summary(report: &Value) -> Value {
    let readiness = report.get("queue_control_readiness").cloned().unwrap_or(Value::Null);
    let blockers = get_string_array(&readiness, &["blockers"]);
    let warnings = get_string_array(&readiness, &["warnings"]);
    let required_human_action = get_string_array(&readiness, &["required_human_action"]);
    let worker_status = get_string(&readiness, &["worker_status"]).unwrap_or_else(|| "unknown".into());
    let worker_service = report
        .get("worker_service_state")
        .cloned()
        .unwrap_or_else(|| fixture_worker_service_state(&Value::Null));
    let worker_service_mode = get_string(&worker_service, &["mode"]).unwrap_or_else(|| "offline".into());
    let worker_service_blockers = get_string_array(&worker_service, &["readiness_blockers"]);
    let attention_count = (if matches!(worker_status.as_str(), "offline" | "stale" | "missing" | "unknown") { 1 } else { 0 })
        + blockers.len()
        + required_human_action.len();
    let next_safe_action = get_string(&readiness, &["next_safe_action"]).unwrap_or_else(|| "Inspect report before any operator action.".into());
    let top_blocker = if blockers.is_empty() {
        None
    } else {
        Some(format!("Queue blocked by {}.", blockers.join(", ")))
    };
    serde_json::json!({
        "schema": "skybridge.campaign_safe_summary.v1",
        "campaign_id": get_string(report, &["campaign_id"]).unwrap_or_else(|| CAMPAIGN_ID.into()),
        "current_step": get_string(report, &["current_step_id"]).unwrap_or_else(|| "unknown".into()),
        "current_goal_id": get_string(report, &["current_goal_id"]).unwrap_or_else(|| "unknown".into()),
        "current_goal_status": get_string(report, &["current_goal_status"]).unwrap_or_else(|| "unknown".into()),
        "queue_readiness": {
            "can_start_one": readiness.get("can_start_one").and_then(Value::as_bool).unwrap_or(false),
            "can_start_queue": readiness.get("can_start_queue").and_then(Value::as_bool).unwrap_or(false),
            "can_resume": readiness.get("can_resume").and_then(Value::as_bool).unwrap_or(false),
            "can_stop": readiness.get("can_stop").and_then(Value::as_bool).unwrap_or(false),
            "can_emergency_stop": readiness.get("can_emergency_stop").and_then(Value::as_bool).unwrap_or(false),
            "next_safe_action": next_safe_action.clone(),
            "worker_required": readiness.get("worker_required").and_then(Value::as_bool).unwrap_or(true),
            "worker_status": worker_status.clone()
        },
        "blockers": blockers,
        "warnings": warnings,
        "worker_status": worker_status,
        "worker_service_mode": worker_service_mode,
        "worker_service_blockers": worker_service_blockers,
        "attention_count": attention_count,
        "top_blocker": top_blocker,
        "recommended_next_action": next_safe_action,
        "token_printed": false
    })
}

fn fixture_worker_service_state(worker_json: &Value) -> Value {
    let remote_status = get_string(worker_json, &["remote_status"]).unwrap_or_else(|| "offline".into());
    let mode = if remote_status == "online" || remote_status == "ready" {
        "standby"
    } else {
        "offline"
    };
    let first_blocker = if mode == "offline" {
        "worker_service_offline"
    } else {
        "standby_heartbeat_only_no_execution"
    };
    serde_json::json!({
        "schema": "skybridge.worker_service_state.v1",
        "worker_service_state": true,
        "worker_id": WORKER_ID,
        "worker_profile": "laptop-zenbookduo-standby",
        "mode": mode,
        "heartbeat_at": get_string(worker_json, &["last_seen"]),
        "service_started_at": null,
        "current_task_id": get_string(worker_json, &["current_task_id"]),
        "can_claim_tasks": false,
        "can_execute_tasks": false,
        "stop_requested": false,
        "pause_requested": false,
        "capability_matrix": {
            "heartbeat": true,
            "status": true,
            "stop": true,
            "pause": true,
            "task_claim": false,
            "task_execute": false,
            "codex_execute": false,
            "pr_create": false,
            "arbitrary_shell": false,
            "token_printed": false
        },
        "readiness_blockers": [first_blocker, "execution_disabled_until_goal_195"],
        "token_available": false,
        "token_printed": false
    })
}

fn home_path(relative: &str) -> PathBuf {
    std::env::var("USERPROFILE")
        .map(PathBuf::from)
        .or_else(|_| std::env::var("HOME").map(PathBuf::from))
        .unwrap_or_else(|_| PathBuf::from("."))
        .join(relative)
}

fn redact(text: &str) -> String {
    text.replace("Authorization", "[REDACTED_HEADER]")
        .replace("Bearer ", "Bearer [REDACTED]")
}

fn redact_summary(text: &str) -> String {
    let redacted = redact(text);
    let trimmed = redacted.trim();
    if trimmed.is_empty() {
        return "status bridge command failed without output".into();
    }
    let first_line = trimmed.lines().next().unwrap_or("status bridge command failed");
    first_line.chars().take(240).collect()
}

fn chrono_like_now() -> String {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| format!("unix:{}", duration.as_secs()))
        .unwrap_or_else(|_| "unix:0".into())
}

fn default_icon() -> tauri::image::Image<'static> {
    tauri::image::Image::from_bytes(include_bytes!("../icons/icon.png")).expect("embedded icon")
}
