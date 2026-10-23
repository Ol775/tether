# Changelog

## Unreleased

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
