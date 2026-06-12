. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$stateDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path ".agent/tmp/managed-mode-run-209"
$matches = @(Select-String -Path (Join-Path $stateDir "*") -Pattern 'raw_prompt|raw_stdout|raw_stderr|raw_codex_transcript|raw_worker_log|raw_ci_log|Authorization\s*[:=]\s*Bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN .*PRIVATE KEY-----|token_printed"\s*:\s*true' -CaseSensitive:$false -ErrorAction SilentlyContinue)
if ($matches.Count -ne 0) { throw "Raw or secret-looking finalizer artifact content found." }
Write-ManagedModeRunSmokeResult "managed-mode-run-209-finalizer-no-raw-artifacts"
