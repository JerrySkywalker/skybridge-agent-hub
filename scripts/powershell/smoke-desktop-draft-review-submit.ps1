[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$submitScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-draft-submit.ps1")

foreach ($needle in @(
  "Draft Review + Submit",
  "Submit preview",
  "Confirm submit",
  "DRAFT_SUBMIT_CONFIRMATION_TEXT",
  "Run with Worker (MG329 future work)",
  "claim_created=false",
  "execution_started=false",
  "codex_run_called=false",
  "matlab_run_called=false",
  "worker_loop_started=false",
  "arbitrary_shell_enabled=false",
  "token_printed=false",
  "submitPreview.schema",
  "submitResult.schema"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) { throw "Desktop draft review/submit panel missing text: $needle" }
}

foreach ($needle in @(
  "DraftSubmitPreview",
  "DraftSubmitResult",
  "fixtureDraftSubmitPreview",
  "fixtureDocsDraftSubmitResult",
  "fixtureMatlabDraftSubmitResult",
  "task_created: true",
  "campaign_created: true",
  "claim_created: false",
  "execution_started: false",
  "codex_run_called: false",
  "matlab_run_called: false",
  "worker_loop_started: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) { throw "Client draft submit fixture missing text: $needle" }
}

foreach ($needle in @(
  "/v1/drafts/submit-preview",
  "/v1/drafts/submit",
  "missing_exact_confirmation",
  "task_created = `$false",
  "campaign_created = `$false",
  "execution_started = `$false",
  "token_printed = `$false"
)) {
  if ($submitScript -notmatch [regex]::Escape($needle)) { throw "Draft submit script missing safety text: $needle" }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-draft-review-submit"
  panel_contract = "skybridge.draft_submit_preview.v1"
  result_contract = "skybridge.draft_submit_result.v1"
  automatic_submit = $false
  claim_created = $false
  execution_started = $false
  codex_run_called = $false
  matlab_run_called = $false
  worker_loop_started = $false
  arbitrary_shell_enabled = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
