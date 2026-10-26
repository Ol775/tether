import AppKit
import Foundation
import TetherCore

private struct ReconnectTarget: Codable {
    let service: DebugService
    let address: String
    let port: String
}

extension AppModel {
    var canManageConnections: Bool {
        if case .installing = updateStatus { return false }
        return !isBusy && !restartingApp && !restartingService
    }

    var canRestartApp: Bool { canManageConnections && Bundle.main.bundleURL.pathExtension == "app" }

    func openDiagnostics(service: DebugService? = nil, endpoint: ConnectionEndpoint? = nil) {
        let serial = selectedTizen?.serial ?? selected?.serial
        diagnosticService = service ?? (selectedTizen != nil ? .sdb : selected != nil ? .adb : diagnosticService)
        if let endpoint = endpoint ?? serial.flatMap({ $0.contains(":") ? try? ConnectionEndpoint(address: $0, port: diagnosticService.defaultPort) : nil }) {
            diagnosticAddress = endpoint.host
            diagnosticPort = String(endpoint.port)
        }
        diagnosticReport = nil
        serviceMessage = nil
        showDiagnostics = true
    }

    func startDiagnostics() {
        guard canManageConnections, let endpoint = try? ConnectionEndpoint(address: diagnosticAddress, port: diagnosticPort) else { return }
        let service = diagnosticService
        let addresses = LocalNetwork.addresses
        diagnosticReport = nil
        serviceMessage = nil
        diagnosticProgress = "Starting checks…"
        isBusy = true
        diagnosticTask = Task {
            defer { diagnosticProgress = nil; diagnosticTask = nil; isBusy = false }
            do {
                diagnosticReport = try await ConnectionDiagnostics.run(service: service, endpoint: endpoint,
                    localAddresses: addresses, adb: adb, sdb: sdb, progress: { @Sendable [weak self] line in
                        await MainActor.run { self?.diagnosticProgress = line }
                    })
            } catch is CancellationError { serviceMessage = "Checks stopped. No device settings were changed." }
            catch { serviceMessage = advice(for: error) }
        }
    }

    func restartService(_ service: DebugService) async {
        guard canManageConnections else { return }
        guard service != .sdb || tizenToolsReady else {
            serviceMessage = "Set up Samsung tools before restarting SDB."
            return
        }
        let selection = service == .sdb ? selectedTizenSerial : selectedSerial
        let serials = service == .sdb ? tizenDevices.map(\.serial) : devices.map(\.serial)
        var endpoints = serials.filter { $0.contains(":") }.compactMap { try? ConnectionEndpoint(address: $0, port: service.defaultPort) }
        if service == diagnosticService, let requested = try? ConnectionEndpoint(address: diagnosticAddress, port: diagnosticPort), !endpoints.contains(requested) {
            endpoints.append(requested)
        }
        isBusy = true
        restartingService = true
        defer { restartingService = false }
        connectionGeneration += 1
        diagnosticReport = nil
        serviceMessage = "Restarting \(service.rawValue.uppercased())…"
        if service == .sdb { selectedTizenSerial = nil; tizenDevices = [] }
        else { selectedSerial = nil; devices = [] }
        var failed: [String] = []
        do {
            if service == .sdb { try await sdb.restartServer() }
            else { try await adb.restartServer() }
            for endpoint in endpoints {
                serviceMessage = "Reconnecting \(endpoint.host):\(endpoint.port)…"
                do {
                    if service == .sdb { try await tizenManager.connect(host: endpoint.host, port: endpoint.port) }
                    else { try await DeviceManager(adb: adb).connect(host: endpoint.host, port: endpoint.port) }
                } catch { failed.append("\(endpoint.host):\(endpoint.port): \(advice(for: error))") }
            }
            serviceMessage = failed.isEmpty ? "\(service.rawValue.uppercased()) restarted.\(endpoints.isEmpty ? "" : " Reconnected the requested devices.")"
                : "\(service.rawValue.uppercased()) restarted, but reconnection failed:\n" + failed.joined(separator: "\n")
        } catch { serviceMessage = "Couldn’t restart \(service.rawValue.uppercased()): \(advice(for: error))" }
        isBusy = false
        if service == .sdb {
            await pollTizen()
            if let selection, tizenDevices.contains(where: { $0.serial == selection }) { selectedTizenSerial = selection; try? await reloadTizen() }
        } else {
            await pollDevices()
            if let selection, devices.contains(where: { $0.serial == selection }) { selectedSerial = selection; try? await reload() }
        }
    }

    func restartApplication() {
        guard canRestartApp else { return }
        let targets = tizenDevices.map { ReconnectTarget(service: .sdb, address: $0.serial, port: "26101") }
            + devices.filter { $0.serial.contains(":") }.map { ReconnectTarget(service: .adb, address: $0.serial, port: "5555") }
        do {
            let data = try JSONEncoder().encode(targets)
            let defaults = UserDefaults.standard
            defaults.set(data, forKey: "restartConnections")
            defaults.set(selectedTizenSerial ?? selectedSerial, forKey: "restartSelection")
            try AppRelauncher.prepare(app: Bundle.main.bundleURL)
            restartingApp = true
            // macOS prevents termination while a sheet is open by default. This explicit restart
            // has already passed the operation guard; these connection sheets hold no unsaved documents.
            for window in NSApp.windows { window.preventsApplicationTerminationWhenModal = false }
            NSApp.terminate(nil)
            // A delegate can still decline termination. Don't leave recovery controls locked if it does.
            restartingApp = false
            defaults.removeObject(forKey: "restartConnections")
            defaults.removeObject(forKey: "restartSelection")
            alert = AppAlert(title: "Tether couldn’t quit", message: "Close any open system dialogs and try restarting again.")
        } catch {
            UserDefaults.standard.removeObject(forKey: "restartConnections")
            UserDefaults.standard.removeObject(forKey: "restartSelection")
            alert = AppAlert(title: "Couldn’t restart Tether", message: error.localizedDescription)
        }
    }

    func resumeConnectionsAfterRestart() async {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "restartConnections") else { return }
        let selection = defaults.string(forKey: "restartSelection")
        defaults.removeObject(forKey: "restartConnections")
        defaults.removeObject(forKey: "restartSelection")
        guard let targets = try? JSONDecoder().decode([ReconnectTarget].self, from: data) else { return }
        var failures: [String] = []
        for target in targets {
            guard let endpoint = try? ConnectionEndpoint(address: target.address, port: target.port) else { continue }
            do {
                if target.service == .sdb { try await connectTizen(host: endpoint.host, port: endpoint.port) }
                else { try await connect(host: endpoint.host, port: endpoint.port) }
            } catch { failures.append("\(target.address): \(advice(for: error))") }
        }
        if let selection {
            if tizenDevices.contains(where: { $0.serial == selection }) { await selectTizen(selection) }
            else if devices.contains(where: { $0.serial == selection }) { await select(selection) }
        }
        if !failures.isEmpty { alert = AppAlert(title: "Tether restarted; some devices couldn’t reconnect", message: failures.joined(separator: "\n")) }
    }
}
