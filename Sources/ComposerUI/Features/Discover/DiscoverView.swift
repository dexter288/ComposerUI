import ComposerCore
import ComposerPackagist
import SwiftUI

@MainActor
@Observable
final class DiscoverViewModel {
    var query = ""
    var results: [DiscoveredPackage] = []
    var total = 0
    var nextPage: Int?
    var isSearching = false
    var error: String?
    var selected: ComposerPackageID?
    var detail: PackagistPackage?
    var detailError: String?
    var isLoadingDetail = false
    var pendingSelection: ComposerPackageID?
    var client: PackagistClient?

    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    func search(using client: PackagistClient) {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []; total = 0; nextPage = nil; error = nil
            return
        }
        isSearching = true
        error = nil
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            do {
                let page = try await client.search(text)
                guard !Task.isCancelled else { return }
                results = page.results
                total = page.total
                nextPage = page.nextPage
                if let selected, !results.contains(where: { $0.id == selected }) { self.selected = nil }
                if let want = pendingSelection, results.contains(where: { $0.id == want }) {
                    pendingSelection = nil
                    select(want, using: client)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isSearching = false
        }
    }

    func loadMore(using client: PackagistClient) {
        guard let page = nextPage, !isSearching else { return }
        isSearching = true
        Task {
            do {
                let more = try await client.search(query.trimmingCharacters(in: .whitespaces), page: page)
                results += more.results.filter { new in !results.contains { $0.id == new.id } }
                nextPage = more.nextPage
            } catch {
                self.error = error.localizedDescription
            }
            isSearching = false
        }
    }

    func select(_ id: ComposerPackageID?, using client: PackagistClient) {
        selected = id
        detail = nil
        detailError = nil
        detailTask?.cancel()
        guard let id else { return }
        isLoadingDetail = true
        detailTask = Task {
            do {
                let package = try await client.package(id)
                guard !Task.isCancelled else { return }
                detail = package
            } catch {
                guard !Task.isCancelled else { return }
                detailError = error.localizedDescription
            }
            isLoadingDetail = false
        }
    }
}

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var vm = DiscoverViewModel()

    var body: some View {
        ListDetailLayout {
            VStack(alignment: .leading, spacing: 0) {
                FeatureHeader(item: .discover)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Packagist").font(.headline)
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vm.isSearching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
                Divider()
                list
            }
            .searchable(text: $vm.query, placement: .toolbar, prompt: "Search Packagist")
            .onChange(of: vm.query) { vm.search(using: model.packagist) }
            .onAppear {
                if vm.query.isEmpty, let seed = model.launchOptions.discoverQuery {
                    vm.query = seed
                    vm.pendingSelection = model.launchOptions.package
                    model.launchOptions.discoverQuery = nil
                    vm.search(using: model.packagist)
                }
            }
        } detail: {
            if let selected = vm.selected {
                DiscoverDetailView(id: selected, hit: vm.results.first { $0.id == selected }, package: vm.detail, error: vm.detailError, isLoading: vm.isLoadingDetail)
            } else {
                EmptyState(symbol: "magnifyingglass", title: "Find a package", message: "Search Packagist by name or keyword, then select a result to see its details and add it to this project.")
            }
        }
    }

    private var subtitle: String {
        if vm.query.trimmingCharacters(in: .whitespaces).count < 2 { return "Type at least two characters to search" }
        if vm.results.isEmpty, !vm.isSearching { return "No results" }
        return "\(vm.results.count) of \(Format.compact(vm.total)) results"
    }

    @ViewBuilder
    private var list: some View {
        if let error = vm.error {
            ErrorBanner(message: error) { vm.search(using: model.packagist) }.padding()
        }
        List(selection: Binding(get: { vm.selected }, set: { vm.select($0, using: model.packagist) })) {
            ForEach(vm.results) { hit in
                let installed = model.inventory.value?.package(hit.id)
                PackageRow(
                    name: hit.name,
                    description: hit.description,
                    version: "\(Format.compact(hit.downloads)) downloads · \(Format.compact(hit.favers)) stars",
                    color: installed == nil ? Theme.discover : Theme.color(for: installed!.scope),
                    badge: installed.map { AnyView(ScopeBadge(scope: $0.scope)) },
                    trailing: installed == nil ? nil : AnyView(Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)),
                    abandoned: hit.isAbandoned
                )
                .tag(hit.id)
            }
            if vm.nextPage != nil {
                Button("Load more results") { vm.loadMore(using: model.packagist) }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .listStyle(.inset)
    }
}

struct DiscoverDetailView: View {
    @Environment(AppModel.self) private var model
    var id: ComposerPackageID
    var hit: DiscoveredPackage?
    var package: PackagistPackage?
    var error: String?
    var isLoading: Bool

