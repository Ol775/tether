# Add Device verification

2026-10-23

- Debug build: `swift build --disable-sandbox` passed.
- `swift test --disable-sandbox --skip 'PortCheckerTests.detects'`: 159 tests passed, including endpoint validation, deadline and cancellation.
- Open/refused socket integration tests are present, but this execution sandbox blocks binding loopback sockets. Run the full `swift test` suite on an unrestricted development host.
- Native Mac UI verified: Fire TV, phone pairing and Samsung layouts; persistent footer; labelled fields; discovery empty state; port defaults; diagnostic reset after address edit.
- Native app checker verified against local ADB port 5038 (open) and local port 1 (refused). No pairing or connection commands were sent to a device.
- Release build reached linking but its dSYM generation was blocked by the environment; the local app bundle uses the successful debug build.
- Local bundle rebuilt and ad-hoc signed at build/Tether.app.
