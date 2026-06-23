[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$requiredDocs = @(
  "docs/product/BOOTSTRAP_ALPHA_PRODUCT_FLOW.md",
  "docs/product/CLIENT_WORKER_SERVER_ARCHITECTURE.md",
  "docs/product/NATURAL_LANGUAGE_TO_TASK_FLOW.md",
  "docs/product/TASK_TEMPLATE_MODEL.md",
  "docs/product/CHAT_TO_TASK_DRAFT_PLANNER.md",
  "docs/product/TASK_TEMPLATE_REGISTRY.md",
  "docs/product/DRAFT_REVIEW_AND_SUBMIT.md",
  "docs/product/WORKER_TEMPLATE_RUNNER_V1.md",
  "docs/release/BOOTSTRAP_ALPHA_SCOPE.md",
  "docs/release/BOOTSTRAP_ALPHA_ROADMAP.md",
  "docs/release/WINDOWS_WORKER_INSTALL_BOOTSTRAP_ALPHA.md"
)

$requiredScripts = @{
  operator_report = "scripts/powershell/smoke-operator-report.ps1"
  review_gate = "scripts/powershell/smoke-review-gate.ps1"
  cloud_parity = "scripts/powershell/skybridge-cloud-parity-check.ps1"
  worker_service_status = "scripts/powershell/skybridge-worker-service-status.ps1"
  worker_service_doctor = "scripts/powershell/skybridge-worker-service-doctor.ps1"
  worker_service_install_preview = "scripts/powershell/skybridge-worker-service-install-preview.ps1"
  worker_service_repair_preview = "scripts/powershell/skybridge-worker-service-repair-preview.ps1"
  worker_service_install = "scripts/powershell/skybridge-worker-service-install.ps1"
  worker_service_repair = "scripts/powershell/skybridge-worker-service-repair.ps1"
  worker_heartbeat_pairing_drill = "scripts/powershell/skybridge-worker-heartbeat-pairing-drill.ps1"
  worker_identity = "scripts/powershell/skybridge-worker-identity.ps1"
  worker_live_heartbeat = "scripts/powershell/skybridge-worker-live-heartbeat.ps1"
  chat_to_task_draft = "scripts/powershell/skybridge-chat-to-task-draft.ps1"
  task_template_registry = "scripts/powershell/skybridge-task-template-registry.ps1"
  draft_submit = "scripts/powershell/skybridge-draft-submit.ps1"
  worker_template_runner = "scripts/powershell/skybridge-worker-template-runner.ps1"
}

$componentPaths = @{
  desktop_app = "apps/desktop"
  server_app = "apps/server"
}

$workerPathCandidates = @(
  "scripts/powershell/skybridge-worker-service-status.ps1",
  "scripts/powershell/skybridge-worker-service-doctor.ps1",
  "scripts/powershell/skybridge-worker-service.ps1",
  "scripts/powershell/skybridge-worker-status.ps1",
  "scripts/powershell/smoke-worker-service-contract.ps1",
  "scripts/powershell/smoke-worker-status.ps1"
)

function Test-RelativePath {
  param([string]$RelativePath, [switch]$Leaf, [switch]$Container)
  $path = Join-Path $RepoRoot $RelativePath
  if ($Leaf) { return (Test-Path -LiteralPath $path -PathType Leaf) }
  if ($Container) { return (Test-Path -LiteralPath $path -PathType Container) }
  return (Test-Path -LiteralPath $path)
}

function Read-JsonPackage {
  $packagePath = Join-Path $RepoRoot "package.json"
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "package.json not found."
  }
  Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json
}

$docResults = foreach ($doc in $requiredDocs) {
  [pscustomobject]@{
    path = $doc
    exists = (Test-RelativePath -RelativePath $doc -Leaf)
  }
}

$scriptResults = foreach ($name in $requiredScripts.Keys) {
  [pscustomobject]@{
    name = $name
    path = $requiredScripts[$name]
    exists = (Test-RelativePath -RelativePath $requiredScripts[$name] -Leaf)
  }
}

$componentResults = foreach ($name in $componentPaths.Keys) {
  [pscustomobject]@{
    name = $name
    path = $componentPaths[$name]
    exists = (Test-RelativePath -RelativePath $componentPaths[$name] -Container)
  }
}

$workerResults = foreach ($candidate in $workerPathCandidates) {
  [pscustomobject]@{
    path = $candidate
    exists = (Test-RelativePath -RelativePath $candidate -Leaf)
  }
}

