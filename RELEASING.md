# Releasing

1. Edit `VERSION` and add a `## x.y.z (date)` entry to `CHANGELOG.md`.
2. `swift test`, then commit and push `main`.
3. `./release.sh --dry-run` (every check, builds and signs the zip, publishes nothing), then `./release.sh`.

`release.sh` refuses unless the tree is clean and pushed, the tests pass, the version isn't already released, and the signing
key matches `Updater.publicKey`. It uploads `Tether-x.y.z.zip`, `.sha256` and `.sig2` and marks the release as latest (the app
reads GitHub's "latest", which never includes pre-releases or drafts).

**Signing key:** Ed25519 private key at `~/.config/tether/signing.key` (mode 600, never in the repo). Tool:
`scripts/sign-tool.swift` (`keygen | public | sign-update | verify`). Back the key up somewhere private: if it is lost, installed
copies can't verify updates and people must reinstall from a build that embeds a new public key. To rotate, ship one release
signed with the old key that embeds the new public key.
