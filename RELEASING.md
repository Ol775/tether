# Releasing

**Main releases must be downloadable.** A source push alone does not complete a release. Publish the app ZIP,
SHA-256 checksum and version-bound signature on GitHub Releases, mark the release latest, and verify all three assets
are available before reporting it shipped. Keep the Ed25519 release key offline on the maintainer's Mac.

1. Edit `VERSION` and add a `## x.y.z (date)` entry to `CHANGELOG.md`.
2. `swift test`, then commit and push `main`.
3. `./release.sh --dry-run` (every check, builds and signs the zip, publishes nothing), then `./release.sh`.

`release.sh` refuses unless the tree is clean and pushed, the tests pass, the version isn't already released, and the signing
key matches `Updater.publicKey`. It uploads `Tether-x.y.z.zip`, `.sha256` and `.sig2` and marks the release as latest (the app
reads GitHub's "latest", which never includes pre-releases or drafts).

The test phase prints its full output and saves it in `build/release-tests.log`. It uses Swift's exit status to decide
whether tests passed. If SwiftPM says another instance is running, let that build or test finish before starting another
release attempt; avoid running several commands against `.build` at once.

GitHub's **Validate Tether** workflow runs the `TetherCore` test suite on a macOS 26 runner for every main push and,
when `VERSION` is bumped, drafts the GitHub release (notes from `CHANGELOG.md`) for `release.sh` to finish. It does not
build the GUI: the runner's newest Xcode (26.x) crashes doing IRGen on the Swift 6.4 GUI module, so the app is compiled,
codesigned and signed only on the Mac by `release.sh`, which is the release gate. `release.sh` always runs the full
local suite before publishing, so a green/absent workflow never substitutes for it.

**Signing key:** Ed25519 private key at `~/.config/tether/signing.key` (mode 600, never in the repo). Tool:
`scripts/sign-tool.swift` (`keygen | public | sign-update | verify`). Back the key up somewhere private: if it is lost, installed
copies can't verify updates and people must reinstall from a build that embeds a new public key. To rotate, ship one release
signed with the old key that embeds the new public key.
