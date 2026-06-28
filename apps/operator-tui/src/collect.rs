use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

use serde::Deserialize;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

use crate::model::{
    fixture_state, CloudState, OperatorState, RepoState, StageCloseState, StatusFreshness,
    BASELINE_HEAD, CLOUD_IMAGE_REF, STAGE_S1_1_HEAD,
};

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum StateMode {
    Fixture,
    Local,
    Cloud,
    LocalCloud,
}

impl StateMode {
    pub fn as_str(self) -> &'static str {
        match self {
            StateMode::Fixture => "fixture",
            StateMode::Local => "local",
            StateMode::Cloud => "cloud",
            StateMode::LocalCloud => "local-cloud",
        }
    }

    pub fn loads_local(self) -> bool {
        matches!(self, StateMode::Local | StateMode::LocalCloud)
    }

    pub fn loads_cloud(self) -> bool {
        matches!(self, StateMode::Cloud | StateMode::LocalCloud)
    }
}

pub fn collect_operator_state(mode: StateMode) -> OperatorState {
    if mode == StateMode::Fixture {
        return fixture_state();
    }

    let generated_at = now_utc();
    let mut state = fixture_state();
    state.generated_at = generated_at.clone();
    state.mode = mode.as_str().to_string();
    state.local_state_source = "not_requested".to_string();
    state.cloud_state_source = "not_requested".to_string();
    state.local_state_loaded = false;
    state.cloud_state_loaded = false;
    state.read_only = true;
    if !mode.loads_local() {
        state.repo = not_requested_repo();
    }
    if !mode.loads_cloud() {
        state.cloud = not_requested_cloud();
    }
    state.status_freshness = StatusFreshness {
        generated_at,
        local_age_seconds: None,
        cloud_age_seconds: None,
    };
    state.stage_close = collect_stage_close_state();

    if mode.loads_local() {
        match collect_local_state() {
            Ok(repo) => {
                state.local_state_source = "git_read_only".to_string();
                state.local_state_loaded = true;
                state.status_freshness.local_age_seconds = Some(0);
                state.repo = repo;
            }
            Err(reason) => {
                state.local_state_source = "git_read_only_unavailable".to_string();
                state.campaign.blockers.push(reason);
            }
        }
    }

    if mode.loads_cloud() {
        let report = collect_cloud_state();
        state.cloud_state_source = report.source.clone();
        state.cloud_state_loaded = report.loaded;
        state.status_freshness.cloud_age_seconds = report.loaded.then_some(0);
        state.cloud = report.cloud;
        state.campaign.warnings.extend(report.warnings);
        if !state.cloud_state_loaded {
            state
                .campaign
                .blockers
                .push("cloud_state_unavailable".to_string());
        }
    }

    state
}

fn collect_local_state() -> Result<RepoState, String> {
    let root = git_text(None, &["rev-parse", "--show-toplevel"])
        .ok_or_else(|| "git_repository_root_unavailable".to_string())?;
    let root_path = PathBuf::from(root.trim());

    let branch = git_text(Some(&root_path), &["rev-parse", "--abbrev-ref", "HEAD"])
        .unwrap_or_else(|| "unknown".to_string());
    let head =
        git_text(Some(&root_path), &["rev-parse", "HEAD"]).unwrap_or_else(|| "unknown".to_string());
    let local_main_commit = git_text(Some(&root_path), &["rev-parse", "main"]).unwrap_or_default();
    let origin_main_commit =
        git_text(Some(&root_path), &["rev-parse", "origin/main"]).unwrap_or_default();
    let status = git_text(Some(&root_path), &["status", "--porcelain=v1"]).unwrap_or_default();
    let status_lines = sanitize_status_lines(&status);
    let worktree_clean = status.trim().is_empty();
    let main_aligned = !local_main_commit.is_empty()
        && !origin_main_commit.is_empty()
        && local_main_commit == origin_main_commit;
    let origin_aligned =
        !head.is_empty() && !origin_main_commit.is_empty() && head == origin_main_commit;

    Ok(RepoState {
        branch,
        head,
        local_main_commit,
        origin_main_commit,
        main_aligned,
        worktree_clean,
        origin_aligned,
        git_status_summary: if status_lines.is_empty() {
            vec!["clean".to_string()]
        } else {
            status_lines
        },
        repository_root: root_path.to_string_lossy().replace('\\', "/"),
        package_manager_marker: detect_package_manager(&root_path),
        known_warning_state: vec![
            "tracked: Vite chunk-size warning non-failing".to_string(),
            "resolved: GitHub Actions Node.js 20 deprecation resolved".to_string(),
        ],
    })
}

