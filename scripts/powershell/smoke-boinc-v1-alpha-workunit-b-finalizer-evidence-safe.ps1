$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-b-finalizer-evidence -Json | Out-String).Trim()
if ($json -match 'token_printed"\s*:\s*true|raw_prompt|raw_stdout|raw_stderr|raw_worker_log|raw_codex_transcript|raw_ci_log|Authorization\s*[:=]\s*Bearer') { throw "unsafe Workunit B finalizer evidence output" }
$obj = $json | ConvertFrom-Json
if ($obj.alpha_id -ne "boinc-v1-alpha-215" -or $obj.workunit_b_id -ne "boinc-v1-alpha-215-workunit-b") { throw "unexpected Workunit B finalizer evidence identity" }
if ($obj.changed_file -ne "docs/boinc-v1-alpha-workunit-b.md" -or $obj.no_auto_merge -ne $true -or $obj.human_review_confirmed -ne $true) { throw "Workunit B finalizer evidence contract mismatch" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-finalizer-evidence-safe"; token_printed = $false } | ConvertTo-Json -Compress
