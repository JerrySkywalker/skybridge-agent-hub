. "$PSScriptRoot\smoke-productization-common.ps1"
$candidate = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "apply-candidate")
Assert-False $candidate.starts_codex_worker "starts_codex_worker"
foreach ($component in @($candidate.components)) { Assert-False $component.starts_codex_worker "component.starts_codex_worker" }
Complete-Smoke "local-runtime-apply-candidate-no-codex-worker"
