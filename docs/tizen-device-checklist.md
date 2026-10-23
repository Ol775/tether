# Tizen TV checklist (manual)

The automated suite uses a scripted `sdb`; these need a real Samsung TV. Note the model and year with each result.

## Connect
- [ ] Developer Mode on, Mac's IP entered, TV restarted; **Add device → Samsung TV** shows this Mac's IP.
- [ ] **Set up Samsung tools** downloads and verifies the installer, runs it, and `sdb` exists afterwards
      (`~/Library/Application Support/Tether/samsung/tizen-studio/tools/sdb`). Confirm the package-manager step
      (`cert-add-on`) is the right package name.
- [ ] Connect on port 26101. A 2023+ model that refuses is reported as refused, not as connected.
- [ ] A pre-2019 TV is refused with a clear message.
- [ ] The `capability` output matches `Tests/TetherCoreTests/Fixtures/sdb-capability-*.txt`; if not, fix the parser and fixtures.

## Apps and removal
- [ ] **The app list command is right**: Debloat lists the TV's real apps. The format of `sdb shell 0 applist` is
      assumed; check the parser against real output.
- [ ] Remove one app you installed yourself: it disappears, a restore point exists, Revert reinstalls it.
- [ ] Try to remove a preinstalled app: if the TV refuses, it shows as **Locked by Samsung** and stays locked after relaunch.
- [ ] Note which command removed anything (`vd_appuninstall` or the `tizen` CLI fallback) and on which year/firmware.
- [ ] Unplug the network mid-removal of several apps: the report shows applied vs pending.
- [ ] Find out whether a reversible *deactivate* exists on your model (spike 2); record the command and result here.

## Install
- [ ] Certificate state on Overview matches reality (ready / missing / not for this TV).
- [ ] **Spike 1:** can a Samsung certificate be created and imported without the Tizen Studio GUI, and is a Samsung
      account required? Record the answer; if it can be scripted, say how.
- [ ] Install a signed `.wgt` (for example Jellyfin) by file; the app appears and starts.
- [ ] Remove it again, then Revert: the saved package is reinstalled.

## Catalogue
- [ ] Each entry in `tizen-catalog.json` is an app id that exists on your model; set `removableFromYear` where you
      confirmed removal works and update `source`.
