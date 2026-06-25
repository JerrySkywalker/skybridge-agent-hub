$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$NativeReportRunnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"

function New-NativeReportSmokeContext {
  param([string]$Prefix = "smoke-codex-native-report")
  $taskId = "$Prefix-" + [Guid]::NewGuid().ToString("n")
  $inputDir = ".agent/tmp/matlab-golden-trial/$taskId"
  $outputDir = ".agent/tmp/codex-analysis-report/$taskId"
  [pscustomobject]@{
    task_id = $taskId
    input_dir = $inputDir
    output_dir = $outputDir
    input_full = Join-Path $RepoRoot $inputDir
    output_full = Join-Path $RepoRoot $outputDir
    fake_codex_dir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-fake-codex-" + [Guid]::NewGuid().ToString("n"))
    old_path = $env:PATH
  }
}

function Write-NativeReportFixtureInputs {
  param($Context)
  New-Item -ItemType Directory -Force -Path $Context.input_full | Out-Null
  @{
    schema = "skybridge.matlab_sweep_manifest.v1"
    task_id = "live-matlab-golden-task-336-001"
    combination_count = 2
    parameter_grid_summary = "eta=[2,3]; h_km=[500]; P=[6]; combinations=2"
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Context.input_full "manifest.json") -Encoding UTF8
  @{
    schema = "skybridge.matlab_sweep_summary.v1"
    task_id = "live-matlab-golden-task-336-001"
    combination_count = 2
    completed_count = 2
    failed_count = 0
    validation_status = "passed"
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Context.input_full "summary.json") -Encoding UTF8
  @("eta,h_km,P,score", "2,500,6,0.024", "3,500,6,0.036") | Set-Content -LiteralPath (Join-Path $Context.input_full "metrics.csv") -Encoding UTF8
}

function New-NativeReportMarkdownLines {
  @(
    "# Codex Native Analysis Report",
    "",
    "This is a synthetic MATLAB golden trial runner validation, not a scientific conclusion.",
    "",
    "## Input Evidence",
    "",
    "- Manifest reviewed: manifest.json",
    "- Summary reviewed: summary.json",
    "- Metrics reviewed: metrics.csv",
    "",
    "## Parameter Grid And Metrics",
    "",
    "- expected_combination_count: 2",
    "- completed_count: 2",
    "- failed_count: 0",
    "- Metric interpretation: both bounded fixture rows completed with synthetic scores.",
    "",
    "## Validation Summary",
    "",
    "The native report satisfies the fixed runner validation contract.",
    "",
    "## Limitations",
    "",
    "This is runner validation only.",
    "",
    "## Safety Notes",
    "",
    "Process streams omitted.",
    "token_printed=false"
  )
}

function Set-FakeCodex {
  param($Context, [ValidateSet("valid-file", "valid-stdout", "invalid-file", "missing-report", "nonzero")] [string]$Mode)
  New-Item -ItemType Directory -Force -Path $Context.fake_codex_dir | Out-Null
  $path = Join-Path $Context.fake_codex_dir "codex.cmd"
  if ($Mode -eq "nonzero") {
    "@echo off`r`nexit /b 9`r`n" | Set-Content -LiteralPath $path -Encoding ASCII
    $env:PATH = "$($Context.fake_codex_dir);$($Context.old_path)"
    return
  }
  if ($Mode -eq "missing-report") {
    "@echo off`r`nexit /b 0`r`n" | Set-Content -LiteralPath $path -Encoding ASCII
    $env:PATH = "$($Context.fake_codex_dir);$($Context.old_path)"
    return
  }

  $lines = New-NativeReportMarkdownLines
  if ($Mode -eq "valid-stdout") {
    $body = @("@echo off") + ($lines | ForEach-Object { "echo $_" }) + @("exit /b 0")
    $body | Set-Content -LiteralPath $path -Encoding ASCII
    $env:PATH = "$($Context.fake_codex_dir);$($Context.old_path)"
    return
  }

  $writeLines = if ($Mode -eq "invalid-file") {
    @(
      "# Invalid Codex Native Report",
      "",
      "This is a synthetic MATLAB golden trial runner validation, not a scientific conclusion.",
      "",
      "## Safety Notes",
      "Raw stdout included: false"
    )
  } else {
    $lines
  }
  $cmd = @(
    "@echo off",
    "set OUT=",
    ":loop",
    "if ""%~1""=="""" goto done",
    "if ""%~1""==""-o"" (",
    "  set OUT=%~2",
    "  shift",
    "  shift",
    "  goto loop",
    ")",
    "shift",
    "goto loop",
    ":done",
    "if not ""%OUT%""=="""" ("
  )
  $first = $true
  foreach ($line in $writeLines) {
    $safeLine = $line.Replace("^", "^^").Replace("&", "^&").Replace("|", "^|").Replace("<", "^<").Replace(">", "^>")
    if ($first) {
      $cmd += "  > ""%OUT%"" echo $safeLine"
      $first = $false
    } else {
      $cmd += "  >> ""%OUT%"" echo $safeLine"
    }
  }
  $cmd += ")"
  $cmd += "exit /b 0"
  $cmd | Set-Content -LiteralPath $path -Encoding ASCII
  $env:PATH = "$($Context.fake_codex_dir);$($Context.old_path)"
}

function Invoke-NativeReportRunnerApply {
  param($Context)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $NativeReportRunnerScript `
    -Command apply `
    -TaskId $Context.task_id `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$($Context.input_dir)/manifest.json" `
    -InputSummary "$($Context.input_dir)/summary.json" `
    -InputMetrics "$($Context.input_dir)/metrics.csv" `
    -OutputDir $Context.output_dir `
    -Confirm `
    -ConfirmationText "I_UNDERSTAND_RUN_ONE_FIXED_CODEX_ANALYSIS_REPORT_ONLY" `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Invoke-NativeReportRunnerValidate {
  param($Context)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $NativeReportRunnerScript `
    -Command validate-output `
    -TaskId $Context.task_id `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$($Context.input_dir)/manifest.json" `
    -InputSummary "$($Context.input_dir)/summary.json" `
    -InputMetrics "$($Context.input_dir)/metrics.csv" `
    -OutputDir $Context.output_dir `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Remove-NativeReportSmokeContext {
  param($Context)
  $env:PATH = $Context.old_path
  Remove-Item -LiteralPath $Context.input_full -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Context.output_full -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Context.fake_codex_dir -Recurse -Force -ErrorAction SilentlyContinue
}
