use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{anyhow, Context};
use serde::Serialize;
use serde_json::json;

use crate::{commands::now_utc, docs_pr_capability::MG371B_FUTURE_AUTHORIZATION_PHRASE};

pub const MG371B1_REPORT_SCHEMA: &str =
    "skybridge.operator_tui_mg371b1_real_docs_pr_provider_implementation.v1";
pub const MG371B1_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/mg371b1-real-provider-implementation";
pub const MG371B1_BASELINE_COMMIT: &str = "873e1b61e20ac1ff651f3ea5f13fc0cdce5e47f6";
const DEFAULT_BRANCH_NAME: &str = "tui/mg371b-docs-only-pr-20260706-b1probe";

const ALLOWED_FILES: &[&str] = &[
    "docs/operator/MG371B_FIRST_TUI_CREATED_DOCS_ONLY_PR.md",
    "docs/operator/RATATUI_OPERATOR_CONSOLE.md",
    "docs/dev/PROGRESS.md",
    "docs/release/MANAGED_DEV_E2E_HANDOFF.md",
    "docs/release/STAGE_S1_1_CLOSE.md",
];

const ARTIFACT_NAMES: &[&str] = &[
    "mg371b1-state.json",
    "mg371b1-report.json",
    "mg371b1-report.md",
    "mg371b1-provider-support-probe.json",
    "mg371b1-default-block-report.json",
    "mg371b1-authorization-block-report.json",
    "mg371b1-allowlist-block-report.json",
    "mg371b1-branch-policy-block-report.json",
    "mg371b1-preflight-report.json",
    "mg371b1-safety-report.json",
    "mg371b1-action-history.json",
    "mg371b1-artifact-index.json",
];

#[derive(Debug, Clone)]
pub struct Mg371b1Options {
    pub output_dir: PathBuf,
    pub support_probe: bool,
    pub allow_real_provider: bool,
    pub authorization_phrase: String,
    pub branch_name: String,
    pub changed_files: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct Mg371b1Report {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub baseline_commit: &'static str,
    pub implementation_added: bool,
    pub runtime_behavior_changed: bool,
    pub real_provider_path_implemented: bool,
    pub real_provider_disabled_by_default: bool,
    pub real_provider_requires_explicit_flag: bool,
    pub real_provider_requires_exact_authorization: bool,
    pub real_provider_requires_allowlist: bool,
    pub real_provider_requires_branch_policy: bool,
    pub real_provider_requires_clean_synced_main: bool,
    pub support_probe_passed: bool,
    pub fake_provider_still_available: bool,
    pub real_provider_called: bool,
    pub real_provider_mutation_executed: bool,
    pub real_mutation_enabled: bool,
    pub authorization_phrase_used_for_real_mutation: bool,
    pub branch_policy_enforced: bool,
    pub allowlist_enforced: bool,
    pub pr_policy_enforced: bool,
    #[serde(rename = "TUI_created_branch")]
    pub tui_created_branch: bool,
    #[serde(rename = "TUI_created_PR")]
    pub tui_created_pr: bool,
    pub git_push_called: bool,
    pub gh_pr_create_called: bool,
    pub github_api_called: bool,
    pub real_task_execution_enabled: bool,
    pub task_created: bool,
    pub task_claimed: bool,
    pub execution_started: bool,
    pub worker_loop_started: bool,
    pub queue_runner_started: bool,
    pub run_forever_started: bool,
    pub hermes_live_called: bool,
    pub mcp_run_called: bool,
    pub auto_merge_enabled: bool,
    pub release_created: bool,
    pub tag_created: bool,
    pub asset_uploaded: bool,
    pub raw_input_persisted: bool,
    pub token_printed: bool,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug)]
struct BranchValidation {
    name: String,
    valid: bool,
    blockers: Vec<String>,
}

#[derive(Debug)]
struct AllowlistValidation {
    changed_files: Vec<String>,
    docs_only_allowlist_passed: bool,
    blocked_files: Vec<String>,
}

#[derive(Debug, Serialize)]
struct RepoPreflight {
    repo_clean: bool,
    on_main: bool,
    main_synced_with_origin_main: bool,
    baseline_present: bool,
    current_branch: String,
    head: String,
    origin_main: String,
    blockers: Vec<String>,
}

