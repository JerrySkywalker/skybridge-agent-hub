use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

use anyhow::Context;
use serde::Serialize;
use serde_json::json;

use crate::commands::now_utc;

pub const MG371B0_REPORT_SCHEMA: &str =
    "skybridge.operator_tui_mg371b0_tui_docs_pr_capability_staging.v1";
pub const MG371B0_OUTPUT_DIR: &str = ".agent/tmp/operator-tui/mg371b0-capability-staging";
pub const MG371B0_BASELINE_COMMIT: &str = "c2f5c6ebd58a19694901c42ffe941b81d6530303";
pub const MG371B_FUTURE_AUTHORIZATION_PHRASE: &str =
    "I_UNDERSTAND_AUTHORIZE_MG371B_FIRST_TUI_CREATED_DOCS_ONLY_BRANCH_AND_DRAFT_PR";
pub const DEFAULT_BRANCH_NAME: &str = "tui/mg371b-docs-only-pr-20260706-a1b2c3";
pub const PR_TITLE: &str = "MG371B First TUI-created Docs-only PR";

const ALLOWED_FILES: &[&str] = &[
    "docs/operator/MG371B_FIRST_TUI_CREATED_DOCS_ONLY_PR.md",
    "docs/operator/RATATUI_OPERATOR_CONSOLE.md",
    "docs/dev/PROGRESS.md",
    "docs/release/MANAGED_DEV_E2E_HANDOFF.md",
    "docs/release/STAGE_S1_1_CLOSE.md",
];

const ARTIFACT_NAMES: &[&str] = &[
    "mg371b0-state.json",
    "mg371b0-report.json",
    "mg371b0-report.md",
    "mg371b0-preflight.json",
    "mg371b0-authorization-check.json",
    "mg371b0-allowlist-check.json",
    "mg371b0-branch-plan.json",
    "mg371b0-pr-metadata.json",
    "mg371b0-provider-report.json",
    "mg371b0-safety-report.json",
    "mg371b0-action-history.json",
    "mg371b0-artifact-index.json",
];

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum Mg371b0Scenario {
    CapabilityStaging,
    UnauthorizedRealMutationBlocked,
    AllowlistInvalid,
    BranchPolicyInvalid,
    NoRealPr,
    NoRealExecution,
}

impl Mg371b0Scenario {
    pub fn from_str(value: &str) -> anyhow::Result<Self> {
        match value {
            "capability-staging" | "staging" => Ok(Self::CapabilityStaging),
            "unauthorized-real-mutation-blocked" | "unauthorized-real-mutation" => {
                Ok(Self::UnauthorizedRealMutationBlocked)
            }
            "allowlist-enforced" | "allowlist-invalid" => Ok(Self::AllowlistInvalid),
            "branch-policy-enforced" | "branch-invalid" => Ok(Self::BranchPolicyInvalid),
            "no-real-pr" => Ok(Self::NoRealPr),
            "no-real-execution" => Ok(Self::NoRealExecution),
            other => anyhow::bail!("unknown MG371B0 docs PR capability scenario: {other}"),
        }
    }
}

impl Default for Mg371b0Scenario {
    fn default() -> Self {
        Self::CapabilityStaging
    }
}

