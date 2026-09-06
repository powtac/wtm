# Long-running commands

- Run local builds, tests, and screenshot capture through `./scripts/run-logged LOG_FILE COMMAND [ARG ...]`. It waits locally and returns a compact completion summary; full output stays in the log.
- Use a stable log path per operation, such as `build/screenshots-run.log` for capture or `build/test-run.log` for tests. The wrapper rejects concurrent runs sharing that path.
- Keep the original tool session until completion. Do not add `sleep`/`ps`/`tail` polling loops or restart after an empty response. A progress message does not require a new status query.
- After completion, inspect only the relevant failure excerpt. Retry only after a concrete fix or new diagnostic evidence. For suspected hangs, follow the global build polling limit before investigating.
