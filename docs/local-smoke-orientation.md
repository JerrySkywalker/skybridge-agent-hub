# Local Smoke-Test Orientation

Use this as a quick pre-flight checklist before a local SkyBridge Agent Hub smoke test.

1. Stay in the repository root and avoid worker-loop commands unless a goal explicitly asks for them.
2. Install dependencies with `pnpm install` if the workspace is not already prepared.
3. Prefer the smallest relevant validation command first, such as `pnpm lint`, `pnpm typecheck`, or `pnpm test`.
4. Run `pnpm check` only when the smaller checks are clean and the goal is ready for final verification.
5. Keep local smoke-test notes free of secrets, `.env` values, full command output that may contain tokens, and production configuration details.