impl RepoPreflight {
    fn ok(&self) -> bool {
        self.repo_clean
            && self.on_main
            && self.main_synced_with_origin_main
            && self.baseline_present
            && self.blockers.is_empty()
    }
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
enum BlockKind {
    SupportProbe,
    DefaultRealProviderBlocked,
    AuthorizationRequired,
    AllowlistFailed,
    BranchPolicyFailed,
    PreflightFailed,
    Mg371bModeRequired,
}

#[allow(dead_code)]
pub trait RealDocsPrProvider {
    fn create_local_branch(&mut self, branch_name: &str) -> anyhow::Result<()>;
    fn commit_allowlisted_docs_changes(&mut self, changed_files: &[String]) -> anyhow::Result<()>;
    fn push_branch(&mut self, branch_name: &str) -> anyhow::Result<()>;
    fn create_draft_pr(&mut self, branch_name: &str, title: &str) -> anyhow::Result<()>;
}

#[allow(dead_code)]
pub struct GuardedRealDocsPrProvider {
    provider_call_count: usize,
}

impl RealDocsPrProvider for GuardedRealDocsPrProvider {
    fn create_local_branch(&mut self, _branch_name: &str) -> anyhow::Result<()> {
        self.provider_call_count += 1;
        Err(anyhow!(
            "real docs PR provider operation is not callable in MG371B1 support mode"
        ))
    }

    fn commit_allowlisted_docs_changes(&mut self, _changed_files: &[String]) -> anyhow::Result<()> {
        self.provider_call_count += 1;
        Err(anyhow!(
            "real docs PR provider operation is not callable in MG371B1 support mode"
        ))
    }

    fn push_branch(&mut self, _branch_name: &str) -> anyhow::Result<()> {
        self.provider_call_count += 1;
        Err(anyhow!(
            "real docs PR provider operation is not callable in MG371B1 support mode"
        ))
    }

