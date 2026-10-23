# Architecture

SwiftPM package. `TetherCore` holds all logic and has no UI; `Tether` is a thin SwiftUI executable.

| Unit | Responsibility |
|---|---|
| `ADBRunner` | Runs the bundled `adb` on a private server port (5038) so it never collides with a system `adb`; timeouts; typed `ADBError`s |
| `Parsers`, `PackageName` | Pure output parsers; the only way a package name reaches a command |
| `DeviceManager`, `Discovery` | Connect, pair, list, profile; Bonjour discovery |
| `DeviceSnapshot` | Live state: packages, settings, density, launcher |
| `RestorePointStore` | One folder per snapshot (`restore.json` + pulled APKs), verified on write |
| `Catalog`, `CatalogStore` | Validated debloat list; bundled, optionally refreshed |
| `ChangeEngine`, `RevertPlanner`, `ChangeLog` | The only path to mutating commands |
| `TweakLibrary` | Curated, reversible settings |
| `GitHubRelease`, `Installer` | ABI-aware release asset choice, verified download, install |
| `ConsoleGuard`, `Console` | Allowlist guard for raw shell |

Samsung TVs (slice B) run a parallel pipeline in `TetherCore/Tizen`:

| Unit | Responsibility |
|---|---|
| `ProcessRunner` | Shared child-process runner (temp-file output, timeout, cancellation) used by `ADBRunner` and `SDBRunner` |
| `SDBRunner`, `SDBError` | Runs Samsung's `sdb`; typed errors with a next step |
| `TizenParsers`, `TizenAppID`, `TizenDevice` | `sdb` output parsers, validated app ids, model year from the model code |
| `TizenManager` | Connect (reads the text, not just the exit code), list TVs, refuse pre-2019 models |
| `TizenChangeEngine`, `TizenRestorePointStore` | Restore point first, uninstall/install, verify by re-reading, report locked apps; reverts reinstall apps Tether installed |
| `TizenCatalog` | Validated list with a per-model-year removability hint |
| `SamsungTools` | Downloads Samsung's installer on first use: https, same-host redirects only, pinned SHA-256 checked before it runs |
| `TizenCertificates` | Reads the certificate profile state; creation is guided through Samsung's Certificate Manager |

`Sources/Tether` holds `AppModel` (the observable bridge) and the views. Tests drive the real pipeline against
`Tests/TetherCoreTests/Fixtures/fake-adb`, a scripted stand-in for `adb`; the same stub backs `demo/run.sh`.

Design: Liquid Glass on chrome only (sidebar, toolbar, floating action bar, sheets), solid content rows, one accent
colour, risk tiers as colour + icon + label, motion under 250 ms and off under Reduce Motion.
