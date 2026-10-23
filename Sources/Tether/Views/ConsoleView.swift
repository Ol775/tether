import SwiftUI
import TetherCore

struct ConsoleView: View {
    @Environment(AppModel.self) private var model

    private struct Line: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case command, output, error }
    }

    private struct Pending: Identifiable { let id = UUID(); let command: String; let reason: String }

    @State private var input = ""
    @State private var lines: [Line] = []
    @State private var pending: Pending?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if lines.isEmpty {
                            Text("Runs on \(model.selected?.model ?? "the device") with adb shell. Read-only commands run straight away; anything that could change the device asks first.")
                                .foregroundStyle(.secondary).font(.callout)
                        }
                        ForEach(lines) { line in
                            Text(line.text).font(.callout.monospaced())
                                .foregroundStyle(line.kind == .command ? Color.accentColor : line.kind == .error ? .red : .primary)
                                .textSelection(.enabled).id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }
                .onChange(of: lines.count) { if let last = lines.last { withAnimation(Theme.quick) { proxy.scrollTo(last.id, anchor: .bottom) } } }
            }
            Divider()
            HStack(spacing: 8) {
                Text("$").font(.body.monospaced()).foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Command", text: $input).textFieldStyle(.plain).font(.body.monospaced())
                    .focused($focused).onSubmit { submit(confirmed: false) }
                Button("Run") { submit(confirmed: false) }.buttonStyle(.glassProminent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
            }
            .padding(14)
        }
        .onAppear { focused = true }
        .alert("Run this command?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { p in
            Button("Run anyway", role: .destructive) { input = p.command; submit(confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: { p in Text("`\(p.command)` \(p.reason).") }
    }

    private func submit(confirmed: Bool) {
        let command = input.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        Task {
            do {
                let output = try await model.console(command, confirmed: confirmed)
                lines.append(Line(text: "$ \(command)", kind: .command))
                if !output.isEmpty { lines.append(Line(text: output.trimmingCharacters(in: .newlines), kind: .output)) }
                input = ""
            } catch ConsoleError.needsConfirmation(let reason) {
                pending = Pending(command: command, reason: reason)
            } catch {
                lines.append(Line(text: "$ \(command)", kind: .command))
                lines.append(Line(text: model.advice(for: error), kind: .error))
                input = ""
            }
        }
    }
}
