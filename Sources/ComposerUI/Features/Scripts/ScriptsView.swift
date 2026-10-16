import ComposerCore
import SwiftUI

struct ScriptsView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: String?

    private var scripts: [ComposerScript] { model.inventory.value?.composerJSON?.scripts ?? [] }

    var body: some View {
        ListDetailLayout {
            VStack(alignment: .leading, spacing: 0) {
                FeatureHeader(item: .scripts)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("composer.json scripts").font(.headline)
                        Text("\(scripts.filter { !$0.isLifecycleEvent }.count) scripts, \(scripts.filter(\.isLifecycleEvent).count) lifecycle hooks").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
                Divider()
                if scripts.isEmpty {
                    EmptyState(symbol: "terminal", title: "No scripts", message: model.project.isGlobal ? "Global Composer has no scripts." : "This composer.json defines no scripts.")
                } else {
                    List(selection: $selected) {
                        Section("Scripts") {
                            ForEach(scripts.filter { !$0.isLifecycleEvent }) { row($0) }
                        }
                        let hooks = scripts.filter(\.isLifecycleEvent)
                        if !hooks.isEmpty {
                            Section("Lifecycle hooks (run automatically by Composer)") {
                                ForEach(hooks) { row($0) }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        } detail: {
            if let name = selected, let script = scripts.first(where: { $0.name == name }) {
                scriptDetail(script)
            } else {
                EmptyState(symbol: "terminal", title: "Select a script", message: "Scripts run with composer run-script, inside the project folder, with vendor/bin on PATH.")
            }
        }
        .onChange(of: scripts.count, initial: true) {
            if selected == nil, let want = model.launchOptions.script, scripts.contains(where: { $0.name == want }) { selected = want }
        }
    }

    private func row(_ script: ComposerScript) -> some View {
        PackageRow(
            name: script.name,
            description: script.description ?? script.commands.joined(separator: " && "),
            version: nil,
            color: script.isLifecycleEvent ? Theme.transitive : Theme.production,
            badge: script.isLifecycleEvent ? AnyView(Badge(text: "hook", color: .gray)) : nil
        )
        .tag(script.name)
    }

    private func scriptDetail(_ script: ComposerScript) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    PackageIcon(color: Theme.production, symbol: "terminal.fill", size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(script.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                        if let description = script.description { Text(description).foregroundStyle(.secondary) }
                    }
                }
                SectionHeader(title: "What it runs")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(script.commands.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                Divider()
                SectionHeader(title: "Run")
                let command = ComposerCommands.runScript(script.name, in: model.project)
                TerminalCommandView(command: command, explanation: script.isLifecycleEvent ? "Composer runs this hook itself during install and update. Running it here triggers it on demand." : "Runs the script in the project folder. Output appears in the console below.", workingDirectory: model.project.rootURL.path)
                Button("Run Script") { model.runScript(script.name); model.console.isExpanded = true }
                    .disabled(model.console.isBusy)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
