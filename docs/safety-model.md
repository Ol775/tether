# Safety model

1. **No restore point, no change.** `ChangeEngine` snapshots first (package states, APKs of apps being removed,
   settings) and re-reads the file before proceeding. If that fails, nothing is touched.
2. **One path to mutate.** Debloat, tweaks and reverts all go through `ChangeEngine`. It applies in order, stops at the
   first failure, reports applied / failed / pending, then re-reads the device to confirm.
3. **Reversible by default.** Removal is `pm uninstall -k --user 0`; restore is `cmd package install-existing`, falling
   back to the pulled APKs. A revert takes its own restore point, so it can be undone too.
4. **Reverts only touch what was changed.** A restore point records its changes; a revert never "restores" settings the
   OS wrote since.
5. **Shell input is validated.** `adb` joins arguments into one remote command line, so package names, setting keys and
   values, components and permissions are checked against strict ASCII sets before anything runs.
6. **Console is an allowlist.** Only known read-only commands run unprompted; wrappers, unknown verbs, redirects and
   anything unparseable need confirmation. Everything is logged to `changes.jsonl`.
7. **Downloads are checked.** https only, size must match, and GitHub's SHA-256 digest is verified when present.
8. **Catalogue refresh cannot lower a risk tier.** Signature verification is still to do and must land before refresh
   is switched on anywhere.