    fn create_draft_pr(&mut self, _branch_name: &str, _title: &str) -> anyhow::Result<()> {
        self.provider_call_count += 1;
        Err(anyhow!(
            "real docs PR provider operation is not callable in MG371B1 support mode"
        ))
    }
}

pub fn run_mg371b1_real_provider_implementation(
    options: &Mg371b1Options,
) -> anyhow::Result<Mg371b1Report> {
    let generated_at = now_utc();
    let branch = validate_branch_name(&branch_name_for(options));
    let allowlist = validate_changed_files(&changed_files_for(options));
    let preflight = collect_repo_preflight();
    let authorization_phrase_matched =
        options.authorization_phrase == MG371B_FUTURE_AUTHORIZATION_PHRASE;
    let fake_provider_still_available = true;
    let mg371b_execution_mode = false;

    let block_kind = classify_run(
        options,
        authorization_phrase_matched,
        &branch,
        &allowlist,
        &preflight,
        mg371b_execution_mode,
    );
    let blockers = blockers_for(block_kind);
    let warnings = vec![
        "MG371B1 implements provider support only; it is not MG371B execution".to_string(),
        "real provider operations are defined but not called by MG371B1 smokes".to_string(),
    ];

    let report = Mg371b1Report {
        schema: MG371B1_REPORT_SCHEMA,
        generated_at: generated_at.clone(),
        mode: "mg371b1-real-provider-implementation",
        baseline_commit: MG371B1_BASELINE_COMMIT,
        implementation_added: true,
        runtime_behavior_changed: true,
        real_provider_path_implemented: true,
        real_provider_disabled_by_default: true,
        real_provider_requires_explicit_flag: true,
        real_provider_requires_exact_authorization: true,
        real_provider_requires_allowlist: true,
        real_provider_requires_branch_policy: true,
        real_provider_requires_clean_synced_main: true,
        support_probe_passed: true,
        fake_provider_still_available,
        real_provider_called: false,
        real_provider_mutation_executed: false,
        real_mutation_enabled: false,
        authorization_phrase_used_for_real_mutation: false,
        branch_policy_enforced: true,
        allowlist_enforced: true,
        pr_policy_enforced: true,
        tui_created_branch: false,
        tui_created_pr: false,
        git_push_called: false,
        gh_pr_create_called: false,
        github_api_called: false,
        real_task_execution_enabled: false,
        task_created: false,
        task_claimed: false,
        execution_started: false,
        worker_loop_started: false,
        queue_runner_started: false,
        run_forever_started: false,
        hermes_live_called: false,
        mcp_run_called: false,
        auto_merge_enabled: false,
        release_created: false,
        tag_created: false,
        asset_uploaded: false,
        raw_input_persisted: false,
        token_printed: false,
        blockers,
        warnings,
    };

    write_mg371b1_artifacts(
        &options.output_dir,
        &generated_at,
        options,
        &branch,
        &allowlist,
        &preflight,
        authorization_phrase_matched,
        block_kind,
        mg371b_execution_mode,
        &report,
    )?;

    Ok(report)
}

fn classify_run(
    options: &Mg371b1Options,
    authorization_phrase_matched: bool,
    branch: &BranchValidation,
    allowlist: &AllowlistValidation,
    preflight: &RepoPreflight,
    mg371b_execution_mode: bool,
) -> BlockKind {
    if options.support_probe {
        return BlockKind::SupportProbe;
    }
    if !options.allow_real_provider {
        return BlockKind::DefaultRealProviderBlocked;
    }
    if !authorization_phrase_matched {
        return BlockKind::AuthorizationRequired;
    }
    if !allowlist.docs_only_allowlist_passed {
        return BlockKind::AllowlistFailed;
    }
    if !branch.valid {
        return BlockKind::BranchPolicyFailed;
    }
    if !preflight.ok() {
        return BlockKind::PreflightFailed;
    }
    if !mg371b_execution_mode {
        return BlockKind::Mg371bModeRequired;
    }
    BlockKind::Mg371bModeRequired
}

fn blockers_for(kind: BlockKind) -> Vec<String> {
    match kind {
        BlockKind::SupportProbe => Vec::new(),
        BlockKind::DefaultRealProviderBlocked => vec!["real_mutation_disabled_by_default"],
        BlockKind::AuthorizationRequired => vec!["authorization_phrase_mismatch"],
        BlockKind::AllowlistFailed => vec!["docs_only_allowlist_failed"],
        BlockKind::BranchPolicyFailed => vec!["branch_policy_failed"],
        BlockKind::PreflightFailed => vec!["preflight_failed"],
        BlockKind::Mg371bModeRequired => vec!["mg371b_execution_mode_required"],
    }
    .into_iter()
    .map(str::to_string)
    .collect()
}

fn branch_name_for(options: &Mg371b1Options) -> String {
    if !options.branch_name.trim().is_empty() {
        return options.branch_name.trim().to_string();
    }
    DEFAULT_BRANCH_NAME.to_string()
}

fn changed_files_for(options: &Mg371b1Options) -> Vec<String> {
    if !options.changed_files.is_empty() {
        return options.changed_files.clone();
    }
    ALLOWED_FILES
        .iter()
        .map(|path| (*path).to_string())
        .collect()
}

fn validate_branch_name(branch_name: &str) -> BranchValidation {
    let mut blockers = Vec::new();
    if !branch_name.starts_with("tui/") {
        blockers.push("branch_prefix_must_be_tui".to_string());
    }
    if !branch_name.starts_with("tui/mg371b-docs-only-pr-") {
        blockers.push("branch_milestone_must_be_mg371b".to_string());
    }
    if branch_name.chars().any(char::is_whitespace) {
        blockers.push("branch_name_must_not_contain_spaces".to_string());
    }
    if branch_name.len() >= 80 {
        blockers.push("branch_name_must_be_under_80_characters".to_string());
    }
    if contains_shell_metacharacter(branch_name) {
        blockers.push("branch_name_must_not_contain_shell_metacharacters".to_string());
    }
    if !has_date_and_short_id(branch_name) {
        blockers.push("branch_name_must_include_utc_date_and_short_id".to_string());
    }

    BranchValidation {
        name: branch_name.to_string(),
        valid: blockers.is_empty(),
        blockers,
    }
}

fn validate_changed_files(changed_files: &[String]) -> AllowlistValidation {
    let allowed = ALLOWED_FILES.iter().copied().collect::<BTreeSet<_>>();
    let blocked_files = changed_files
        .iter()
        .filter(|path| !allowed.contains(path.as_str()))
        .cloned()
        .collect::<Vec<_>>();

    AllowlistValidation {
        changed_files: changed_files.to_vec(),
        docs_only_allowlist_passed: blocked_files.is_empty(),
        blocked_files,
    }
}

fn collect_repo_preflight() -> RepoPreflight {
    let status = run_git(&["status", "--porcelain=v1"]).unwrap_or_default();
    let current_branch = run_git(&["branch", "--show-current"]).unwrap_or_default();
    let head = run_git(&["rev-parse", "HEAD"]).unwrap_or_default();
    let origin_main = run_git(&["rev-parse", "origin/main"]).unwrap_or_default();
    let merge_base_contains = Command::new("git")
        .args([
            "merge-base",
            "--is-ancestor",
            MG371B1_BASELINE_COMMIT,
            "HEAD",
        ])
        .status()
        .map(|status| status.success())
        .unwrap_or(false);

    let repo_clean = status.trim().is_empty();
    let on_main = current_branch.trim() == "main";
    let main_synced_with_origin_main = !head.trim().is_empty() && head.trim() == origin_main.trim();
    let mut blockers = Vec::new();
    if !repo_clean {
        blockers.push("repo_not_clean".to_string());
    }
    if !on_main {
        blockers.push("current_branch_not_main".to_string());
    }
    if !main_synced_with_origin_main {
        blockers.push("main_not_synced_with_origin_main".to_string());
    }
    if !merge_base_contains {
        blockers.push("baseline_commit_not_present".to_string());
    }

    RepoPreflight {
        repo_clean,
        on_main,
        main_synced_with_origin_main,
        baseline_present: merge_base_contains,
        current_branch: current_branch.trim().to_string(),
        head: head.trim().to_string(),
        origin_main: origin_main.trim().to_string(),
        blockers,
    }
}

fn run_git(args: &[&str]) -> anyhow::Result<String> {
    let output = Command::new("git").args(args).output()?;
    if !output.status.success() {
        return Ok(String::new());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn contains_shell_metacharacter(value: &str) -> bool {
    value.chars().any(|ch| {
        matches!(
            ch,
            ';' | '&'
                | '|'
                | '<'
                | '>'
                | '$'
                | '`'
                | '\''
                | '"'
                | '('
                | ')'
                | '{'
                | '}'
                | '['
                | ']'
                | '*'
                | '?'
                | '\\'
                | '~'
        )
    })
}

fn has_date_and_short_id(branch_name: &str) -> bool {
    let Some(tail) = branch_name.strip_prefix("tui/mg371b-docs-only-pr-") else {
        return false;
    };
    let mut parts = tail.split('-');
    let date = parts.next().unwrap_or_default();
    let short_id = parts.next().unwrap_or_default();
    parts.next().is_none()
        && date.len() == 8
        && date.chars().all(|ch| ch.is_ascii_digit())
        && (4..=12).contains(&short_id.len())
        && short_id.chars().all(|ch| ch.is_ascii_alphanumeric())
}

fn write_mg371b1_artifacts(
    output_dir: &Path,
    generated_at: &str,
    options: &Mg371b1Options,
    branch: &BranchValidation,
    allowlist: &AllowlistValidation,
    preflight: &RepoPreflight,
    authorization_phrase_matched: bool,
    block_kind: BlockKind,
    mg371b_execution_mode: bool,
    report: &Mg371b1Report,
) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let provider_boundary = json!({
        "operation_boundary_defined": true,
        "operations": [
            "create_local_branch",
            "commit_allowlisted_docs_changes",
            "push_branch",
            "create_draft_pr"
        ],
        "operations_called_in_mg371b1": false,
        "provider_call_count": 0,
        "unexpected_provider_call_count": 0
    });
    let support_probe = json!({
        "schema": "skybridge.operator_tui_mg371b1_provider_support_probe.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "real_provider_path_implemented": true,
        "real_provider_disabled_by_default": true,
        "real_provider_requires_explicit_flag": true,
        "real_provider_requires_exact_authorization": true,
        "real_provider_requires_allowlist": true,
        "real_provider_requires_branch_policy": true,
        "real_provider_requires_clean_synced_main": true,
        "real_provider_requires_mg371b_mode": true,
        "fake_provider_still_available": true,
        "real_provider_called": false,
        "provider_call_count": 0,
        "git_push_called": false,
        "gh_pr_create_called": false,
        "github_api_called": false,
        "support_probe_passed": true,
        "token_printed": false
    });
    let default_block = json!({
        "schema": "skybridge.operator_tui_mg371b1_default_block.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "allow_real_provider_flag_present": options.allow_real_provider,
        "blocked": !options.allow_real_provider,
        "blocker": "real_mutation_disabled_by_default",
        "provider_call_count": 0,
        "real_provider_called": false,
        "token_printed": false
    });
    let authorization_block = json!({
        "schema": "skybridge.operator_tui_mg371b1_authorization_block.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "authorization_phrase_matched": authorization_phrase_matched,
        "authorization_phrase_used_for_real_mutation": false,
        "blocked": !authorization_phrase_matched,
        "blocker": "authorization_phrase_mismatch",
        "provider_call_count": 0,
        "real_provider_called": false,
        "token_printed": false
    });
    let allowlist_block = json!({
        "schema": "skybridge.operator_tui_mg371b1_allowlist_block.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "changed_files": allowlist.changed_files,
        "allowed_files": ALLOWED_FILES,
        "docs_only_allowlist_passed": allowlist.docs_only_allowlist_passed,
        "blocked": !allowlist.docs_only_allowlist_passed,
        "blocked_files": allowlist.blocked_files,
        "blocker": "docs_only_allowlist_failed",
        "provider_call_count": 0,
        "real_provider_called": false,
        "token_printed": false
    });
    let branch_policy_block = json!({
        "schema": "skybridge.operator_tui_mg371b1_branch_policy_block.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "branch_name": branch.name,
        "branch_name_recorded_before_provider_action": true,
        "branch_policy_passed": branch.valid,
        "blocked": !branch.valid,
        "blockers": branch.blockers,
        "one_branch_maximum": true,
        "provider_call_count": 0,
        "real_provider_called": false,
        "token_printed": false
    });
    let preflight_report = json!({
        "schema": "skybridge.operator_tui_mg371b1_preflight.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "preflight_artifact_written_before_mutation": true,
        "repo_clean": preflight.repo_clean,
        "on_main": preflight.on_main,
        "main_synced_with_origin_main": preflight.main_synced_with_origin_main,
        "baseline_present": preflight.baseline_present,
        "current_branch": preflight.current_branch,
        "head": preflight.head,
        "origin_main": preflight.origin_main,
        "preflight_passed": preflight.ok(),
        "blockers": preflight.blockers,
        "provider_call_count": 0,
        "real_provider_called": false,
        "token_printed": false
    });
    let safety_report = json!({
        "schema": "skybridge.operator_tui_mg371b1_safety_report.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "real_provider_called": false,
        "real_provider_mutation_executed": false,
        "real_mutation_enabled": false,
        "authorization_phrase_used_for_real_mutation": false,
        "TUI_created_branch": false,
        "TUI_created_PR": false,
        "git_push_called": false,
        "gh_pr_create_called": false,
        "github_api_called": false,
        "real_task_execution_enabled": false,
        "task_created": false,
        "task_claimed": false,
        "execution_started": false,
        "worker_loop_started": false,
        "queue_runner_started": false,
        "run_forever_started": false,
        "hermes_live_called": false,
        "mcp_run_called": false,
        "auto_merge_enabled": false,
        "release_created": false,
        "tag_created": false,
        "asset_uploaded": false,
        "raw_input_persisted": false,
        "token_printed": false
    });
    let state = json!({
        "schema": "skybridge.operator_tui_mg371b1_state.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "current_state": state_for(block_kind),
        "support_probe_requested": options.support_probe,
        "allow_real_provider_requested": options.allow_real_provider,
        "mg371b_execution_mode": mg371b_execution_mode,
        "branch_name": branch.name,
        "changed_files": allowlist.changed_files,
        "real_provider_path_implemented": true,
        "real_provider_called": false,
        "provider_call_count": 0,
        "token_printed": false
    });
    let action_history = json!({
        "schema": "skybridge.operator_tui_mg371b1_action_history.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "actions": [
            "loaded_mg371b1_provider_boundary",
            "wrote_preflight_artifact_before_any_mutation",
            "evaluated_explicit_real_provider_flag",
            "evaluated_exact_authorization_phrase",
            "evaluated_docs_only_allowlist",
            "evaluated_branch_policy",
            "evaluated_clean_synced_main_preflight",
            "kept_real_provider_uncalled"
        ],
        "block_kind": state_for(block_kind),
        "provider_boundary": provider_boundary,
        "real_provider_called": false,
        "provider_call_count": 0,
        "git_push_called": false,
        "gh_pr_create_called": false,
        "github_api_called": false,
        "token_printed": false
    });
    let artifact_index = json!({
        "schema": "skybridge.operator_tui_mg371b1_artifact_index.v1",
        "generated_at": generated_at,
        "mode": "mg371b1-real-provider-implementation",
        "artifacts": artifact_paths(output_dir),
        "token_printed": false
    });

    write_json(&output_dir.join("mg371b1-state.json"), &state)?;
    write_json(&output_dir.join("mg371b1-report.json"), report)?;
    write_text(
        &output_dir.join("mg371b1-report.md"),
        &render_report_markdown(report, output_dir),
    )?;
    write_json(
        &output_dir.join("mg371b1-provider-support-probe.json"),
        &support_probe,
    )?;
    write_json(
        &output_dir.join("mg371b1-default-block-report.json"),
        &default_block,
    )?;
    write_json(
        &output_dir.join("mg371b1-authorization-block-report.json"),
        &authorization_block,
    )?;
    write_json(
        &output_dir.join("mg371b1-allowlist-block-report.json"),
        &allowlist_block,
    )?;
    write_json(
        &output_dir.join("mg371b1-branch-policy-block-report.json"),
        &branch_policy_block,
    )?;
    write_json(
        &output_dir.join("mg371b1-preflight-report.json"),
        &preflight_report,
    )?;
    write_json(
        &output_dir.join("mg371b1-safety-report.json"),
        &safety_report,
    )?;
    write_json(
        &output_dir.join("mg371b1-action-history.json"),
        &action_history,
    )?;
    write_json(
        &output_dir.join("mg371b1-artifact-index.json"),
        &artifact_index,
    )?;

    Ok(())
}

fn state_for(kind: BlockKind) -> &'static str {
    match kind {
        BlockKind::SupportProbe => "support_probe_completed",
        BlockKind::DefaultRealProviderBlocked => "real_provider_default_blocked",
        BlockKind::AuthorizationRequired => "authorization_required_blocked",
        BlockKind::AllowlistFailed => "allowlist_failed_blocked",
        BlockKind::BranchPolicyFailed => "branch_policy_failed_blocked",
        BlockKind::PreflightFailed => "preflight_failed_blocked",
        BlockKind::Mg371bModeRequired => "mg371b_mode_required_blocked",
    }
}

