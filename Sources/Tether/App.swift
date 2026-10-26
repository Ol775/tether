import AppKit
import SwiftUI

@main
struct TetherApp: App {
    @State private var model = AppModel()

    init() {
        // Lets the bare executable (swift run, demo/run.sh) get a window and focus like the bundled app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Tether") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1240, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await model.checkForUpdates(userInitiated: true) } }
                Button("Restart Tether") { model.restartApplication() }.disabled(!model.canRestartApp)
            }
            CommandGroup(replacing: .help) {
                Button("Connection diagnostics…") { model.openDiagnostics() }
                    .disabled(model.isBusy || model.showDiagnostics)
            }
        }
    }
}
