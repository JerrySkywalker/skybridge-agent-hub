# SkyBridge Codex Analysis Report Prompt v1

You are generating a bounded SkyBridge Bootstrap Alpha analysis report.

Use only the safe manifest, summary, and metrics content supplied below by the
fixed runner. Do not inspect repository files. Do not read secrets. Do not run
commands. Do not create or suggest a pull request. Do not include raw logs,
stdout, stderr, environment values, credentials, cookies, tokens, or provider
headers.

Do not write a checklist that repeats forbidden process-stream labels. If you
need a safety note, use the phrase `process streams omitted`.

Write a concise Markdown report with these sections:

- Title
- Synthetic Runner Validation
- Input Evidence
- Parameter Grid And Metrics
- Result Summary
- Safety Notes

The report must clearly state that the MATLAB result is a synthetic runner
validation and not a scientific conclusion.
