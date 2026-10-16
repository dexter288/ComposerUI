import AppKit
import ComposerCore
import SwiftUI

struct ConfigurationView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var confirmSelfUpdate = false

    var body: some View {
        @Bindable var settings = model.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FeatureHeader(item: .configuration).padding(.horizontal, -20).padding(.top, -16)

                if let error = model.environment.errorMessage {
                    ErrorBanner(message: error) { Task { await model.loadEnvironment() } }
                }

                GroupBox("Toolchain") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        let env = model.environment.value
                        DetailRow(label: "Composer", value: env?.composerVersion.map { "\($0)  ·  \(env?.composerPath ?? "")" } ?? env?.composerPath ?? "Not found", monospaced: true)
                        DetailRow(label: "PHP", value: env?.phpVersion.map { "\($0)  ·  \(env?.phpPath ?? "")" } ?? env?.phpPath ?? "Not found", monospaced: true)
                        DetailRow(label: "Composer home", value: env?.composerHome ?? "", monospaced: true)
                        DetailRow(label: "Project", value: model.project.isGlobal ? "Global (\(model.project.rootURL.path))" : model.project.rootURL.path, monospaced: true)
                        GridRow {
                            Text("Composer path").foregroundStyle(.secondary)
                            HStack {
                                TextField("Detect automatically", text: $settings.composerPath).textFieldStyle(.roundedBorder).font(.body.monospaced())
                                Button("Choose…") { choose(into: \.composerPath) }
                            }
                        }
                        GridRow {
                            Text("PHP path").foregroundStyle(.secondary)
                            HStack {
                                TextField("Detect automatically", text: $settings.phpPath).textFieldStyle(.roundedBorder).font(.body.monospaced())
                                Button("Choose…") { choose(into: \.phpPath) }
                            }
                        }
                        GridRow {
                            Text("")
                            Text("Leave empty to detect Homebrew, Herd, MAMP or /usr/local installs. The app runs Composer with its own clean PATH, so shell aliases and exported variables do not apply.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: settings.composerPath) { model.settingsChanged() }
                .onChange(of: settings.phpPath) { model.settingsChanged() }

                GroupBox("Maintenance") {
                    VStack(alignment: .leading, spacing: 12) {
                        actionRow(ComposerCommands.diagnose(model.project), explanation: "Checks the platform, network access to Packagist and common misconfigurations. Output appears in the console.", button: "Diagnose") { model.diagnose() }
                        Divider()
                        actionRow(ComposerCommands.clearCache(), explanation: "Deletes Composer's download and metadata caches. The next install re-downloads what it needs.", button: "Clear Cache") { model.clearCache() }
                        Divider()
                        actionRow(ComposerCommands.selfUpdate(), explanation: "Updates the Composer executable itself to the latest stable release.", button: "Update Composer") { confirmSelfUpdate = true }
                            .confirmationDialog("Update Composer?", isPresented: $confirmSelfUpdate) {
                                Button("Update Composer") { model.selfUpdate() }
                            } message: {
                                Text("This replaces the composer executable at \(model.environment.value?.composerPath ?? "its current path"). Homebrew-managed installs are better updated with brew upgrade composer.")
                            }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Effective settings for this project, from composer config --list").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            TextField("Filter", text: $query).textFieldStyle(.roundedBorder).frame(width: 200)
                        }
                        let entries = (model.environment.value?.config ?? []).filter { query.isEmpty || $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
                        if entries.isEmpty {
                            Text(model.environment.isLoading ? "Loading…" : "No settings to show.").foregroundStyle(.secondary).padding(.vertical, 8)
                        } else {
                            Table(entries) {
                                TableColumn("Key") { Text($0.key).font(.callout.monospaced()) }.width(min: 160, ideal: 240)
                                TableColumn("Value") { Text($0.value).font(.callout.monospaced()).textSelection(.enabled) }
                            }
                            .frame(minHeight: 280, idealHeight: CGFloat(entries.count) * 24 + 40)
                        }
                    }
                    .padding(6)
                } label: {
                    Text("Composer configuration")
                }
            }
            .padding(20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionRow(_ command: ComposerCommand, explanation: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TerminalCommandView(command: command, explanation: explanation)
            Button(button, action: action).disabled(model.console.isBusy)
        }
    }

    private func choose(into keyPath: ReferenceWritableKeyPath<ToolchainSettings, String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Use"
        if panel.runModal() == .OK, let url = panel.url {
            model.settings[keyPath: keyPath] = url.path
        }
    }
}
