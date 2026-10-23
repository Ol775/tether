# Installing Jellyfin

## Fire TV / Android TV
Apps page → Jellyfin. Tether downloads the latest **stable release** APK from `jellyfin/jellyfin-androidtv`, checks its size and SHA-256, saves a restore point and runs `adb install -r`. Update and reinstall keep app data; nothing is uninstalled. A different signing key is reported as an error rather than worked around.

## Samsung (Tizen)
There is no prebuilt Jellyfin WGT, so Tether builds one with the steps in the [jellyfin-tizen README](https://github.com/jellyfin/jellyfin-tizen#build-process).

You need: Git, Node.js 20+, npm, the Samsung tools set up in Tether, and a Samsung signing profile that includes your TV (Certificate setup… in Tether).

1. Enter the Jellyfin Web version matching your server (the latest may not match).
2. Enter your profile name. It must exist and be the **active** profile in Certificate Manager; Tether checks this because signing uses the named profile while `install-permit` uses the active one.
3. Build and install. This takes several minutes. Tether checks the package declares `AprZAARz4r.Jellyfin` before installing.

Reinstall re-applies the last saved build. Firmware may reject a same-version install; Tether reports that and never uninstalls Jellyfin for you.

## Root, debloat and boot logo
Standard SDB cannot grant root and preinstalled apps are protected. Third-party root projects ([samsung-tv-root](https://github.com/chris-ritsen/samsung-tv-root), [untethered fork](https://github.com/levkropp/samsung-tv-root-untethered)) are model- and firmware-specific; compatibility with UE43AU9007KXXU / T-NKLADEUC-2310.0 is **unconfirmed**. Their "preflight" is not passive. Tether does not run exploits.
