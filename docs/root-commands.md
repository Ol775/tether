# Experimental Samsung root commands

In a connected Samsung TV's Overview, expand **Samsung system customisation** and choose **Experimental root commands…**.

This is an opt-in adapter for the **archive-root command interface in samsung-tv-root v0.0.12**. It provides one-shot commands through that project's temporary root session. It does not enable Samsung's regular `sdb shell`, provide an interactive PTY, keep root enabled, install boot persistence, or disable UEP. The normal Shell and SDB root capability indicators continue to describe what the TV's firmware reports.

Compatibility depends on the exact model and firmware. Tether does not label an untested TV compatible, and a successful TCP or SDB check is not root compatibility evidence. Consult the project's [compatibility table](https://github.com/chris-ritsen/samsung-tv-root/tree/v0.0.12#tv-compatibility) and [quick start](https://github.com/chris-ritsen/samsung-tv-root/blob/v0.0.12/QUICKSTART.md). The archive route has no interactive shell in this version. Its `probe` acquires root too; it is not a passive diagnostic.

## Prepare the local tool

Obtain the project yourself from its [v0.0.12 release](https://github.com/chris-ritsen/samsung-tv-root/releases/tag/v0.0.12), or prepare a source installation using the project's instructions. Select its executable in Tether. For a Python source installation, this can be the generated `.venv/bin/samsung-tv-root` entry point. Tether does not bundle, download, compile or silently update the root tool or exploit payloads.

The source path requires Python 3.12+, OpenSSL and the matching built payloads; upstream documents the .NET SDK requirements. A source checkout alone is insufficient. For an older TV runtime, use the project's .NET 3.1 payload build rather than assuming the .NET 6 payloads will work. Prefer automatic runtime detection unless upstream guidance for your exact TV calls for an override. Runtime selection does not establish compatibility.

**Check local setup** runs only `--version` and `doctor` on this Mac. It does not contact or exploit the TV. Tether accepts the reviewed CLI version 0.0.12; it rejects a different reported version before invoking the archive route. This version check is not an authenticity check: select a tool you trust. The optional payload-folder override must contain both `SamsungTvArchiveRoot.dll` and `SamsungTvRootAgent.dll`.

## Run a command

The TV must already be connected to Tether over IPv4 on port 26101. The callback address must match an active Mac Wi-Fi or Ethernet IPv4 address; the TV needs to connect back to that Mac address.

**Verify root identity…** requests the command `id`; **Run command as root…** requests the command in the editor. Both open a review sheet with the exact TV, command, executable and callback address. Neither executes until you choose **Attempt root and run**. Even the identity check executes the exploit.

Every run acquires a fresh session, executes one command and allows the external tool to clean up. Working directory and environment do not carry over. Tether passes the command as one argument to the tool; it never evaluates it in a host shell.

Root operations bypass the restore-point engine. There is no automatic backup or undo, and root commands can damage the TV or its data. Command effects can persist even though the root session is temporary. A cleanup report is not a rollback.

Tether pauses polling and blocks device changes, other connection work, updates and restarts during the attempt. Keep the app open until it finishes. The process has a three-minute bound; on a timeout or failed result, completion and cleanup are unverified, so do not assume changes were undone. Inspect the TV before retrying.

## Interpret the result

Tether reports a confirmed last session only when the tool returns an authenticated UID 0/EUID 0 result for the requested host and exact command, plus successful staging cleanup and unchanged checked system files. It preserves command exit codes, stderr and timeout results. The evidence is the external tool's report, not independent verification of that tool.

Command output stays in memory. Tether's change log records only attempt metadata and result status, not the command text or output. Selecting a different TV clears the displayed result. Root attempts never run in background diagnostics or automatic reconnects.
