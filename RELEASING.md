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

GitHub's **Validate Tether** workflow also runs the full suite on a macOS 26 runner for every main push and retains
a release-candidate app ZIP plus the complete test log. If local host restrictions prevent the full suite, require the
workflow for the exact release commit to pass instead; never mark skipped checks as passed. Its candidate ZIP is
not an updater-ready release until it has been signed offline and published with the checksum and `.sig2` files.

**Signing key:** Ed25519 private key at `~/.config/tether/signing.key` (mode 600, never in the repo). Tool:
`scripts/sign-tool.swift` (`keygen | public | sign-update | verify`). Back the key up somewhere private: if it is lost, installed
copies can't verify updates and people must reinstall from a build that embeds a new public key. To rotate, ship one release
signed with the old key that embeds the new public key.
