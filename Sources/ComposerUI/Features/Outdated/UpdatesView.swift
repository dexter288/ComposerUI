import ComposerCore
import SwiftUI

struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .direct
    @State private var query = ""
    @State private var confirmUpdateAll = false

    enum Filter: String, CaseIterable, Identifiable {
        case direct = "Direct", all = "All"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var model = model
        ListDetailLayout {
            VStack(alignment: .leading, spacing: 0) {
                FeatureHeader(item: .updates)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Available updates").font(.headline)
                        Spacer()
                        Text(countText).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
                Divider()
                content
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search Updates")
        } detail: {
            if let id = model.selectedPackage, let package = model.inventory.value?.package(id) {
                PackageDetailView(package: package)
            } else {
                updateAllPane
            }
        }
    }

    private var countText: String {
        guard let list = model.outdated.value else { return model.outdated.isLoading ? "Checking Packagist…" : "" }
        let direct = list.filter(\.isDirect).count
        if list.isEmpty { return "Everything is up to date" }
        return "\(list.count) outdated, \(direct) required directly"
    }

    private var filtered: [OutdatedPackage] {
        let list = model.outdated.value ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return list.filter { entry in
            if filter == .direct, !entry.isDirect { return false }
            guard !q.isEmpty else { return true }
            return entry.name.contains(q) || entry.description.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var model = model
        if let error = model.outdated.errorMessage {
            ErrorBanner(message: error) { Task { await model.refreshOutdated() } }.padding()
        }
        if model.outdated.isLoading, model.outdated.value == nil {
            VStack { Spacer(); ProgressView("Checking for updates…"); Spacer() }.frame(maxWidth: .infinity)
        } else if (model.outdated.value ?? []).isEmpty {
            EmptyState(symbol: "checkmark.circle", title: "Up to date", message: "Every installed package is at its latest release.")
        } else {
            List(selection: $model.selectedPackage) {
                ForEach(filtered) { entry in
                    let scope = model.inventory.value?.package(entry.id)?.scope ?? (entry.isDirect ? .production : .transitive)
                    PackageRow(
                        name: entry.name,
                        description: entry.description,
                        version: "\(entry.installedVersion)  →  \(entry.latestVersion)",
                        color: Theme.color(for: scope),
                        badge: AnyView(statusBadge(entry)),
                        trailing: AnyView(Image(systemName: "arrow.up.circle.fill").foregroundStyle(.blue)),
                        abandoned: entry.isAbandoned
                    )
                    .tag(entry.id)
                }
            }
            .listStyle(.inset)
        }
    }

    private func statusBadge(_ entry: OutdatedPackage) -> some View {
        switch entry.status {
        case .semverSafe: Badge(text: "safe update", color: .green)
        case .updatePossible: Badge(text: "new major", color: .orange)
        default: Badge(text: "update", color: .blue)
        }
    }

    @ViewBuilder
    private var updateAllPane: some View {
        let list = model.outdated.value ?? []
        let safe = list.filter { $0.status == .semverSafe }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Update everything").font(.title2.weight(.semibold))
                Text("Composer updates every package to the newest version its constraint in composer.json allows, then rewrites composer.lock. Packages marked “new major” need their constraint changed first; select one to do that.")
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    DetailRow(label: "Outdated", value: "\(list.count)")
                    DetailRow(label: "Within constraints", value: "\(safe.count)")
                    DetailRow(label: "Need a new constraint", value: "\(list.count - safe.count)")
                    if let at = Format.relative(model.outdated.loadedAt) {
                        DetailRow(label: "Checked", value: at)
                    }
                }
                let command = ComposerCommands.update([], in: model.project)
                TerminalCommandView(command: command, explanation: "Resolves and installs the newest allowed version of every dependency.", workingDirectory: model.project.isGlobal ? nil : model.project.rootURL.path)
                HStack {
                    Button("Update All") { confirmUpdateAll = true }
                        .disabled(list.isEmpty || model.console.isBusy)
                        .confirmationDialog("Update all packages?", isPresented: $confirmUpdateAll) {
                            Button("Update All") { model.updateAll() }
                        } message: {
                            Text("This runs composer update, which may change many packages and composer.lock.")
                        }
                    Button("Check Again") { Task { await model.refreshOutdated() } }
                        .disabled(model.console.isBusy)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
