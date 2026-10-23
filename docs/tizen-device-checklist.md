# Tizen TV checklist (manual)

The automated suite uses a scripted `sdb`; these need a real Samsung TV. Note the model and year with each result.

## Verified hardware

2026-10-23, Samsung UE43AU9007KXXU (2021), Tizen 6.0: Developer Mode and the Host PC IP were confirmed;
connection and reading the list of 405 apps succeeded. The retail capability response omits `model_name`, so the
model must also be read from `sdb devices`. SDB sometimes reports a connection failure even while the device list
shows the TV as ready. Fixtures and regression tests cover both observations. Install, removal and restore have
not been tested on this TV.

## Connect
- [ ] Developer Mode on, Mac's IP entered, TV restarted; **Add device → Samsung TV** shows this Mac's IP.
- [ ] **Set up Samsung tools** downloads and verifies the installer, runs it, and `sdb` exists afterwards
      (`~/Library/Application Support/Tether/samsung/tizen-studio/tools/sdb`). Confirm the package-manager step
      (`cert-add-on`) is the right package name.
- [x] Connect on port 26101 (verified on the 2021 model above).
- [ ] Verify failed connections on other models remain failures unless a ready SDB device and readable profile confirm the session.
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
