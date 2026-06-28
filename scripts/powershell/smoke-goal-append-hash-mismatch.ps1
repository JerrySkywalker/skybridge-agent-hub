. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-hash-mismatch-$([guid]::NewGuid().ToString('N'))"
$badHash = "0000000000000000000000000000000000000000000000000000000000000000"
$result = Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "review-preview",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-ExpectedHash", $badHash
)
Assert-False $result.hash_matches "hash_matches"
if (-not (@($result.blockers) -contains "candidate_hash_mismatch")) { throw "Missing candidate_hash_mismatch blocker." }
Assert-False $result.import_performed "import_performed"
Assert-False $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-TokenPrintedFalse $result

Complete-Smoke "goal-append-hash-mismatch"
