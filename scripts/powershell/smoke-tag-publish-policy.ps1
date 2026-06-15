. "$PSScriptRoot\smoke-productization-common.ps1"
$policy = Invoke-JsonScript "skybridge-release-workflow-guard.ps1" @("-Command", "classify-tag-triggers")
Assert-TokenPrintedFalse $policy
Assert-True $policy.tags_may_trigger_existing_workflows "tags_may_trigger_existing_workflows"
Assert-False $policy.manual_github_release_creation_allowed "manual_github_release_creation_allowed"
Assert-False $policy.manual_artifact_upload_allowed "manual_artifact_upload_allowed"
Complete-Smoke "tag-publish-policy"
