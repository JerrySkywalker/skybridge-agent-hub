[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $PSScriptRoot "skybridge-matlab-doctor.ps1"
$cases = @(
  @{ fixture = "executable-missing"; category = "matlab_executable_not_found" },
  @{ fixture = "batch-unsupported"; category = "matlab_batch_unsupported" },
  @{ fixture = "license-unavailable"; category = "matlab_license_unavailable" },
  @{ fixture = "startup-profile-failed"; category = "matlab_startup_profile_failed" },
  @{ fixture = "working-directory-failed"; category = "matlab_working_directory_failed" },
  @{ fixture = "output-write-failed"; category = "matlab_output_write_failed" },
  @{ fixture = "fixed-script-failed"; category = "matlab_fixed_script_failed" },
  @{ fixture = "unknown-startup-failure"; category = "unknown_matlab_startup_failure" }
)

$results = @()
foreach ($case in $cases) {
  $doctorId = "classification-" + $case.fixture + "-" + [Guid]::NewGuid().ToString("n")
  $outputDir = ".agent/tmp/matlab-doctor/$doctorId"
  $fullOutputDir = Join-Path $RepoRoot $outputDir
  try {
    $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
      -Command fixture `
      -FixtureCase $case.fixture `
      -OutputDir $outputDir `
      -Json
    $text = ($raw | Out-String).Trim()
    Assert-NoUnsafeText $text
    $doctor = $text | ConvertFrom-Json
    if ([string]$doctor.schema -ne "skybridge.matlab_doctor.v1") { throw "Unexpected doctor schema for $($case.fixture)." }
    if ($doctor.ok -ne $false) { throw "Classification fixture should fail for $($case.fixture)." }
    if ([string]$doctor.failure_category -ne [string]$case.category) {
      throw "Expected $($case.category) for $($case.fixture), got $($doctor.failure_category)."
    }
    if ([string]::IsNullOrWhiteSpace([string]$doctor.recommended_next_action)) { throw "Missing recommended_next_action." }
    Assert-False $doctor.raw_stdout_included "raw_stdout_included $($case.fixture)"
    Assert-False $doctor.raw_stderr_included "raw_stderr_included $($case.fixture)"
    Assert-False $doctor.claim_created "claim_created $($case.fixture)"
    Assert-False $doctor.execution_started "execution_started $($case.fixture)"
    Assert-False $doctor.codex_run_called "codex_run_called $($case.fixture)"
    Assert-False $doctor.arbitrary_shell_enabled "arbitrary_shell_enabled $($case.fixture)"
    Assert-False $doctor.worker_loop_started "worker_loop_started $($case.fixture)"
    Assert-TokenPrintedFalse $doctor
    $results += [pscustomobject]@{
      fixture = $case.fixture
      category = $doctor.failure_category
      recommended_next_action_present = $true
    }
  } finally {
    Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "matlab-doctor-classification"
  cases = $results
  no_task_claim = $true
  no_codex = $true
  no_worker_loop = $true
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
