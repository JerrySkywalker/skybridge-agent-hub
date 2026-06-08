$ErrorActionPreference = "Stop"
$outputs = @()
$outputs += (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-list -Json)
$outputs += (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-profile-preview -Json)
$text = $outputs -join "`n"
if ($text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log') {
  throw "Secret-looking text detected in project profile output."
}
if ($text -notmatch '"token_printed":false') { throw "Expected token_printed=false in output." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-no-secrets"; token_printed = $false } | ConvertTo-Json -Compress
