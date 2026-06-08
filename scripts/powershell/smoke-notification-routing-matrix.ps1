$ErrorActionPreference = "Stop"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-attention-fixture.ps1" -Command routing-matrix -Json | ConvertFrom-Json
$routes = @($result.routing_matrix)
foreach ($required in @("desktop_only", "web_banner", "local_fixture_notification", "ntfy_placeholder", "disabled")) {
  if (-not (@($routes | Where-Object { $_.route -eq $required }).Count)) {
    throw "Missing notification route: $required"
  }
}
if (@($routes | Where-Object { $_.real_external_send -ne $false }).Count) {
  throw "A notification route allows real external send by default."
}
if (($routes | Where-Object { $_.route -eq "ntfy_placeholder" }).status -ne "not_configured") {
  throw "ntfy placeholder must be not_configured by default."
}

[pscustomobject]@{
  ok = $true
  scenario = "notification-routing-matrix"
  external_notification_sent = $false
  token_printed = $false
} | ConvertTo-Json -Compress