$package = Read-JsonPackage
$scripts = $package.scripts
$requiredPackageScripts = @(
  "check",
  "smoke:operator-report",
  "smoke:review-gate",
  "smoke:self-bootstrap-converge",
  "smoke:bootstrap-alpha-acceptance",
  "smoke:worker-service-status",
  "smoke:worker-service-doctor",
  "smoke:desktop-worker-service-manager",
  "smoke:worker-service-install-preview",
  "smoke:worker-service-install-apply-fixture",
  "smoke:worker-service-repair-preview",
  "smoke:worker-heartbeat-pairing-fixture",
  "smoke:desktop-worker-install-flow",
  "smoke:worker-identity-preview",
  "smoke:worker-identity-apply-fixture",
  "smoke:worker-live-heartbeat-preview",
  "smoke:worker-live-heartbeat-fixture",
  "smoke:desktop-worker-identity-heartbeat",
  "smoke:chat-to-task-draft",
  "smoke:desktop-chat-to-task",
  "smoke:chat-to-task-matlab-example",
  "smoke:task-template-registry",
  "smoke:task-template-registry-matlab",
  "smoke:desktop-task-template-registry",
  "smoke:draft-submit-preview",
  "smoke:draft-submit-server",
  "smoke:draft-submit-matlab-campaign",
  "smoke:desktop-draft-review-submit",
  "smoke:worker-template-runner-preview",
  "smoke:worker-template-runner-apply-one-fixture",
  "smoke:worker-template-runner-reject-unsafe",
  "smoke:desktop-worker-template-runner"
)
$packageScriptResults = foreach ($scriptName in $requiredPackageScripts) {
  [pscustomobject]@{
    name = $scriptName
    exists = [bool]($scripts.PSObject.Properties.Name -contains $scriptName)
  }
}

$docSecretFindings = @()
foreach ($doc in $requiredDocs) {
  $path = Join-Path $RepoRoot $doc
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    $text = Get-Content -Raw -LiteralPath $path
    try {
      Assert-NoUnsafeText $text
    } catch {
      $docSecretFindings += [pscustomobject]@{
        path = $doc
        issue = "unsafe_marker_detected"
      }
    }
  }
}

