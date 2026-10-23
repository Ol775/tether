# Device checklist (manual)

The automated suite uses a fake `adb`; these need real hardware. Record results here.

## Any device
- [ ] Bonjour discovery lists the device (Android 11+ wireless debugging; the first run asks for Local Network access).
- [ ] Manual IP connect works; unauthorised devices show the "Allow debugging" advice.
- [ ] Create restore point; reveal in Finder shows `restore.json`.
- [ ] Debloat: remove one Safe app, confirm it is gone, Revert, confirm it is back.
- [ ] Unplug the network mid-removal of several apps: the report shows applied vs pending, nothing is half-recorded.
- [ ] Install an `.apk` by file and by GitHub repository (try one repo with several ABI assets).
- [ ] Console: `getprop ro.product.model` runs; `rm x` asks first.

## Fire TV / Fire OS
- [ ] ADB over network enabled per `docs/setup/fire-tv.md`; device profile reads as Fire OS.
- [ ] **Verify every catalogue entry's package name exists on your model** before trusting the "Safe" tier
      (the starter set is unverified); update `source` in `catalog.json` as you confirm each one.
- [ ] Tweaks: animations, private DNS, density (reset works); **Limit ad tracking is experimental**: confirm the key
      has any effect under Settings → Preferences → Privacy Settings.
- [ ] Default launcher swap (Apps → Actions) works with a replacement launcher installed; `cmd package set-home-activity`
      may not be honoured on some Fire OS versions.
- [ ] Never remove `com.amazon.dcp` / `com.amazon.tv.launcher` without a restore point and a way to reach the device.

## Android phone / tablet
- [ ] Wireless pairing code flow, then connect on the main Wireless debugging port.
- [ ] Samsung / Xiaomi catalogue entries exist and removal is reversible.
- [ ] Screen timeout and screensaver tweaks apply and revert.
