# Security

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting (the **Report a vulnerability** button on the Security tab) instead of a
public issue. Only the latest release is supported.

## How updates are trusted

Tether checks GitHub's "latest release" for this repository and installs an update only if **all** of these hold:

- the asset URLs are `https://github.com/Ol775/tether/releases/download/…` with no dot-segments, and redirects stay on
  `github.com` or `*.githubusercontent.com` over https;
- the version is a plain `x.y.z`, and newer than the running one;
- the download is at most 100 MB;
- an **Ed25519 signature** over `tether-update\nv<version>\n` plus the zip bytes verifies against the public key built into
  the app (`Updater.publicKey`). The private key stays offline on the maintainer's Mac, so a hijacked GitHub account or
  release cannot push an update that installs;
- the SHA-256 matches, and is re-checked just before unpacking;
- the unpacked app has bundle id `io.github.ol775.tether`, the same version as the release, and passes `codesign --verify`.

Releases without a signature are never installed automatically. A copy that can't replace itself (run from Downloads or a
disk image) is sent to the release page instead. The old app is kept as a backup in `~/Library/Caches/Tether/previous`.

The app is ad-hoc signed, not notarised, so macOS asks you to approve it on first launch.

## What else Tether verifies, and what it doesn't

- `adb` (bundled in release builds) is fetched from Google at build time and checked against a pinned SHA-256.
- Samsung's installer for the Tizen tools is downloaded on first use, from one host, with a pinned SHA-256 checked before it runs.
  What that installer and Samsung's package manager download afterwards is Samsung's and is **not** verified by Tether.
- GitHub release APKs installed to a device are size-checked and checked against GitHub's digest when present. Tether can't
  tell you whether an app is trustworthy.
- The debloat catalogues are unverified starter lists; see the device checklists.
- Restore points (package lists, settings dumps, saved packages) are stored unencrypted in
  `~/Library/Application Support/Tether`.
- Tether has no telemetry. Network use is: your devices on the local network, GitHub (update check, release downloads) and,
  on request, Google and Samsung downloads as above.

See also [docs/safety-model.md](docs/safety-model.md).
