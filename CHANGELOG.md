# Changelog

## 0.3.2 (2026-10-26)

- Added an opt-in experimental Samsung root-command console for a separately prepared `samsung-tv-root` v0.0.12 tool. Every attempt, including identity verification, requires review of the exact TV and command. This is a one-shot archive-root integration, not an interactive shell or a change to Samsung's SDB shell capability.
- Root results require the tool's authenticated UID 0/EUID 0 evidence, matching target and command, and successful cleanup checks. Root commands have no automatic restore point or undo. No root attempt runs as part of diagnostics, reconnects or startup.

## 0.3.1 (2026-10-26)

- Added Connection diagnostics from Help, the toolbar and Add a device. Checks distinguish TCP reachability, Samsung's network status, Developer Mode and Host PC IP, and a readable ADB/SDB session. Reports can be copied for troubleshooting without exporting full TV metadata or certificates.
- Added separate SDB and ADB service restarts with reconnection of Tether's network devices. SDB restart affects Samsung's shared server; ADB restart stays on Tether's private port 5038. Polling pauses during recovery and stale results are discarded.
- Added Restart Tether to the application menu and diagnostics panel. The packaged app reopens itself and attempts to reconnect previously connected network devices. Restarts are blocked during device operations and app updates.

## 0.3.0 (2026-10-24)

- Samsung app installs no longer use Samsung's Tizen command-line tools for signing or certificate authorisation. Tether signs the widget itself (a native W3C widget signature, identical to what Tizen Studio produces) and authorises the certificate on the TV directly, so the Jellyfin build and install run without the Tizen CLI or Device Manager. The Jellyfin installer now asks for your Samsung certificate password, used only to sign and never stored.

## 0.2.0 (2026-10-23)

- Samsung app installs now run entirely over `sdb` — push the signed package, then `vd_appinstall` by the app id read from the package itself — instead of Tizen Studio's `install` command, which fails to stage packages on this toolchain and left retail TVs reporting only "Failed to install". No Device Manager or Tizen CLI install step is involved. Fixes installing Jellyfin and other signed apps on real Samsung TVs.
- Added official Jellyfin installers on the Apps page. Fire TV / Android TV: verified stable release APK installed over the existing app (data kept). Samsung: builds official Jellyfin Web and jellyfin-tizen on this Mac, signs with your Samsung profile, checks the package declares `AprZAARz4r.Jellyfin`, then installs it. Update and reinstall never uninstall the app.
- Samsung installs now fail on error text even when `sdb` exits 0; the profile used for signing must exist and be the SDK's active profile.
- Fixed the `tizen uninstall` fallback to pass the TV with `-s`. Cancelling or timing out a build now stops the whole process tree.

- Added Samsung certificate setup, selecting existing profiles and refreshing status; fixed the CLI launcher when the SDK path contains spaces.

- Redesigned the Mac app icon with a silver and blue interlocking connection mark.

- Fixed Samsung connections when a retail TV reports its model only in the device list, and when SDB reports failure despite a ready device.
- Corrected UHD model-year parsing for full regional model codes and clarified SDB connection errors.

## 0.1.1 (2026-10-23)

- Reworked Add Device with scrollable setup instructions, labelled fields and persistent connection actions.
- Added cancellable TCP port checks with open, refused, timeout and unreachable results.
- Added manual wireless pairing, pasted IP:port support, discovery refresh and copying the Samsung Host PC IP.

## 0.1.0 (2026-10-23)

- First public beta. Android and Fire OS over network `adb`: restore points, curated debloat, reversible tweaks, installs from a file or a GitHub release, guarded console.
- Samsung Tizen TVs (2019+) over `sdb`: list apps, remove what the TV allows (locked apps are shown as locked), install signed `.wgt` packages, restore points and revert. Untested on a real TV so far.
- The app checks GitHub for new releases and can update itself. Updates install only if they carry a valid signature from the offline release key (see SECURITY.md).
