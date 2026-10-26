import Foundation
import TetherCore

extension AppModel {
    func checkRootTool() async {
        guard canManageConnections, let sdb = tools.sdb else { return }
        isBusy = true
        defer { isBusy = false }
        rootLocalReport = nil; rootMessage = nil
        do {
            rootLocalReport = try await SamsungRootTool.checkLocalInstallation(tool: URL(fileURLWithPath: rootToolPath), sdb: sdb)
            UserDefaults.standard.set(rootToolPath, forKey: "rootToolPath")
            UserDefaults.standard.set(rootPayloadPath, forKey: "rootPayloadPath")
        } catch { rootMessage = advice(for: error) }
    }

    func prepareRootCommand(_ command: String) {
        guard canManageConnections, let tv = selectedTizen, let sdb = tools.sdb else { return }
        do {
            guard LocalNetwork.addresses.contains(rootCallbackAddress) else { throw SamsungRootError.invalidTarget }
            pendingRootRequest = try SamsungRootRequest(tool: URL(fileURLWithPath: rootToolPath), sdb: sdb,
                device: tv, callback: rootCallbackAddress, command: command, runtime: rootRuntime,
                payloads: rootPayloadPath.isEmpty ? nil : URL(fileURLWithPath: rootPayloadPath))
            rootMessage = nil
        } catch { rootMessage = advice(for: error) }
    }

    func executeRootCommand(_ request: SamsungRootRequest) {
        guard canManageConnections, pendingRootRequest?.id == request.id,
              selectedTizen?.serial == request.deviceSerial,
              LocalNetwork.addresses.contains(request.callback) else { pendingRootRequest = nil; return }
        pendingRootRequest = nil
        isBusy = true; rootOperationRunning = true
        connectionGeneration += 1
        rootResult = nil
        rootMessage = "Attempting root, running the command, then checking cleanup. Keep Tether open until this finishes."
        Task {
            defer { isBusy = false; rootOperationRunning = false }
            await log.append("\(request.deviceSerial): user-confirmed experimental root command started; no automatic restore point")
            do {
                let result = try await SamsungRootTool.run(request, confirmed: true)
                guard selectedTizen?.serial == request.deviceSerial else { return }
                rootResult = result
                rootMessage = result.timedOut ? "The command timed out. The tool confirmed session cleanup; command changes are not rolled back."
                    : "The tool confirmed an authenticated UID 0 session and cleanup. The session has ended; root is not kept enabled."
                UserDefaults.standard.set(rootToolPath, forKey: "rootToolPath")
                UserDefaults.standard.set(rootPayloadPath, forKey: "rootPayloadPath")
                await log.append("\(request.deviceSerial): root command exited \(result.exitCode.map(String.init) ?? "unknown"); authenticated UID 0 and cleanup reported")
            } catch {
                rootMessage = advice(for: error)
                await log.append("\(request.deviceSerial): root attempt failed; completion/cleanup unverified")
            }
        }
    }
}