fn collect_cloud_state() -> CloudProbeResult {
    let output = Command::new("pwsh")
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            CLOUD_PROBE_SCRIPT,
        ])
        .env("SKYBRIDGE_OPERATOR_TUI_REPO_ROOT", repo_root_for_probe())
        .output();

    let Ok(output) = output else {
        return CloudProbeResult::unavailable("pwsh_unavailable");
    };

    if !output.status.success() {
        return CloudProbeResult::unavailable("cloud_probe_failed");
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let parsed = serde_json::from_str::<CloudProbeJson>(text.trim());
    let Ok(parsed) = parsed else {
        return CloudProbeResult::unavailable("cloud_probe_invalid_json");
    };

    let image_tag = if parsed.image_tag.is_empty() {
        image_tag_from_ref(&parsed.image_ref)
    } else {
        parsed.image_tag
    };
    let health = if parsed.health_ok {
        "ok"
    } else {
        "unavailable"
    };
    let parity = if parsed.parity_status.is_empty() {
        if parsed.parity_ok {
            "ok"
        } else {
            "unavailable"
        }
    } else {
        parsed.parity_status.as_str()
    };

    CloudProbeResult {
        loaded: parsed.loaded,
        source: parsed.source,
        cloud: CloudState {
            health: health.to_string(),
            version: parsed.commit_sha.clone(),
            image_ref: parsed.image_ref,
            parity: parity.to_string(),
            health_ok: parsed.health_ok,
            version_ok: parsed.version_ok,
            commit_sha: parsed.commit_sha,
            image_tag,
            parity_ok: parsed.parity_ok,
            missing_routes: parsed.missing_routes,
        },
        warnings: parsed.warnings,
    }
}

fn collect_stage_close_state() -> StageCloseState {
    let source = Path::new("docs/release/STAGE_S1_1_CLOSE.md");
    let text = fs::read_to_string(source).unwrap_or_default();
    let tracked = if text.contains("Vite chunk-size warning") {
        "Vite chunk-size warning non-failing"
    } else {
        "Vite chunk-size warning state not found"
    };
    let resolved = if text.contains("GitHub Actions Node.js 20") {
        "GitHub Actions Node.js 20 deprecation resolved"
    } else {
        "GitHub Actions Node.js 20 deprecation state not found"
    };

    StageCloseState {
        source: source.to_string_lossy().replace('\\', "/"),
        baseline_commit: STAGE_S1_1_HEAD.to_string(),
        baseline_image_ref: format!(
            "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-{STAGE_S1_1_HEAD}"
        ),
        tracked_warning: tracked.to_string(),
        resolved_warning: resolved.to_string(),
    }
}

fn not_requested_repo() -> RepoState {
    RepoState {
        branch: "not_loaded".to_string(),
        head: String::new(),
        local_main_commit: String::new(),
        origin_main_commit: String::new(),
        main_aligned: false,
        worktree_clean: false,
        origin_aligned: false,
        git_status_summary: vec!["not_loaded".to_string()],
        repository_root: String::new(),
        package_manager_marker: "not_loaded".to_string(),
        known_warning_state: Vec::new(),
    }
}

fn not_requested_cloud() -> CloudState {
    CloudState {
        health: "not_loaded".to_string(),
        version: String::new(),
        image_ref: String::new(),
        parity: "not_loaded".to_string(),
        health_ok: false,
        version_ok: false,
        commit_sha: String::new(),
        image_tag: String::new(),
        parity_ok: false,
        missing_routes: Vec::new(),
    }
}

fn repo_root_for_probe() -> String {
    git_text(None, &["rev-parse", "--show-toplevel"])
        .map(PathBuf::from)
        .or_else(|| env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."))
        .to_string_lossy()
        .to_string()
}

fn git_text(repo_root: Option<&Path>, args: &[&str]) -> Option<String> {
    let mut command = Command::new("git");
    if let Some(root) = repo_root {
        command.arg("-C").arg(root);
    }
    command.args(args);
    let output = command.output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn sanitize_status_lines(status: &str) -> Vec<String> {
    let mut lines = status
        .lines()
        .take(20)
        .map(|line| {
            if line.len() > 180 {
                format!("{}...", &line[..180])
            } else {
                line.to_string()
            }
        })
        .collect::<Vec<_>>();
    if status.lines().count() > lines.len() {
        lines.push("truncated_status_summary".to_string());
    }
    lines
}

fn detect_package_manager(root: &Path) -> String {
    if root.join("pnpm-lock.yaml").is_file() {
        "pnpm".to_string()
    } else if root.join("package-lock.json").is_file() {
        "npm".to_string()
    } else if root.join("yarn.lock").is_file() {
        "yarn".to_string()
    } else if root.join("package.json").is_file() {
        "package_json_only".to_string()
    } else {
        "unknown".to_string()
    }
}

fn image_tag_from_ref(image_ref: &str) -> String {
    image_ref
        .rsplit(':')
        .next()
        .filter(|value| !value.is_empty() && *value != image_ref)
        .unwrap_or("")
        .to_string()
}

fn now_utc() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}

#[derive(Debug)]
struct CloudProbeResult {
    loaded: bool,
    source: String,
    cloud: CloudState,
    warnings: Vec<String>,
}

impl CloudProbeResult {
    fn unavailable(reason: &str) -> Self {
        Self {
            loaded: false,
            source: reason.to_string(),
            cloud: CloudState {
                health: "unavailable".to_string(),
                version: String::new(),
                image_ref: CLOUD_IMAGE_REF.to_string(),
                parity: "unavailable".to_string(),
                health_ok: false,
                version_ok: false,
                commit_sha: BASELINE_HEAD.to_string(),
                image_tag: format!("sha-{BASELINE_HEAD}"),
                parity_ok: false,
                missing_routes: Vec::new(),
            },
            warnings: vec![reason.to_string()],
        }
    }
}

#[derive(Debug, Deserialize)]
struct CloudProbeJson {
    loaded: bool,
    source: String,
    health_ok: bool,
    version_ok: bool,
    commit_sha: String,
    image_ref: String,
    image_tag: String,
    parity_ok: bool,
    parity_status: String,
    missing_routes: Vec<String>,
    warnings: Vec<String>,
}

const CLOUD_PROBE_SCRIPT: &str = r#"
$ErrorActionPreference = "Stop"
$warnings = @()
function Add-Warning([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  if ($warnings -notcontains $Value) { $script:warnings = @($script:warnings) + $Value }
}

$apiBase = $env:SKYBRIDGE_API_BASE
if ([string]::IsNullOrWhiteSpace($apiBase)) { $apiBase = $env:SKYBRIDGE_PUBLIC_API_BASE }
if ([string]::IsNullOrWhiteSpace($apiBase)) {
  $gh = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $gh) {
    try {
      $raw = & gh variable get SKYBRIDGE_PUBLIC_API_BASE --repo JerrySkywalker/skybridge-agent-hub 2>$null
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($raw)) {
        $apiBase = (($raw | Out-String).Trim())
      }
    } catch {
      Add-Warning "cloud_api_base_variable_unavailable"
    }
  }
}

