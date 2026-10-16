import ComposerCore
import SwiftUI

struct InstalledView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var query = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", direct = "Direct", dev = "Dev", transitive = "Transitive"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var model = model
        ListDetailLayout {
            VStack(alignment: .leading, spacing: 0) {
                FeatureHeader(item: .installed)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.project.isGlobal ? "Global packages" : "Your packages").font(.headline)
                        Spacer()
                        Text(countText).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                Divider()
                content
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search Installed Packages")
        } detail: {
            if let id = model.selectedPackage, let package = model.inventory.value?.package(id) {
                PackageDetailView(package: package)
            } else {
                EmptyState(symbol: "shippingbox", title: "No package selected", message: "Select a package to see its details, dependencies and actions.")
            }
        }
    }

    private var countText: String {
        guard let inventory = model.inventory.value else { return model.inventory.isLoading ? "Loading…" : "" }
        let direct = inventory.packages.filter(\.isDirect).count
        return "\(inventory.packages.count) packages, \(direct) required directly"
    }

    private var filtered: [InstalledPackage] {
        let packages = model.inventory.value?.packages ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return packages.filter { package in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .direct: package.isDirect
            case .dev: package.scope == .development
            case .transitive: package.scope == .transitive
            }
            guard matchesFilter else { return false }
            guard !q.isEmpty else { return true }
            return package.name.contains(q) || package.description.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var model = model
        if let error = model.inventory.errorMessage {
            ErrorBanner(message: error) { Task { await model.refreshInventory() } }.padding()
        }
        if let inventory = model.inventory.value, !inventory.hasVendor {
            VStack(spacing: 12) {
                EmptyState(symbol: "tray", title: "Nothing installed yet", message: inventory.hasLockFile ? "This project has a composer.lock but no vendor folder. Install the locked dependencies to get started." : "This project has a composer.json but no vendor folder. Install to resolve and download its dependencies.")
                let command = ComposerCommands.install(model.project)
                TerminalCommandView(command: command, explanation: "Downloads every package into vendor/ and writes composer.lock if missing.", workingDirectory: model.project.rootURL.path)
                    .frame(maxWidth: 520)
                Button("Install Dependencies") { model.install() }.disabled(model.console.isBusy)
                Spacer()
            }
            .padding()
        } else if model.inventory.isLoading, model.inventory.value == nil {
            VStack { Spacer(); ProgressView("Reading installed packages…"); Spacer() }.frame(maxWidth: .infinity)
        } else {
            List(selection: $model.selectedPackage) {
                ForEach(filtered) { package in
                    PackageRow(
                        name: package.name,
                        description: package.description,
                        version: package.version,
                        color: Theme.color(for: package.scope),
                        badge: AnyView(ScopeBadge(scope: package.scope)),
                        trailing: AnyView(statusIcon(for: package)),
                        abandoned: package.isAbandoned
                    )
                    .tag(package.id)
                }
            }
            .listStyle(.inset)
            .overlay {
                if filtered.isEmpty, !(model.inventory.value?.packages.isEmpty ?? true) {
                    EmptyState(symbol: "magnifyingglass", title: "No matches", message: "No installed package matches “\(query)”.")
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for package: InstalledPackage) -> some View {
        if !model.advisories(for: package.id).isEmpty {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.red).help("Security advisory")
        } else if model.outdatedEntry(package.id) != nil {
            Image(systemName: "arrow.up.circle.fill").foregroundStyle(.blue).help("Update available")
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Installed")
        }
    }
}