$missingDocs = @($docResults | Where-Object { -not $_.exists } | ForEach-Object { $_.path })
$missingScripts = @($scriptResults | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
$missingComponents = @($componentResults | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
$missingPackageScripts = @($packageScriptResults | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
$workerSupportPresent = [bool](@($workerResults | Where-Object { $_.exists }).Count -gt 0)

$desktopWorkerServiceManagerPresent = $false
$desktopChatToTaskPanelPresent = $false
$desktopTaskTemplateRegistryPanelPresent = $false
$desktopDraftReviewSubmitPanelPresent = $false
$desktopWorkerTemplateRunnerPanelPresent = $false
$desktopWorkerInstallFlowPresent = $false
$desktopWorkerIdentityHeartbeatPresent = $false
$desktopSourcePath = Join-Path $RepoRoot "apps/desktop/src/main.tsx"
if (Test-Path -LiteralPath $desktopSourcePath -PathType Leaf) {
  $desktopSource = Get-Content -Raw -LiteralPath $desktopSourcePath
  $desktopWorkerServiceManagerPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Worker Setup") -and
    $desktopSource -match [regex]::Escape("LocalWorkerServiceStatus") -and
    $desktopSource -match [regex]::Escape("claim_enabled=false") -and
    $desktopSource -match [regex]::Escape("execute_enabled=false") -and
    $desktopSource -match [regex]::Escape("worker_loop_started=false; token_printed=false")
  )
  $desktopWorkerInstallFlowPresent = (
    $desktopSource -match [regex]::Escape("MG331 identity and live heartbeat apply are PowerShell exact-confirmation only") -and
    $desktopSource -match [regex]::Escape("Install apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("Repair apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("Heartbeat pairing preview") -and
    $desktopSource -match [regex]::Escape("Heartbeat apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("Cloud worker registered") -and
    $desktopSource -match [regex]::Escape("template_runner_enabled=false; worker_loop_started=false; token_printed=false")
  )
  $desktopWorkerIdentityHeartbeatPresent = (
    $desktopSource -match [regex]::Escape("Worker identity status") -and
    $desktopSource -match [regex]::Escape("Identity setup preview") -and
    $desktopSource -match [regex]::Escape("Identity apply unavailable in Desktop") -and
    $desktopSource -match [regex]::Escape("Live heartbeat preview") -and
    $desktopSource -match [regex]::Escape("Live heartbeat last result") -and
    $desktopSource -match [regex]::Escape("Live heartbeat apply unavailable in Desktop")
  )
  $desktopChatToTaskPanelPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Chat-to-Task") -and
    $desktopSource -match [regex]::Escape("skybridge.task_draft_preview.v1") -and
    $desktopSource -match [regex]::Escape("task_created=false") -and
    $desktopSource -match [regex]::Escape("execution_started=false; codex_run_called=false; matlab_run_called=false; token_printed=false") -and
    $desktopSource -match [regex]::Escape("Draft Review + Submit")
  )
  $desktopTaskTemplateRegistryPanelPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Task Templates") -and
    $desktopSource -match [regex]::Escape("skybridge.task_template_registry.v1") -and
    $desktopSource -match [regex]::Escape("execution_supported=false") -and
    $desktopSource -match [regex]::Escape("task_creation_supported=false; campaign_creation_supported=false; claim_supported=false") -and
    $desktopSource -match [regex]::Escape("codex_run_supported=false; matlab_run_supported=false; arbitrary_shell_enabled=false; token_printed=false")
  )
  $desktopDraftReviewSubmitPanelPresent = (
    $desktopSource -match [regex]::Escape("Draft Review + Submit") -and
    $desktopSource -match [regex]::Escape("Submit preview") -and
    $desktopSource -match [regex]::Escape("Confirm submit") -and
    $desktopSource -match [regex]::Escape("DRAFT_SUBMIT_CONFIRMATION_TEXT") -and
    $desktopSource -match [regex]::Escape("submitPreview.schema") -and
    $desktopSource -match [regex]::Escape("submitResult.schema") -and
    $desktopSource -match [regex]::Escape("Run with Worker (MG329 future work)") -and
    $desktopSource -match [regex]::Escape("claim_created=false") -and
    $desktopSource -match [regex]::Escape("execution_started=false") -and
    $desktopSource -match [regex]::Escape("worker_loop_started=false") -and
    $desktopSource -match [regex]::Escape("token_printed=false")
  )
  $desktopWorkerTemplateRunnerPanelPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Worker Runner Preview") -and
    $desktopSource -match [regex]::Escape("BootstrapAlphaWorkerTemplateRunnerPanel") -and
    $desktopSource -match [regex]::Escape("skybridge.worker_template_runner_preview.v1") -and
    $desktopSource -match [regex]::Escape("Desktop preview-only") -and
    $desktopSource -match [regex]::Escape("MaxTasks=1; claim via PowerShell exact confirmation only") -and
    $desktopSource -match [regex]::Escape("codex_run_called=false; matlab_run_called=false; arbitrary_shell_enabled=false; worker_loop_started=false; token_printed=false")
  )
}

$workerStatusContract = $null
$workerStatusContractOk = $false
$workerStatusError = $null
$chatToTaskContract = $null
$chatToTaskContractOk = $false
$chatToTaskError = $null
$taskTemplateRegistryContract = $null
$taskTemplateRegistryContractOk = $false
$taskTemplateRegistryError = $null
$draftSubmitStatusContract = $null
$draftSubmitStatusContractOk = $false
$draftSubmitStatusError = $null
$workerTemplateRunnerStatusContract = $null
$workerTemplateRunnerStatusContractOk = $false
$workerTemplateRunnerStatusError = $null
$workerInstallPreviewContract = $null
$workerInstallPreviewContractOk = $false
$workerInstallPreviewError = $null
$workerHeartbeatPreviewContract = $null
$workerHeartbeatPreviewContractOk = $false
$workerHeartbeatPreviewError = $null
$workerIdentityPreviewContract = $null
$workerIdentityPreviewContractOk = $false
$workerIdentityPreviewError = $null
$workerLiveHeartbeatPreviewContract = $null
$workerLiveHeartbeatPreviewContractOk = $false
$workerLiveHeartbeatPreviewError = $null
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-bootstrap-alpha-acceptance-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null
try {
  $statusScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-service-status.ps1"
  if (Test-Path -LiteralPath $statusScriptPath -PathType Leaf) {
    $rawStatus = & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusScriptPath -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
    $rawText = ($rawStatus | Out-String).Trim()
    Assert-NoUnsafeText $rawText
    $workerStatusContract = $rawText | ConvertFrom-Json
    $workerStatusContractOk = (
      [string]$workerStatusContract.schema -eq "skybridge.local_worker_service_status.v1" -and
      [bool]$workerStatusContract.claim_enabled -eq $false -and
      [bool]$workerStatusContract.execute_enabled -eq $false -and
      [bool]$workerStatusContract.worker_loop_started -eq $false -and
      [bool]$workerStatusContract.token_printed -eq $false
    )
  }
  $installScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-service-install.ps1"
  if (Test-Path -LiteralPath $installScriptPath -PathType Leaf) {
    $rawInstallPreview = & pwsh -NoProfile -ExecutionPolicy Bypass -File $installScriptPath -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
    $installPreviewText = ($rawInstallPreview | Out-String).Trim()
    Assert-NoUnsafeText $installPreviewText
    $workerInstallPreviewContract = $installPreviewText | ConvertFrom-Json
    $workerInstallPreviewContractOk = (
      [string]$workerInstallPreviewContract.schema -eq "skybridge.local_worker_service_install.v1" -and
      [string]$workerInstallPreviewContract.mode -eq "preview" -and
      [bool]$workerInstallPreviewContract.would_mutate -eq $false -and
      [bool]$workerInstallPreviewContract.did_mutate -eq $false -and
      [bool]$workerInstallPreviewContract.confirmation_required -eq $true -and
      [bool]$workerInstallPreviewContract.claim_enabled -eq $false -and
      [bool]$workerInstallPreviewContract.execute_enabled -eq $false -and
      [bool]$workerInstallPreviewContract.template_runner_enabled -eq $false -and
      [bool]$workerInstallPreviewContract.worker_loop_started -eq $false -and
      [bool]$workerInstallPreviewContract.codex_run_called -eq $false -and
      [bool]$workerInstallPreviewContract.matlab_run_called -eq $false -and
      [bool]$workerInstallPreviewContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerInstallPreviewContract.token_printed -eq $false
    )
  }
  $heartbeatScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-heartbeat-pairing-drill.ps1"
  if (Test-Path -LiteralPath $heartbeatScriptPath -PathType Leaf) {
    $rawHeartbeatPreview = & pwsh -NoProfile -ExecutionPolicy Bypass -File $heartbeatScriptPath -Command heartbeat-preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
    $heartbeatPreviewText = ($rawHeartbeatPreview | Out-String).Trim()
    Assert-NoUnsafeText $heartbeatPreviewText
    $workerHeartbeatPreviewContract = $heartbeatPreviewText | ConvertFrom-Json
    $workerHeartbeatPreviewContractOk = (
      [string]$workerHeartbeatPreviewContract.schema -eq "skybridge.worker_heartbeat_pairing_drill.v1" -and
      [string]$workerHeartbeatPreviewContract.mode -eq "preview" -and
      [bool]$workerHeartbeatPreviewContract.would_mutate_server -eq $false -and
      [bool]$workerHeartbeatPreviewContract.server_mutation_performed -eq $false -and
      [bool]$workerHeartbeatPreviewContract.claim_enabled -eq $false -and
      [bool]$workerHeartbeatPreviewContract.execute_enabled -eq $false -and
      [bool]$workerHeartbeatPreviewContract.template_runner_enabled -eq $false -and
      [bool]$workerHeartbeatPreviewContract.claim_created -eq $false -and
      [bool]$workerHeartbeatPreviewContract.execution_started -eq $false -and
      [bool]$workerHeartbeatPreviewContract.worker_loop_started -eq $false -and
      [bool]$workerHeartbeatPreviewContract.codex_run_called -eq $false -and
      [bool]$workerHeartbeatPreviewContract.matlab_run_called -eq $false -and
      [bool]$workerHeartbeatPreviewContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerHeartbeatPreviewContract.token_printed -eq $false
    )
  }
  $identityScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-identity.ps1"
  if (Test-Path -LiteralPath $identityScriptPath -PathType Leaf) {
    $rawIdentityPreview = & pwsh -NoProfile -ExecutionPolicy Bypass -File $identityScriptPath -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId "jerry-win-local-01" -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Json
    $identityPreviewText = ($rawIdentityPreview | Out-String).Trim()
    Assert-NoUnsafeText $identityPreviewText
    $workerIdentityPreviewContract = $identityPreviewText | ConvertFrom-Json
    $workerIdentityPreviewContractOk = (
      [string]$workerIdentityPreviewContract.schema -eq "skybridge.worker_identity.v1" -and
      [string]$workerIdentityPreviewContract.mode -eq "preview" -and
      [string]$workerIdentityPreviewContract.worker_id -eq "jerry-win-local-01" -and
      [bool]$workerIdentityPreviewContract.would_mutate -eq $false -and
      [bool]$workerIdentityPreviewContract.did_mutate -eq $false -and
      [bool]$workerIdentityPreviewContract.claim_enabled -eq $false -and
      [bool]$workerIdentityPreviewContract.execute_enabled -eq $false -and
      [bool]$workerIdentityPreviewContract.worker_loop_started -eq $false -and
      [bool]$workerIdentityPreviewContract.codex_run_called -eq $false -and
      [bool]$workerIdentityPreviewContract.matlab_run_called -eq $false -and
      [bool]$workerIdentityPreviewContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerIdentityPreviewContract.token_printed -eq $false
    )
  }
  $liveHeartbeatScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-live-heartbeat.ps1"
  if (Test-Path -LiteralPath $liveHeartbeatScriptPath -PathType Leaf) {
    $rawLiveHeartbeatPreview = & pwsh -NoProfile -ExecutionPolicy Bypass -File $liveHeartbeatScriptPath -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId "jerry-win-local-01" -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Json
    $liveHeartbeatPreviewText = ($rawLiveHeartbeatPreview | Out-String).Trim()
    Assert-NoUnsafeText $liveHeartbeatPreviewText
    $workerLiveHeartbeatPreviewContract = $liveHeartbeatPreviewText | ConvertFrom-Json
    $workerLiveHeartbeatPreviewContractOk = (
      [string]$workerLiveHeartbeatPreviewContract.schema -eq "skybridge.worker_live_heartbeat.v1" -and
      [string]$workerLiveHeartbeatPreviewContract.mode -eq "preview" -and
      [bool]$workerLiveHeartbeatPreviewContract.would_mutate_server -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.server_mutation_performed -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.claim_enabled -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.execute_enabled -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.claim_created -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.execution_started -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.worker_loop_started -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.codex_run_called -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.matlab_run_called -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerLiveHeartbeatPreviewContract.token_printed -eq $false
    )
  }
  $chatScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-chat-to-task-draft.ps1"
  if (Test-Path -LiteralPath $chatScriptPath -PathType Leaf) {
    $rawChat = & pwsh -NoProfile -ExecutionPolicy Bypass -File $chatScriptPath -Command sample-matlab -ProjectId "skybridge-agent-hub" -Json
    $chatText = ($rawChat | Out-String).Trim()
    Assert-NoUnsafeText $chatText
    $chatToTaskContract = $chatText | ConvertFrom-Json
    $chatToTaskContractOk = (
      [string]$chatToTaskContract.schema -eq "skybridge.task_draft_preview.v1" -and
      [string]$chatToTaskContract.draft_type -eq "campaign" -and
      [string]$chatToTaskContract.template_id -eq "matlab-parameter-sweep.v1" -and
      [bool]$chatToTaskContract.task_created -eq $false -and
      [bool]$chatToTaskContract.campaign_created -eq $false -and
      [bool]$chatToTaskContract.claim_created -eq $false -and
      [bool]$chatToTaskContract.execution_started -eq $false -and
      [bool]$chatToTaskContract.codex_run_called -eq $false -and
      [bool]$chatToTaskContract.matlab_run_called -eq $false -and
      [bool]$chatToTaskContract.arbitrary_shell_enabled -eq $false -and
      [bool]$chatToTaskContract.token_printed -eq $false
    )
  }
  $taskTemplateRegistryScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-task-template-registry.ps1"
  if (Test-Path -LiteralPath $taskTemplateRegistryScriptPath -PathType Leaf) {
    $rawRegistry = & pwsh -NoProfile -ExecutionPolicy Bypass -File $taskTemplateRegistryScriptPath -Command list -Json
    $registryText = ($rawRegistry | Out-String).Trim()
    Assert-NoUnsafeText $registryText
    $taskTemplateRegistryContract = $registryText | ConvertFrom-Json
    $requiredTemplateIds = @(
      "software-docs-task.v1",
      "codex-analysis-report.v1",
      "safe-local-smoke.v1",
      "matlab-parameter-sweep.v1",
      "matlab-result-analysis.v1"
    )
    $registryTemplateIds = @($taskTemplateRegistryContract.templates | ForEach-Object { [string]$_.template_id })
    $requiredTemplatesPresent = $true
    foreach ($id in $requiredTemplateIds) {
      if ($registryTemplateIds -notcontains $id) { $requiredTemplatesPresent = $false }
    }
    $forbiddenTemplateFlagsEnabled = @($taskTemplateRegistryContract.templates | Where-Object {
      $_.execution_supported -ne $false -or
      $_.task_creation_supported -ne $false -or
      $_.campaign_creation_supported -ne $false -or
      $_.claim_supported -ne $false -or
      $_.codex_run_supported -ne $false -or
      $_.matlab_run_supported -ne $false -or
      $_.arbitrary_shell_enabled -ne $false -or
      $_.token_printed -ne $false
    }).Count -gt 0
    $taskTemplateRegistryContractOk = (
      [string]$taskTemplateRegistryContract.schema -eq "skybridge.task_template_registry.v1" -and
      $requiredTemplatesPresent -and
      -not $forbiddenTemplateFlagsEnabled -and
      [bool]$taskTemplateRegistryContract.execution_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.task_creation_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.campaign_creation_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.claim_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.codex_run_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.matlab_run_supported -eq $false -and
      [bool]$taskTemplateRegistryContract.arbitrary_shell_enabled -eq $false -and
      [bool]$taskTemplateRegistryContract.token_printed -eq $false
    )
  }
  $draftSubmitScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-draft-submit.ps1"
  if (Test-Path -LiteralPath $draftSubmitScriptPath -PathType Leaf) {
    $rawSubmit = & pwsh -NoProfile -ExecutionPolicy Bypass -File $draftSubmitScriptPath -Command status -Json
    $submitText = ($rawSubmit | Out-String).Trim()
    Assert-NoUnsafeText $submitText
    $draftSubmitStatusContract = $submitText | ConvertFrom-Json
    $draftSubmitStatusContractOk = (
      [string]$draftSubmitStatusContract.schema -eq "skybridge.draft_submit_status.v1" -and
      [bool]$draftSubmitStatusContract.confirmation_required -eq $true -and
      [bool]$draftSubmitStatusContract.preview_default -eq $true -and
      [bool]$draftSubmitStatusContract.task_created -eq $false -and
      [bool]$draftSubmitStatusContract.campaign_created -eq $false -and
      [bool]$draftSubmitStatusContract.claim_created -eq $false -and
      [bool]$draftSubmitStatusContract.execution_started -eq $false -and
      [bool]$draftSubmitStatusContract.codex_run_called -eq $false -and
      [bool]$draftSubmitStatusContract.matlab_run_called -eq $false -and
      [bool]$draftSubmitStatusContract.worker_loop_started -eq $false -and
      [bool]$draftSubmitStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$draftSubmitStatusContract.raw_prompt_persisted -eq $false -and
      [bool]$draftSubmitStatusContract.raw_response_persisted -eq $false -and
      [bool]$draftSubmitStatusContract.token_printed -eq $false
    )
  }
  $workerTemplateRunnerScriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-worker-template-runner.ps1"
  if (Test-Path -LiteralPath $workerTemplateRunnerScriptPath -PathType Leaf) {
    $rawRunner = & pwsh -NoProfile -ExecutionPolicy Bypass -File $workerTemplateRunnerScriptPath -Command status -Json
    $runnerText = ($rawRunner | Out-String).Trim()
    Assert-NoUnsafeText $runnerText
    $workerTemplateRunnerStatusContract = $runnerText | ConvertFrom-Json
    $workerTemplateRunnerStatusContractOk = (
      [string]$workerTemplateRunnerStatusContract.schema -eq "skybridge.worker_template_runner_status.v1" -and
      [bool]$workerTemplateRunnerStatusContract.confirmation_required -eq $true -and
      [bool]$workerTemplateRunnerStatusContract.preview_default -eq $true -and
      [int]$workerTemplateRunnerStatusContract.max_tasks -eq 1 -and
      @($workerTemplateRunnerStatusContract.supported_template_ids) -contains "safe-local-smoke.v1" -and
      @($workerTemplateRunnerStatusContract.supported_runner_ids) -contains "safe-local-smoke-runner.v1" -and
      [bool]$workerTemplateRunnerStatusContract.codex_run_called -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.matlab_run_called -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.arbitrary_shell_enabled -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.worker_loop_started -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.unbounded_run_enabled -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.project_control_unpaused -eq $false -and
      [bool]$workerTemplateRunnerStatusContract.token_printed -eq $false
    )
  }
} catch {
  if (-not $workerStatusContractOk) {
    $workerStatusError = "worker_service_status_contract_failed"
  }
  if (-not $chatToTaskContractOk) {
    $chatToTaskError = "chat_to_task_contract_failed"
  }
  if (-not $taskTemplateRegistryContractOk) {
    $taskTemplateRegistryError = "task_template_registry_contract_failed"
  }
  if (-not $draftSubmitStatusContractOk) {
    $draftSubmitStatusError = "draft_submit_status_contract_failed"
  }
  if (-not $workerTemplateRunnerStatusContractOk) {
    $workerTemplateRunnerStatusError = "worker_template_runner_status_contract_failed"
  }
  if (-not $workerInstallPreviewContractOk) {
    $workerInstallPreviewError = "worker_install_preview_contract_failed"
  }
  if (-not $workerHeartbeatPreviewContractOk) {
    $workerHeartbeatPreviewError = "worker_heartbeat_preview_contract_failed"
  }
  if (-not $workerIdentityPreviewContractOk) {
    $workerIdentityPreviewError = "worker_identity_preview_contract_failed"
  }
  if (-not $workerLiveHeartbeatPreviewContractOk) {
    $workerLiveHeartbeatPreviewError = "worker_live_heartbeat_preview_contract_failed"
  }
} finally {
  Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}

$ok = (
  $missingDocs.Count -eq 0 -and
  $missingScripts.Count -eq 0 -and
  $missingComponents.Count -eq 0 -and
  $missingPackageScripts.Count -eq 0 -and
  $workerSupportPresent -and
  $docSecretFindings.Count -eq 0 -and
  $desktopWorkerServiceManagerPresent -and
  $desktopChatToTaskPanelPresent -and
  $desktopTaskTemplateRegistryPanelPresent -and
  $desktopDraftReviewSubmitPanelPresent -and
  $desktopWorkerTemplateRunnerPanelPresent -and
  $desktopWorkerInstallFlowPresent -and
  $desktopWorkerIdentityHeartbeatPresent -and
  $workerStatusContractOk -and
  $workerInstallPreviewContractOk -and
  $workerHeartbeatPreviewContractOk -and
  $workerIdentityPreviewContractOk -and
  $workerLiveHeartbeatPreviewContractOk -and
  $chatToTaskContractOk -and
  $taskTemplateRegistryContractOk -and
  $draftSubmitStatusContractOk -and
  $workerTemplateRunnerStatusContractOk
)

$report = [pscustomobject]@{
  schema = "skybridge.bootstrap_alpha_acceptance.v1"
  ok = $ok
  expected_docs = $docResults
  package_scripts = $packageScriptResults
  required_scripts = $scriptResults
  components = $componentResults
  worker_support_present = $workerSupportPresent
  worker_support_candidates = $workerResults
  desktop_worker_service_manager_present = $desktopWorkerServiceManagerPresent
  desktop_chat_to_task_panel_present = $desktopChatToTaskPanelPresent
  desktop_task_template_registry_panel_present = $desktopTaskTemplateRegistryPanelPresent
  desktop_draft_review_submit_panel_present = $desktopDraftReviewSubmitPanelPresent
  desktop_worker_template_runner_panel_present = $desktopWorkerTemplateRunnerPanelPresent
  desktop_worker_install_flow_present = $desktopWorkerInstallFlowPresent
  desktop_worker_identity_heartbeat_present = $desktopWorkerIdentityHeartbeatPresent
  worker_service_status_contract_ok = $workerStatusContractOk
  worker_service_status_contract = if ($workerStatusContract) {
    [pscustomobject]@{
      schema = $workerStatusContract.schema
      readiness_status = $workerStatusContract.readiness_status
      claim_enabled = $workerStatusContract.claim_enabled
      execute_enabled = $workerStatusContract.execute_enabled
      worker_loop_started = $workerStatusContract.worker_loop_started
      token_printed = $workerStatusContract.token_printed
    }
  } else { $null }
  worker_service_status_error = $workerStatusError
  worker_install_preview_contract_ok = $workerInstallPreviewContractOk
  worker_install_preview_contract = if ($workerInstallPreviewContract) {
    [pscustomobject]@{
      schema = $workerInstallPreviewContract.schema
      mode = $workerInstallPreviewContract.mode
      would_mutate = $workerInstallPreviewContract.would_mutate
      did_mutate = $workerInstallPreviewContract.did_mutate
      confirmation_required = $workerInstallPreviewContract.confirmation_required
      claim_enabled = $workerInstallPreviewContract.claim_enabled
      execute_enabled = $workerInstallPreviewContract.execute_enabled
      template_runner_enabled = $workerInstallPreviewContract.template_runner_enabled
      worker_loop_started = $workerInstallPreviewContract.worker_loop_started
      codex_run_called = $workerInstallPreviewContract.codex_run_called
      matlab_run_called = $workerInstallPreviewContract.matlab_run_called
      arbitrary_shell_enabled = $workerInstallPreviewContract.arbitrary_shell_enabled
      token_printed = $workerInstallPreviewContract.token_printed
    }
  } else { $null }
  worker_install_preview_error = $workerInstallPreviewError
  worker_heartbeat_preview_contract_ok = $workerHeartbeatPreviewContractOk
  worker_heartbeat_preview_contract = if ($workerHeartbeatPreviewContract) {
    [pscustomobject]@{
      schema = $workerHeartbeatPreviewContract.schema
      mode = $workerHeartbeatPreviewContract.mode
      would_mutate_server = $workerHeartbeatPreviewContract.would_mutate_server
      server_mutation_performed = $workerHeartbeatPreviewContract.server_mutation_performed
      claim_enabled = $workerHeartbeatPreviewContract.claim_enabled
      execute_enabled = $workerHeartbeatPreviewContract.execute_enabled
      template_runner_enabled = $workerHeartbeatPreviewContract.template_runner_enabled
      claim_created = $workerHeartbeatPreviewContract.claim_created
      execution_started = $workerHeartbeatPreviewContract.execution_started
      worker_loop_started = $workerHeartbeatPreviewContract.worker_loop_started
      codex_run_called = $workerHeartbeatPreviewContract.codex_run_called
      matlab_run_called = $workerHeartbeatPreviewContract.matlab_run_called
      arbitrary_shell_enabled = $workerHeartbeatPreviewContract.arbitrary_shell_enabled
      token_printed = $workerHeartbeatPreviewContract.token_printed
    }
  } else { $null }
  worker_heartbeat_preview_error = $workerHeartbeatPreviewError
  worker_identity_preview_contract_ok = $workerIdentityPreviewContractOk
  worker_identity_preview_contract = if ($workerIdentityPreviewContract) {
    [pscustomobject]@{
      schema = $workerIdentityPreviewContract.schema
      mode = $workerIdentityPreviewContract.mode
      worker_id = $workerIdentityPreviewContract.worker_id
      would_mutate = $workerIdentityPreviewContract.would_mutate
      did_mutate = $workerIdentityPreviewContract.did_mutate
      claim_enabled = $workerIdentityPreviewContract.claim_enabled
      execute_enabled = $workerIdentityPreviewContract.execute_enabled
      worker_loop_started = $workerIdentityPreviewContract.worker_loop_started
      codex_run_called = $workerIdentityPreviewContract.codex_run_called
      matlab_run_called = $workerIdentityPreviewContract.matlab_run_called
      arbitrary_shell_enabled = $workerIdentityPreviewContract.arbitrary_shell_enabled
      token_printed = $workerIdentityPreviewContract.token_printed
    }
  } else { $null }
  worker_identity_preview_error = $workerIdentityPreviewError
  worker_live_heartbeat_preview_contract_ok = $workerLiveHeartbeatPreviewContractOk
  worker_live_heartbeat_preview_contract = if ($workerLiveHeartbeatPreviewContract) {
    [pscustomobject]@{
      schema = $workerLiveHeartbeatPreviewContract.schema
      mode = $workerLiveHeartbeatPreviewContract.mode
      worker_id = $workerLiveHeartbeatPreviewContract.worker_id
      would_mutate_server = $workerLiveHeartbeatPreviewContract.would_mutate_server
      server_mutation_performed = $workerLiveHeartbeatPreviewContract.server_mutation_performed
      claim_enabled = $workerLiveHeartbeatPreviewContract.claim_enabled
      execute_enabled = $workerLiveHeartbeatPreviewContract.execute_enabled
      claim_created = $workerLiveHeartbeatPreviewContract.claim_created
      execution_started = $workerLiveHeartbeatPreviewContract.execution_started
      worker_loop_started = $workerLiveHeartbeatPreviewContract.worker_loop_started
      codex_run_called = $workerLiveHeartbeatPreviewContract.codex_run_called
      matlab_run_called = $workerLiveHeartbeatPreviewContract.matlab_run_called
      arbitrary_shell_enabled = $workerLiveHeartbeatPreviewContract.arbitrary_shell_enabled
      token_printed = $workerLiveHeartbeatPreviewContract.token_printed
    }
  } else { $null }
  worker_live_heartbeat_preview_error = $workerLiveHeartbeatPreviewError
  chat_to_task_contract_ok = $chatToTaskContractOk
  chat_to_task_contract = if ($chatToTaskContract) {
    [pscustomobject]@{
      schema = $chatToTaskContract.schema
      status = $chatToTaskContract.status
      draft_type = $chatToTaskContract.draft_type
      template_id = $chatToTaskContract.template_id
      task_created = $chatToTaskContract.task_created
      campaign_created = $chatToTaskContract.campaign_created
      claim_created = $chatToTaskContract.claim_created
      execution_started = $chatToTaskContract.execution_started
      codex_run_called = $chatToTaskContract.codex_run_called
      matlab_run_called = $chatToTaskContract.matlab_run_called
      arbitrary_shell_enabled = $chatToTaskContract.arbitrary_shell_enabled
      token_printed = $chatToTaskContract.token_printed
    }
  } else { $null }
  chat_to_task_error = $chatToTaskError
  task_template_registry_contract_ok = $taskTemplateRegistryContractOk
  task_template_registry_contract = if ($taskTemplateRegistryContract) {
    [pscustomobject]@{
      schema = $taskTemplateRegistryContract.schema
      template_count = @($taskTemplateRegistryContract.templates).Count
      template_ids = @($taskTemplateRegistryContract.templates | ForEach-Object { [string]$_.template_id })
      execution_supported = $taskTemplateRegistryContract.execution_supported
      task_creation_supported = $taskTemplateRegistryContract.task_creation_supported
      campaign_creation_supported = $taskTemplateRegistryContract.campaign_creation_supported
      claim_supported = $taskTemplateRegistryContract.claim_supported
      codex_run_supported = $taskTemplateRegistryContract.codex_run_supported
      matlab_run_supported = $taskTemplateRegistryContract.matlab_run_supported
      arbitrary_shell_enabled = $taskTemplateRegistryContract.arbitrary_shell_enabled
      token_printed = $taskTemplateRegistryContract.token_printed
    }
  } else { $null }
  task_template_registry_error = $taskTemplateRegistryError
  draft_submit_status_contract_ok = $draftSubmitStatusContractOk
  draft_submit_status_contract = if ($draftSubmitStatusContract) {
    [pscustomobject]@{
      schema = $draftSubmitStatusContract.schema
      confirmation_required = $draftSubmitStatusContract.confirmation_required
      preview_default = $draftSubmitStatusContract.preview_default
      task_created = $draftSubmitStatusContract.task_created
      campaign_created = $draftSubmitStatusContract.campaign_created
      claim_created = $draftSubmitStatusContract.claim_created
      execution_started = $draftSubmitStatusContract.execution_started
      codex_run_called = $draftSubmitStatusContract.codex_run_called
      matlab_run_called = $draftSubmitStatusContract.matlab_run_called
      worker_loop_started = $draftSubmitStatusContract.worker_loop_started
      arbitrary_shell_enabled = $draftSubmitStatusContract.arbitrary_shell_enabled
      raw_prompt_persisted = $draftSubmitStatusContract.raw_prompt_persisted
      raw_response_persisted = $draftSubmitStatusContract.raw_response_persisted
      token_printed = $draftSubmitStatusContract.token_printed
    }
  } else { $null }
  draft_submit_status_error = $draftSubmitStatusError
  worker_template_runner_status_contract_ok = $workerTemplateRunnerStatusContractOk
  worker_template_runner_status_contract = if ($workerTemplateRunnerStatusContract) {
    [pscustomobject]@{
      schema = $workerTemplateRunnerStatusContract.schema
      confirmation_required = $workerTemplateRunnerStatusContract.confirmation_required
      preview_default = $workerTemplateRunnerStatusContract.preview_default
      max_tasks = $workerTemplateRunnerStatusContract.max_tasks
      supported_template_ids = $workerTemplateRunnerStatusContract.supported_template_ids
      supported_runner_ids = $workerTemplateRunnerStatusContract.supported_runner_ids
      codex_run_called = $workerTemplateRunnerStatusContract.codex_run_called
      matlab_run_called = $workerTemplateRunnerStatusContract.matlab_run_called
      arbitrary_shell_enabled = $workerTemplateRunnerStatusContract.arbitrary_shell_enabled
      worker_loop_started = $workerTemplateRunnerStatusContract.worker_loop_started
      unbounded_run_enabled = $workerTemplateRunnerStatusContract.unbounded_run_enabled
      project_control_unpaused = $workerTemplateRunnerStatusContract.project_control_unpaused
      token_printed = $workerTemplateRunnerStatusContract.token_printed
    }
  } else { $null }
  worker_template_runner_status_error = $workerTemplateRunnerStatusError
  doc_secret_marker_findings = $docSecretFindings
  missing_docs = $missingDocs
  missing_scripts = $missingScripts
  missing_components = $missingComponents
  missing_package_scripts = $missingPackageScripts
  raw_secret_markers_in_new_docs = ($docSecretFindings.Count -gt 0)
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 8
} elseif ($ok) {
  Complete-Smoke "bootstrap-alpha-acceptance"
} else {
  $report | Format-List
}

if (-not $ok) {
  exit 1
}
