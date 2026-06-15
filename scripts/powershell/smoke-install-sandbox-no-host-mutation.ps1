$ErrorActionPreference = "Stop"
$install = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-install-sandbox.ps1" -Command safe-summary -Json | Out-String).Trim() | ConvertFrom-Json
$uninstall = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-uninstall-sandbox.ps1" -Command safe-summary -Json | Out-String).Trim() | ConvertFrom-Json
foreach ($json in @($install, $uninstall)) {
  if ($json.registry_mutation -ne $false -or $json.service_mutation -ne $false -or $json.scheduled_task_mutation -ne $false -or $json.path_mutation -ne $false -or $json.powercfg_mutation -ne $false) { throw "Host mutation flag was not false." }
  if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
}
[pscustomobject]@{ ok = $true; scenario = "install-sandbox-no-host-mutation"; token_printed = $false } | ConvertTo-Json -Compress
