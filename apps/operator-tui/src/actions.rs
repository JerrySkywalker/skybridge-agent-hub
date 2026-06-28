use crate::model::ActionStatus;

const DISABLED_REASONS: [&str; 4] = [
    "action_disabled_in_mg368a",
    "requires_later_reviewed_gate",
    "execution_apply_disabled",
    "mutation_not_allowed_in_fixture",
];

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum Action {
    Refresh,
    CopySafeSummary,
    GenerateCandidateFixture,
    ValidateCandidate,
    AppendCandidate,
    PreviewBoundedAction,
    StartOneGoal,
    SafePause,
    AbortTerminate,
    Quit,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum ActionOutcome {
    Allowed(&'static str),
    Blocked {
        action: &'static str,
        reasons: Vec<&'static str>,
    },
}

impl Action {
    pub fn all() -> Vec<Action> {
        vec![
            Action::Refresh,
            Action::CopySafeSummary,
            Action::GenerateCandidateFixture,
            Action::ValidateCandidate,
            Action::AppendCandidate,
            Action::PreviewBoundedAction,
            Action::StartOneGoal,
            Action::SafePause,
            Action::AbortTerminate,
            Action::Quit,
        ]
    }

    pub fn action_id(self) -> &'static str {
        match self {
            Action::Refresh => "refresh_fixture_state",
            Action::CopySafeSummary => "copy_safe_summary",
            Action::GenerateCandidateFixture => "generate_candidate_fixture",
            Action::ValidateCandidate => "validate_candidate",
            Action::AppendCandidate => "append_candidate",
            Action::PreviewBoundedAction => "preview_bounded_action",
            Action::StartOneGoal => "start_one_goal",
            Action::SafePause => "safe_pause",
            Action::AbortTerminate => "abort_terminate",
            Action::Quit => "quit",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Action::Refresh => "r",
            Action::CopySafeSummary => "c",
            Action::GenerateCandidateFixture => "g",
            Action::ValidateCandidate => "v",
            Action::AppendCandidate => "a",
            Action::PreviewBoundedAction => "p",
            Action::StartOneGoal => "s",
            Action::SafePause => "h",
            Action::AbortTerminate => "x",
            Action::Quit => "q",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Action::Refresh => "Refresh",
            Action::CopySafeSummary => "Copy safe summary",
            Action::GenerateCandidateFixture => "Generate candidate fixture",
            Action::ValidateCandidate => "Validate candidate",
            Action::AppendCandidate => "Append candidate",
            Action::PreviewBoundedAction => "Preview bounded action",
            Action::StartOneGoal => "Start one goal",
            Action::SafePause => "Safe pause",
            Action::AbortTerminate => "Abort/terminate",
            Action::Quit => "Quit",
        }
    }

    pub fn enabled(self) -> bool {
        matches!(
            self,
            Action::Refresh | Action::CopySafeSummary | Action::Quit
        )
    }

    pub fn disabled_reasons(self) -> Vec<&'static str> {
        if self.enabled() {
            Vec::new()
        } else {
            DISABLED_REASONS.to_vec()
        }
    }

    pub fn status(self) -> ActionStatus {
        ActionStatus {
            action: self.action_id(),
            key: self.key(),
            label: self.label(),
            enabled: self.enabled(),
            disabled_reasons: self.disabled_reasons(),
        }
    }
}

pub fn active_action_statuses() -> Vec<ActionStatus> {
    Action::all()
        .into_iter()
        .filter(|action| action.enabled())
        .map(Action::status)
        .collect()
}

pub fn disabled_action_statuses() -> Vec<ActionStatus> {
    Action::all()
        .into_iter()
        .filter(|action| !action.enabled())
        .map(Action::status)
        .collect()
}

pub fn handle_action(action: Action) -> ActionOutcome {
    if action.enabled() {
        return ActionOutcome::Allowed(action.action_id());
    }

    ActionOutcome::Blocked {
        action: action.action_id(),
        reasons: action.disabled_reasons(),
    }
}
