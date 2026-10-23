# Third-party software

**Android Debug Bridge (`adb`)** from Google's Android SDK Platform-Tools is included in release builds of Tether
(`Tether.app/Contents/Resources/adb`). It is not stored in this repository: `scripts/fetch-platform-tools.sh`
downloads the pinned version from `dl.google.com` and checks its SHA-256. The `adb` source is part of the Android Open
Source Project and is licensed under the Apache License 2.0; the prebuilt Platform-Tools package is distributed by
Google under the [Android SDK License Agreement](https://developer.android.com/studio/terms). If you redistribute
Tether builds yourself, check that those terms suit your use.

**Samsung Tizen tools (`sdb`, `tizen` CLI)** are *not* included. Tether downloads Samsung's official installer on first
use, after you accept Samsung's Tizen Studio licence, and installs it in Tether's own folder.

No other third-party code is bundled.
