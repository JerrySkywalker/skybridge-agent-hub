use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager};

const PROJECT_ID: &str = "skybridge-agent-hub";
const CAMPAIGN_ID: &str = "dev-queue-189-200";
const WORKER_ID: &str = "laptop-zenbookduo";

#[derive(Debug, Serialize, Deserialize)]
struct DesktopStatus {
    ok: bool,
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
    active_tasks: i64,
    stale_leases: i64,
    token_printed: bool,
    last_refresh_time: String,
    status_file: String,
    log_file: String,
    errors: Vec<String>,
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
fn get_status(app: AppHandle) -> Result<DesktopStatus, String> {
    collect_status(&app)
}

#[tauri::command]
fn heartbeat_now(app: AppHandle) -> Result<HeartbeatResult, String> {
    append_log(&app, "heartbeat-now requested")?;
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

pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            build_tray(app.handle())?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_status, heartbeat_now])
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
                let _ = collect_status(app);
                show_main_window(app);
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
    let mut errors = Vec::new();

    let active_json = match run_script_json(
        "skybridge-status.ps1",
        &["-ActiveOnly", "-Json", "-ColorMode", "Never"],
    ) {
        Ok(value) => value,
        Err(error) => {
            errors.push(error);
            Value::Null
        }
    };
    let campaign_json = match run_script_json("skybridge-campaign.ps1", &["status", "-CampaignId", CAMPAIGN_ID, "-Json"]) {
        Ok(value) => value,
        Err(error) => {
            errors.push(error);
            Value::Null
        }
    };
    let worker_json = match run_worker_status(&["-Command", "status", "-Json"]).and_then(|output| parse_json(&output)) {
        Ok(value) => value,
        Err(error) => {
            errors.push(error);
            Value::Null
        }
    };

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
        .find(|step| get_string(step, &["goal_id"]).as_deref() == Some("super-189-ci-guardian-pr-finalizer-hardening"));

    let status = DesktopStatus {
        ok: errors.is_empty(),
        project_id: PROJECT_ID.into(),
        campaign_id: CAMPAIGN_ID.into(),
        worker_id: WORKER_ID.into(),
        worker_status: get_string(&worker_json, &["remote_status"]).unwrap_or_else(|| "unknown".into()),
        current_step: current_step_id,
        current_goal_id: current_step
            .and_then(|step| get_string(step, &["goal_id"]))
            .unwrap_or_else(|| "unknown".into()),
        current_goal_status: current_step
            .and_then(|step| get_string(step, &["status"]))
            .unwrap_or_else(|| "unknown".into()),
        current_goal_linked_task_ids: current_step.map_or_else(Vec::new, |step| get_string_array(step, &["linked_task_ids"])),
        current_goal_linked_pr_urls: current_step.map_or_else(Vec::new, |step| get_string_array(step, &["linked_pr_urls"])),
        previous_goal_id: previous_step
            .and_then(|step| get_string(step, &["goal_id"]))
            .unwrap_or_else(|| "unknown".into()),
        previous_goal_status: previous_step
            .and_then(|step| get_string(step, &["status"]))
            .unwrap_or_else(|| "unknown".into()),
        active_tasks: get_i64(&active_json, &["task_summary", "active"]).unwrap_or(0),
        stale_leases: get_i64(&active_json, &["task_summary", "stale_leases"]).unwrap_or(0),
        token_printed: false,
        last_refresh_time: chrono_like_now(),
        status_file: status_file(app).display().to_string(),
        log_file: log_file(app).display().to_string(),
        errors,
    };
    write_status(app, &status)?;
    Ok(status)
}

fn run_script_json(script: &str, args: &[&str]) -> Result<Value, String> {
    let repo = repo_root()?;
    let script_path = repo.join("scripts").join("powershell").join(script);
    let token_file = home_path(".skybridge\\secrets\\worker-token.txt");
    let mut command_args = vec![
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
    ];
    command_args.extend(args.iter().map(|arg| arg.to_string()));
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

fn run_powershell(args: &[String]) -> Result<String, String> {
    let output = Command::new("pwsh")
        .args(args)
        .current_dir(repo_root()?)
        .output()
        .map_err(|err| format!("failed to run pwsh: {err}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        return Err(redact(&format!("{stdout}\n{stderr}")));
    }
    Ok(redact(&stdout))
}

fn parse_json(text: &str) -> Result<Value, String> {
    serde_json::from_str::<Value>(text.trim()).map_err(|err| format!("invalid bridge json: {err}"))
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

fn chrono_like_now() -> String {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| format!("unix:{}", duration.as_secs()))
        .unwrap_or_else(|_| "unix:0".into())
}

fn default_icon() -> tauri::image::Image<'static> {
    tauri::image::Image::from_bytes(include_bytes!("../icons/icon.png")).expect("embedded icon")
}
