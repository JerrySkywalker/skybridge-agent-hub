# Safe Metadata Export Policy

Safe metadata exports may include bounded JSON and Markdown summaries that have already passed local redaction expectations.

Do not export:

- raw prompts or transcripts
- raw stdout or stderr
- worker logs
- CI or GitHub logs
- environment dumps
- token files
- Authorization headers
- cookies
- private keys
- raw pairing codes
- build output unless it is explicit safe metadata

All preview reports must keep `token_printed=false`.