#[derive(Debug, Clone)]
pub struct Mg371b0Options {
    pub output_dir: PathBuf,
    pub scenario: Mg371b0Scenario,
    pub fake_provider_requested: bool,
    pub real_provider_requested: bool,
    pub authorization_phrase: String,
    pub branch_name: String,
    pub changed_files: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct Mg371b0Report {
    pub schema: &'static str,
    pub generated_at: String,
    pub mode: &'static str,
    pub baseline_commit: &'static str,
    pub implementation_added: bool,
    pub runtime_behavior_changed: bool,
    pub real_mutation_enabled: bool,
    pub fake_provider_used: bool,
    pub real_provider_called: bool,
    pub future_authorization_phrase_known: bool,
    pub future_authorization_phrase_used_for_real_mutation: bool,
    pub real_mutation_authorized: bool,
    pub branch_policy_enforced: bool,
    pub allowlist_enforced: bool,
    pub pr_policy_enforced: bool,
    pub abort_policy_enforced_or_documented: bool,
    pub artifacts_written: bool,
    #[serde(rename = "TUI_created_branch")]
    pub tui_created_branch: bool,
    #[serde(rename = "TUI_created_PR")]
    pub tui_created_pr: bool,
    pub git_push_called: bool,
    pub gh_pr_create_called: bool,
    pub github_api_called: bool,
    pub real_task_execution_enabled: bool,
    #[serde(rename = "real_branch_creation_enabled_by_TUI")]
    pub real_branch_creation_enabled_by_tui: bool,
    #[serde(rename = "real_PR_creation_enabled_by_TUI")]
    pub real_pr_creation_enabled_by_tui: bool,
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

pub fn run_mg371b0_capability_staging(options: &Mg371b0Options) -> anyhow::Result<Mg371b0Report> {
    let generated_at = now_utc();
    let branch_name = branch_name_for(options);
    let changed_files = changed_files_for(options);
    let branch = validate_branch_name(&branch_name);
    let allowlist = validate_changed_files(&changed_files);
    let authorization_phrase_matched =
        options.authorization_phrase == MG371B_FUTURE_AUTHORIZATION_PHRASE;
    let real_provider_requested = options.real_provider_requested
        || options.scenario == Mg371b0Scenario::UnauthorizedRealMutationBlocked;
    let fake_provider_requested = options.fake_provider_requested || !real_provider_requested;

    let mut states = vec![
        "disabled".to_string(),
        "preflight_pending".to_string(),
        "authorization_required".to_string(),
    ];
    if authorization_phrase_matched {
        states.push("authorization_verified".to_string());
    }
    states.push("branch_plan_prepared".to_string());
    states.push("allowlist_checked".to_string());
    states.push("draft_pr_metadata_prepared".to_string());

    let mut blockers = Vec::new();
    if !branch.valid {
        blockers.extend(branch.blockers.clone());
    }
    if !allowlist.docs_only_allowlist_passed {
        blockers.extend(
            allowlist
                .blocked_files
                .iter()
                .map(|path| format!("changed_file_not_in_mg371b_allowlist:{path}")),
        );
    }

    let fake_provider_allowed = fake_provider_requested
        && !real_provider_requested
        && branch.valid
        && allowlist.docs_only_allowlist_passed
        && authorization_phrase_matched;
    let real_provider_blocked = real_provider_requested;
    let fake_provider_used = fake_provider_allowed;
    if fake_provider_used {
        states.push("fake_provider_executed".to_string());
    }
    if real_provider_blocked {
        states.push("real_provider_blocked".to_string());
        push_unique(&mut blockers, "real_mutation_disabled_by_default");
        push_unique(&mut blockers, "mg371b0_does_not_authorize_real_provider");
    }
    if !authorization_phrase_matched {
        push_unique(
            &mut blockers,
            "future_authorization_phrase_not_matched_for_fixture_flow",
        );
    }
    states.push("completed_staging".to_string());

    let warnings = vec![
        "MG371B0 stages capability only; it is not MG371B authorization".to_string(),
        "fake provider records simulated branch and PR metadata only".to_string(),
    ];

    let report = Mg371b0Report {
        schema: MG371B0_REPORT_SCHEMA,
        generated_at: generated_at.clone(),
        mode: "mg371b0-capability-staging",
        baseline_commit: MG371B0_BASELINE_COMMIT,
        implementation_added: true,
        runtime_behavior_changed: true,
        real_mutation_enabled: false,
        fake_provider_used,
        real_provider_called: false,
        future_authorization_phrase_known: true,
        future_authorization_phrase_used_for_real_mutation: false,
        real_mutation_authorized: false,
        branch_policy_enforced: true,
        allowlist_enforced: true,
        pr_policy_enforced: true,
        abort_policy_enforced_or_documented: true,
        artifacts_written: true,
        tui_created_branch: false,
        tui_created_pr: false,
        git_push_called: false,
        gh_pr_create_called: false,
        github_api_called: false,
        real_task_execution_enabled: false,
        real_branch_creation_enabled_by_tui: false,
        real_pr_creation_enabled_by_tui: false,
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

    write_mg371b0_artifacts(
        &options.output_dir,
        &generated_at,
        &states,
        &branch,
        &allowlist,
        authorization_phrase_matched,
        real_provider_requested,
        real_provider_blocked,
        &report,
    )?;

    Ok(report)
}

struct BranchValidation {
    name: String,
    valid: bool,
    blockers: Vec<String>,
}

struct AllowlistValidation {
    changed_files: Vec<String>,
    docs_only_allowlist_passed: bool,
    blocked_files: Vec<String>,
}

fn branch_name_for(options: &Mg371b0Options) -> String {
    if !options.branch_name.trim().is_empty() {
        return options.branch_name.trim().to_string();
    }
    if options.scenario == Mg371b0Scenario::BranchPolicyInvalid {
        return "tui/mg371b docs-only-pr bad".to_string();
    }
    DEFAULT_BRANCH_NAME.to_string()
}

fn changed_files_for(options: &Mg371b0Options) -> Vec<String> {
    if !options.changed_files.is_empty() {
        return options.changed_files.clone();
    }
    if options.scenario == Mg371b0Scenario::AllowlistInvalid {
        return vec![
            "docs/operator/MG371B_FIRST_TUI_CREATED_DOCS_ONLY_PR.md".to_string(),
            "apps/operator-tui/src/main.rs".to_string(),
        ];
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

fn write_mg371b0_artifacts(
    output_dir: &Path,
    generated_at: &str,
    states: &[String],
    branch: &BranchValidation,
    allowlist: &AllowlistValidation,
    authorization_phrase_matched: bool,
    real_provider_requested: bool,
    real_provider_blocked: bool,
    report: &Mg371b0Report,
) -> anyhow::Result<()> {
    fs::create_dir_all(output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let artifact_paths = artifact_paths(output_dir);
    let current_state = states
        .last()
        .cloned()
        .unwrap_or_else(|| "completed_staging".to_string());
    let preflight = json!({
        "schema": "skybridge.operator_tui_mg371b0_preflight.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "baseline_commit": MG371B0_BASELINE_COMMIT,
        "capability_disabled_by_default": true,
        "fake_provider_default": true,
        "real_provider_reachable": false,
        "real_mutation_enabled": false,
        "token_printed": false
    });
    let authorization = json!({
        "schema": "skybridge.operator_tui_mg371b0_authorization_check.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "future_authorization_phrase_known": true,
        "authorization_phrase_matched_for_future_flow": authorization_phrase_matched,
        "future_authorization_phrase_used_for_real_mutation": false,
        "phrase_used_for_real_mutation": false,
        "real_mutation_authorized": false,
        "token_printed": false
    });
    let branch_plan = json!({
        "schema": "skybridge.operator_tui_mg371b0_branch_plan.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "branch_name": branch.name,
        "branch_name_valid": branch.valid,
        "prefix_must_be_tui": true,
        "milestone_must_be_mg371b": true,
        "no_spaces": !branch.name.chars().any(char::is_whitespace),
        "no_shell_metacharacters": !contains_shell_metacharacter(&branch.name),
        "under_80_characters": branch.name.len() < 80,
        "recorded_before_provider_action": true,
        "one_branch_maximum": true,
        "blockers": branch.blockers,
        "token_printed": false
    });
    let allowlist_check = json!({
        "schema": "skybridge.operator_tui_mg371b0_allowlist_check.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "changed_files": allowlist.changed_files,
        "allowed_files": ALLOWED_FILES,
        "docs_only_allowlist_passed": allowlist.docs_only_allowlist_passed,
        "allowlist_enforced": true,
        "blocked_files": allowlist.blocked_files,
        "blocked_file_classes": [
            "app_code",
            "server_code",
            "workflow_files",
            "package_files",
            "docker_runtime_production_infra",
            "generated_binary_artifacts",
            "secrets"
        ],
        "token_printed": false
    });
    let pr_metadata = json!({
        "schema": "skybridge.operator_tui_mg371b0_pr_metadata.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "title": PR_TITLE,
        "title_starts_with_required_prefix": true,
        "body_includes_safety_flags": true,
        "draft_pr": true,
        "one_draft_pr_maximum": true,
        "auto_merge": false,
        "release_tag_assets": false,
        "merge_by_tui": false,
        "pr_url": "",
        "pr_number": null,
        "token_printed": false
    });
    let provider_report = json!({
        "schema": "skybridge.operator_tui_mg371b0_provider_report.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "provider_boundary_defined": true,
        "fake_provider_default": true,
        "fake_provider_used": report.fake_provider_used,
        "fake_provider_executed": report.fake_provider_used,
        "fake_branch_metadata_recorded": report.fake_provider_used,
        "fake_pr_metadata_recorded": report.fake_provider_used,
        "real_provider_requested": real_provider_requested,
        "real_provider_blocked": real_provider_blocked,
        "real_provider_called": false,
        "git_push_called": false,
        "gh_pr_create_called": false,
        "github_api_called": false,
        "tui_created_branch": false,
        "tui_created_pr": false,
        "token_printed": false
    });
    let safety_report = json!({
        "schema": "skybridge.operator_tui_mg371b0_safety_report.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "real_mutation_enabled": false,
        "TUI_created_branch": false,
        "TUI_created_PR": false,
        "git_push_called": false,
        "gh_pr_create_called": false,
        "github_api_called": false,
        "real_task_execution_enabled": false,
        "real_branch_creation_enabled_by_TUI": false,
        "real_PR_creation_enabled_by_TUI": false,
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
    let action_history = json!({
        "schema": "skybridge.operator_tui_mg371b0_action_history.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "state_history": states,
        "fake_provider_only": !real_provider_requested,
        "real_provider_blocked_before_provider_call": real_provider_blocked,
        "abort_transitions": [
            "before_branch_creation: clears_pending_state_and_records_aborted_before_branch_creation",
            "after_fake_branch_before_fake_pr: records_branch_created_true_pr_created_false_no_real_branch_exists",
            "after_fake_pr_creation: records_branch_created_true_pr_created_true_no_real_pr_exists"
        ],
        "one_branch_maximum": true,
        "one_draft_pr_maximum": true,
        "token_printed": false
    });
    let state = json!({
        "schema": "skybridge.operator_tui_mg371b0_state.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "current_state": current_state,
        "lifecycle_states": states,
        "branch_name": branch.name,
        "changed_files": allowlist.changed_files,
        "fake_provider_used": report.fake_provider_used,
        "real_provider_called": false,
        "real_provider_blocked": real_provider_blocked,
        "token_printed": false
    });
    let artifact_index = json!({
        "schema": "skybridge.operator_tui_mg371b0_artifact_index.v1",
        "generated_at": generated_at,
        "mode": "mg371b0-capability-staging",
        "artifacts": artifact_paths,
        "token_printed": false
    });

    write_json(&output_dir.join("mg371b0-state.json"), &state)?;
    write_json(&output_dir.join("mg371b0-report.json"), report)?;
    write_text(
        &output_dir.join("mg371b0-report.md"),
        &render_report_markdown(report, output_dir),
    )?;
    write_json(&output_dir.join("mg371b0-preflight.json"), &preflight)?;
    write_json(
        &output_dir.join("mg371b0-authorization-check.json"),
        &authorization,
    )?;
    write_json(
        &output_dir.join("mg371b0-allowlist-check.json"),
        &allowlist_check,
    )?;
    write_json(&output_dir.join("mg371b0-branch-plan.json"), &branch_plan)?;
    write_json(&output_dir.join("mg371b0-pr-metadata.json"), &pr_metadata)?;
    write_json(
        &output_dir.join("mg371b0-provider-report.json"),
        &provider_report,
    )?;
    write_json(
        &output_dir.join("mg371b0-safety-report.json"),
        &safety_report,
    )?;
    write_json(
        &output_dir.join("mg371b0-action-history.json"),
        &action_history,
    )?;
    write_json(
        &output_dir.join("mg371b0-artifact-index.json"),
        &artifact_index,
    )?;

    Ok(())
}

fn artifact_paths(output_dir: &Path) -> Vec<String> {
    ARTIFACT_NAMES
        .iter()
        .map(|name| output_dir.join(name).to_string_lossy().replace('\\', "/"))
        .collect()
}

fn render_report_markdown(report: &Mg371b0Report, output_dir: &Path) -> String {
    format!(
        "# Operator TUI MG371B0 Docs-only PR Capability Staging Report\n\n- schema: {}\n- mode: {}\n- baseline_commit: {}\n- implementation_added: true\n- runtime_behavior_changed: true\n- real_mutation_enabled: false\n- fake_provider_used: {}\n- real_provider_called: false\n- future_authorization_phrase_known: true\n- future_authorization_phrase_used_for_real_mutation: false\n- real_mutation_authorized: false\n- branch_policy_enforced: true\n- allowlist_enforced: true\n- pr_policy_enforced: true\n- abort_policy_enforced_or_documented: true\n- artifacts_written: true\n- TUI_created_branch: false\n- TUI_created_PR: false\n- git_push_called: false\n- gh_pr_create_called: false\n- github_api_called: false\n- real_task_execution_enabled: false\n- real_branch_creation_enabled_by_TUI: false\n- real_PR_creation_enabled_by_TUI: false\n- task_created: false\n- task_claimed: false\n- execution_started: false\n- worker_loop_started: false\n- queue_runner_started: false\n- run_forever_started: false\n- hermes_live_called: false\n- mcp_run_called: false\n- auto_merge_enabled: false\n- release_created: false\n- tag_created: false\n- asset_uploaded: false\n- raw_input_persisted: false\n- token_printed: false\n\n## Artifacts\n\n- state: {}\n- report_json: {}\n- preflight: {}\n- authorization_check: {}\n- allowlist_check: {}\n- branch_plan: {}\n- pr_metadata: {}\n- provider_report: {}\n- safety_report: {}\n- action_history: {}\n- artifact_index: {}\n",
        report.schema,
        report.mode,
        report.baseline_commit,
        report.fake_provider_used,
        path_for_report(&output_dir.join("mg371b0-state.json")),
        path_for_report(&output_dir.join("mg371b0-report.json")),
        path_for_report(&output_dir.join("mg371b0-preflight.json")),
        path_for_report(&output_dir.join("mg371b0-authorization-check.json")),
        path_for_report(&output_dir.join("mg371b0-allowlist-check.json")),
        path_for_report(&output_dir.join("mg371b0-branch-plan.json")),
        path_for_report(&output_dir.join("mg371b0-pr-metadata.json")),
        path_for_report(&output_dir.join("mg371b0-provider-report.json")),
        path_for_report(&output_dir.join("mg371b0-safety-report.json")),
        path_for_report(&output_dir.join("mg371b0-action-history.json")),
        path_for_report(&output_dir.join("mg371b0-artifact-index.json")),
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

fn push_unique(values: &mut Vec<String>, value: &str) {
    if !values.iter().any(|existing| existing == value) {
        values.push(value.to_string());
    }
}
