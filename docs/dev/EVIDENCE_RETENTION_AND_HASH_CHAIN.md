# Evidence Retention And Hash Chain

Goal 219 indexes safe release evidence metadata. The retention command stores paths, hashes, evidence type, chain position, and safe metadata. It does not store raw file contents in reports and does not index raw prompts, transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, raw diffs, environment dumps, or secret-bearing paths.

## Contracts

- `skybridge.evidence_retention.v1`
- `skybridge.evidence_index_entry.v1`
- `skybridge.evidence_hash_chain.v1`
- `skybridge.evidence_export_summary.v1`
- `skybridge.evidence_retention_report.v1`
- `skybridge.evidence_retention_violation.v1`

## Covered Evidence

The scanner targets safe JSON and Markdown reports from:

- `managed-mode-pilot-208`
- `managed-mode-run-209`
- `managed-mode-run-210`
- `managed-mode-run-211`
- `boinc-v1-alpha-215` Workunit A and Workunit B
- Desktop resident worker Goal 217 report
- Server control plane Goal 218 report
- campaign/evidence summaries already marked safe

Files with raw-artifact names such as logs, stdout, stderr, prompts, transcripts, JSONL event logs, worker logs, CI logs, and GitHub logs are excluded and treated as non-exportable.

## Reports

The command writes ignored reports under `.agent/tmp/evidence-retention/`:

- `evidence-index.json`
- `evidence-hash-chain.json`
- `evidence-retention-report.json`
- `evidence-retention-report.md`

Each entry includes `sha256`, `previous_hash`, `chain_index`, `raw_artifact=false`, `secret_detected=false`, and `token_printed=false`.

## Validation

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-evidence-retention-index.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-evidence-retention-hash-chain.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-evidence-retention-safe-export.ps1
```

