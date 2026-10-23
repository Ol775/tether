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

`Sources/Tether` holds `AppModel` (the observable bridge) and the views. Tests drive the real pipeline against
`Tests/TetherCoreTests/Fixtures/fake-adb`, a scripted stand-in for `adb`; the same stub backs `demo/run.sh`.

Design: Liquid Glass on chrome only (sidebar, toolbar, floating action bar, sheets), solid content rows, one accent
colour, risk tiers as colour + icon + label, motion under 250 ms and off under Reduce Motion.