    @State private var asDev = false
    @State private var constraint = ""

    var body: some View {
        let installed = model.inventory.value?.package(id)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    PackageIcon(color: installed.map { Theme.color(for: $0.scope) } ?? Theme.discover, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(id.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                            if let installed { ScopeBadge(scope: installed.scope) }
                            if package?.isAbandoned ?? hit?.isAbandoned ?? false { Badge(text: "abandoned", color: Theme.danger) }
                        }
                        Text(package?.description ?? hit?.description ?? "").foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }

                if let error { ErrorBanner(message: error) }
                if isLoading, package == nil { ProgressView("Loading from Packagist…") }

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    SectionHeader(title: "Details").gridCellColumns(2)
                    if let installed { DetailRow(label: "Installed", value: installed.version, monospaced: true) }
                    if let latest = package?.latest {
                        DetailRow(label: "Latest version", value: latest.version, monospaced: true)
                        if let released = Format.short(latest.releasedAt) { DetailRow(label: "Released", value: released) }
                        if !latest.license.isEmpty { DetailRow(label: "License", value: latest.license.joined(separator: ", ")) }
                        if let php = latest.requiresPHP { DetailRow(label: "Requires PHP", value: php, monospaced: true) }
                    }
                    if let package {
                        DetailRow(label: "Type", value: package.type)
                        DetailRow(label: "Downloads", value: "\(package.downloadsTotal.formatted()) total, \(Format.compact(package.downloadsMonthly)) this month")
                        DetailRow(label: "Stars", value: package.githubStars.map { "\($0.formatted()) on GitHub, \(package.favers.formatted()) on Packagist" } ?? package.favers.formatted())
                        if !package.maintainers.isEmpty { DetailRow(label: "Maintainers", value: package.maintainers.joined(separator: ", ")) }
                    } else if let hit {
                        DetailRow(label: "Downloads", value: hit.downloads.formatted())
                        DetailRow(label: "Stars", value: hit.favers.formatted())
                    }
                    if let homepage = package?.homepage { LinkRow(label: "Homepage", url: homepage) }
                    if let repo = package?.repository ?? hit?.repository { LinkRow(label: "Repository", url: repo, title: repo.host()) }
                    if let url = id.packagistURL { LinkRow(label: "Packagist", url: url, title: "packagist.org") }
                }

                if let package, !package.keywords.isEmpty {
                    Divider()
                    SectionHeader(title: "Keywords")
                    Text(package.keywords.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }

                if let package, !package.versions.isEmpty {
                    Divider()
                    SectionHeader(title: "Recent versions")
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(package.versions.prefix(8)) { version in
                            HStack {
                                Text(version.version).font(.callout.monospaced())
                                if version.isDev { Badge(text: "dev", color: .gray) } else if !version.isStable { Badge(text: "pre-release", color: .orange) }
                                Spacer()
                                Text(Format.short(version.releasedAt) ?? "").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Divider()
                requireSection(installed: installed)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: package?.latestStable?.version, initial: true) { _, latest in
            if constraint.isEmpty, let latest { constraint = "^" + latest.trimmingCharacters(in: CharacterSet(charactersIn: "v")) }
        }
        .onChange(of: id) { constraint = ""; asDev = false }
    }

    @ViewBuilder
    private func requireSection(installed: InstalledPackage?) -> some View {
        if let installed {
            SectionHeader(title: "Installed")
            Text("Already in this project (\(installed.version)). Open it under Installed to update or remove it.").foregroundStyle(.secondary)
            Button("Show in Installed") { model.selectedPackage = id; model.sidebar = .installed }
        } else if model.project.isGlobal || model.inventory.value?.composerJSON != nil {
            SectionHeader(title: "Add to \(model.project.isGlobal ? "global packages" : model.project.displayName)")
            HStack {
                Toggle("Development dependency (require-dev)", isOn: $asDev)
                Spacer()
                TextField("Constraint", text: $constraint, prompt: Text("^1.0"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 140)
            }
            let command = ComposerCommands.require(id, constraint: constraint.isEmpty ? nil : constraint, dev: asDev, in: model.project)
            TerminalCommandView(
                command: command,
                explanation: asDev ? "Adds the package to require-dev in composer.json and installs it with its dependencies." : "Adds the package to require in composer.json and installs it with its dependencies.",
                workingDirectory: model.project.isGlobal ? nil : model.project.rootURL.path
            )
            Button("Require") { model.require(id, constraint: constraint.isEmpty ? nil : constraint, dev: asDev) }
                .disabled(model.console.isBusy)
        }
    }
}