$healthOk = $false
$versionOk = $false
$commitSha = ""
$imageRef = ""
$imageTag = ""
$parityOk = $false
$parityStatus = ""
$missingRoutes = @()

if ([string]::IsNullOrWhiteSpace($apiBase)) {
  Add-Warning "cloud_api_base_not_configured"
  [pscustomobject]@{
    loaded = $false
    source = "cloud_api_base_not_configured"
    health_ok = $false
    version_ok = $false
    commit_sha = ""
    image_ref = ""
    image_tag = ""
    parity_ok = $false
    parity_status = "not_configured"
    missing_routes = @()
    warnings = @($warnings)
  } | ConvertTo-Json -Depth 8 -Compress
  return
}

try {
  $health = Invoke-RestMethod -Method GET -Uri ($apiBase.TrimEnd("/") + "/v1/health") -TimeoutSec 20
  $healthOk = $true
} catch {
  Add-Warning "cloud_health_unavailable"
}

try {
  $version = Invoke-RestMethod -Method GET -Uri ($apiBase.TrimEnd("/") + "/v1/version") -TimeoutSec 20
  $versionOk = $true
  if ($version.commit_sha) { $commitSha = [string]$version.commit_sha }
  if ($version.image_ref) { $imageRef = [string]$version.image_ref }
  if ($version.image_tag) { $imageTag = [string]$version.image_tag }
} catch {
  Add-Warning "cloud_version_unavailable"
}

try {
  $repoRoot = $env:SKYBRIDGE_OPERATOR_TUI_REPO_ROOT
  $parityScript = Join-Path $repoRoot "scripts/powershell/skybridge-cloud-parity-check.ps1"
  if (Test-Path -LiteralPath $parityScript -PathType Leaf) {
    $rawParity = & pwsh -NoProfile -ExecutionPolicy Bypass -File $parityScript -ApiBase $apiBase -Json 2>$null
    if ($LASTEXITCODE -eq 0) {
      $parsed = (($rawParity | Out-String).Trim() | ConvertFrom-Json)
      $parityOk = [bool]$parsed.ok
      $parityStatus = if ($parsed.status) { [string]$parsed.status } else { "unknown" }
      $missingRoutes = @($parsed.missing_routes | ForEach-Object { [string]$_ })
    } else {
      Add-Warning "cloud_parity_check_failed"
      $parityStatus = "failed"
    }
  } else {
    Add-Warning "cloud_parity_script_missing"
    $parityStatus = "script_missing"
  }
} catch {
  Add-Warning "cloud_parity_unavailable"
  $parityStatus = "unavailable"
}

if ([string]::IsNullOrWhiteSpace($imageTag) -and -not [string]::IsNullOrWhiteSpace($imageRef) -and $imageRef.Contains(":")) {
  $imageTag = $imageRef.Split(":")[-1]
}

[pscustomobject]@{
  loaded = ($healthOk -and $versionOk)
  source = "http_v1_health_version_with_parity_script"
  health_ok = $healthOk
  version_ok = $versionOk
  commit_sha = $commitSha
  image_ref = $imageRef
  image_tag = $imageTag
  parity_ok = $parityOk
  parity_status = $parityStatus
  missing_routes = @($missingRoutes)
  warnings = @($warnings)
} | ConvertTo-Json -Depth 8 -Compress
"#;
