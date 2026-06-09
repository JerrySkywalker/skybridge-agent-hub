$ErrorActionPreference = "Stop"
$client = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
if ($client -notmatch "can_claim_tasks:\s*false") { throw "Local supervisor must keep can_claim_tasks=false." }
if ($desktop -match "claimTask|claim-task|task\.claimed|/v1/tasks/.*/claim") { throw "Desktop exposes a task claim path." }
[pscustomobject]@{ ok = $true; scenario = "desktop-worker-supervisor-no-task-claim"; task_claimed = $false; token_printed = $false } | ConvertTo-Json -Compress