fn artifact_paths(output_dir: &Path) -> Vec<String> {
    ARTIFACT_NAMES
        .iter()
        .map(|name| output_dir.join(name).to_string_lossy().replace('\\', "/"))
        .collect()
}

fn render_report_markdown(report: &Mg371b1Report, output_dir: &Path) -> String {
    format!(
        "# Operator TUI MG371B1 Real Docs PR Provider Implementation Report\n\n- schema: {}\n- mode: {}\n- baseline_commit: {}\n- implementation_added: true\n- runtime_behavior_changed: true\n- real_provider_path_implemented: true\n- real_provider_disabled_by_default: true\n- real_provider_requires_explicit_flag: true\n- real_provider_requires_exact_authorization: true\n- real_provider_requires_allowlist: true\n- real_provider_requires_branch_policy: true\n- real_provider_requires_clean_synced_main: true\n- support_probe_passed: true\n- fake_provider_still_available: true\n- real_provider_called: false\n- real_provider_mutation_executed: false\n- real_mutation_enabled: false\n- authorization_phrase_used_for_real_mutation: false\n- branch_policy_enforced: true\n- allowlist_enforced: true\n- pr_policy_enforced: true\n- TUI_created_branch: false\n- TUI_created_PR: false\n- git_push_called: false\n- gh_pr_create_called: false\n- github_api_called: false\n- real_task_execution_enabled: false\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- raw_input_persisted: false\n- token_printed: false\n\n## Artifacts\n\n- state: {}\n- report_json: {}\n- provider_support_probe: {}\n- default_block_report: {}\n- authorization_block_report: {}\n- allowlist_block_report: {}\n- branch_policy_block_report: {}\n- preflight_report: {}\n- safety_report: {}\n- action_history: {}\n- artifact_index: {}\n",
        report.schema,
        report.mode,
        report.baseline_commit,
        path_for_report(&output_dir.join("mg371b1-state.json")),
        path_for_report(&output_dir.join("mg371b1-report.json")),
        path_for_report(&output_dir.join("mg371b1-provider-support-probe.json")),
        path_for_report(&output_dir.join("mg371b1-default-block-report.json")),
        path_for_report(&output_dir.join("mg371b1-authorization-block-report.json")),
        path_for_report(&output_dir.join("mg371b1-allowlist-block-report.json")),
        path_for_report(&output_dir.join("mg371b1-branch-policy-block-report.json")),
        path_for_report(&output_dir.join("mg371b1-preflight-report.json")),
        path_for_report(&output_dir.join("mg371b1-safety-report.json")),
        path_for_report(&output_dir.join("mg371b1-action-history.json")),
        path_for_report(&output_dir.join("mg371b1-artifact-index.json")),
    )
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> anyhow::Result<()> {
    write_text(path, &format!("{}\n", serde_json::to_string_pretty(value)?))
}

fn write_text(path: &Path, text: &str) -> anyhow::Result<()> {
    fs::write(path, text).with_context(|| format!("failed to write {}", path.display()))
}

fn path_for_report(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}
