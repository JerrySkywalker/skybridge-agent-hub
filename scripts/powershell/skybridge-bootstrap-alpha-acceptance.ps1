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
  chat_to_task_draft = "scripts/powershell/skybridge-chat-to-task-draft.ps1"
  task_template_registry = "scripts/powershell/skybridge-task-template-registry.ps1"
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
  "smoke:chat-to-task-draft",
  "smoke:desktop-chat-to-task",
  "smoke:chat-to-task-matlab-example",
  "smoke:task-template-registry",
  "smoke:task-template-registry-matlab",
  "smoke:desktop-task-template-registry"
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
  $desktopChatToTaskPanelPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Chat-to-Task") -and
    $desktopSource -match [regex]::Escape("skybridge.task_draft_preview.v1") -and
    $desktopSource -match [regex]::Escape("task_created=false") -and
    $desktopSource -match [regex]::Escape("execution_started=false; codex_run_called=false; matlab_run_called=false; token_printed=false") -and
    $desktopSource -match [regex]::Escape("Review and Submit (MG328 future work)")
  )
  $desktopTaskTemplateRegistryPanelPresent = (
    $desktopSource -match [regex]::Escape("Bootstrap Alpha Task Templates") -and
    $desktopSource -match [regex]::Escape("skybridge.task_template_registry.v1") -and
    $desktopSource -match [regex]::Escape("execution_supported=false") -and
    $desktopSource -match [regex]::Escape("task_creation_supported=false; campaign_creation_supported=false; claim_supported=false") -and
    $desktopSource -match [regex]::Escape("codex_run_supported=false; matlab_run_supported=false; arbitrary_shell_enabled=false; token_printed=false")
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
  $workerStatusContractOk -and
  $chatToTaskContractOk -and
  $taskTemplateRegistryContractOk
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
