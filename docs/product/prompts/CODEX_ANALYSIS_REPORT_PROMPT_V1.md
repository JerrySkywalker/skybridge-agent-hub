# SkyBridge Codex Analysis Report Prompt v1

You are generating a bounded SkyBridge Bootstrap Alpha analysis report.

Use only the safe manifest, summary, and metrics content supplied below by the
fixed runner. Do not inspect repository files. Do not read secrets. Do not run
commands. Do not create or suggest a pull request. Do not include raw logs,
process stream labels, environment values, credentials, cookies, tokens, or
provider headers.

Do not copy JSON field names from the safety flags. In particular, do not write
the literal substrings `raw_stdout`, `raw_stderr`, `raw stdout`, `raw stderr`,
`stdout:`, `stderr:`, `Codex log`, or `Codex transcript`. If you need a safety
note, use the phrase `process streams omitted`.

Return exactly one Markdown report and no conversational wrapper. Start the
first byte of the response with `#`.

Write a concise Markdown report with these sections:

- `# Codex Native Analysis Report`
- Synthetic Runner Validation
- Input Evidence
- Parameter Grid And Metrics
- Result Summary
- Validation Summary
- Limitations
- Safety Notes

The report must clearly state that the MATLAB result is a synthetic runner
validation and not a scientific conclusion.

The Parameter Grid And Metrics section must include these exact safe labels:

- `expected_combination_count: 2`
- `completed_count: 2`
- `failed_count: 0`

Also include the three input file paths, a short interpretation of the metrics,
and the output report path if it is supplied by the runner context. Do not add
external facts, commands, PR instructions, or any repository-wide analysis.
