[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$doctorScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-matlab-doctor.ps1")
$configScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-matlab-local-config.ps1")

foreach ($needle in @(
  "MG335 MATLAB runtime repair status",
  "MG335 configured MATLAB executable",
  "MG335 MATLAB executable source",
  "MG335 MATLAB config path",
  "MG335 run mode",
  "MG335 fallback_supported",
  "MG335 license_status",
  "MG335 minimal_compute_ok",
  "MG335 failure category",
  "MG335 recommended next action",
  "MG335 local config confirmation",
  "MG335 MATLAB local config preview",
  "MG335 MATLAB local config apply unavailable in Desktop",
  "MG335 MATLAB doctor apply unavailable in Desktop",
  "MG335 task claim disabled"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop MATLAB runtime repair panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureMatlabRuntimeRepairDoctor",
  "fixtureMatlabLocalConfigPreview",
  "MATLAB_LOCAL_CONFIG_CONFIRMATION_TEXT",
  "I_UNDERSTAND_CONFIGURE_LOCAL_MATLAB_EXECUTABLE_ONLY",
  "fallback_supported",
  "recommended_next_action",
  "matlab_license_unavailable",
  "modifies_matlab_installation: false",
  "modifies_system_path: false",
  "modifies_registry: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) {
    throw "Client MATLAB runtime repair fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "fallback_supported",
  "recommended_next_action",
  "matlab_executable_not_found",
  "matlab_batch_unsupported",
  "matlab_license_unavailable",
  "matlab_startup_profile_failed",
  "matlab_working_directory_failed",
  "matlab_output_write_failed",
  "matlab_fixed_script_failed",
  "unknown_matlab_startup_failure",
  "raw_stdout_included = `$false",
  "raw_stderr_included = `$false",
  "token_printed = `$false"
)) {
  if ($doctorScript -notmatch [regex]::Escape($needle)) {
    throw "MATLAB doctor classification script missing text: $needle"
  }
}

foreach ($needle in @(
  "skybridge.matlab_local_config.v1",
  "I_UNDERSTAND_CONFIGURE_LOCAL_MATLAB_EXECUTABLE_ONLY",
  "SKYBRIDGE_MATLAB_EXE",
  "SKYBRIDGE_MATLAB_RUN_MODE",
  "modifies_matlab_installation = `$false",
  "modifies_system_path = `$false",
  "modifies_registry = `$false",
  "matlab_invoked = `$false",
  "token_printed = `$false"
)) {
  if ($configScript -notmatch [regex]::Escape($needle)) {
    throw "MATLAB local config script missing text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-matlab-runtime-repair"
  desktop_live_apply_enabled = $false
  arbitrary_matlab_command_box = $false
  arbitrary_shell_enabled = $false
  task_claim_button = $false
  codex_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
