# Safety Kernel Contract

The shared safety kernel preserves these invariants:

- no raw prompts, transcripts, stdout, stderr, worker logs, CI logs, Authorization headers, tokens, cookies, private keys, or environment dumps are persisted;
- `token_printed=false` appears in JSON, smoke, report, and UI fixture outputs;
- resource gates do not mutate `powercfg`, registry, sleep settings, services, or require admin rights;
- apply paths remain disabled unless a future explicit goal authorizes a narrow path;
- wrappers keep legacy command names and fail closed if shared modules cannot load;
- PR packaging allows only `README.md` and `docs/**` unless a future goal explicitly extends the allowlist.

The scanner rejects token-looking text, raw artifact fields, secret-looking JSON, environment dumps, and unsafe command strings such as `start-all`, bounded queue apply, `resume -Apply`, and destructive cleanup patterns.

Future goals may add stricter checks but must not weaken these rules.
