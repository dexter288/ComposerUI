import ComposerCore
import SwiftUI

/// Detail pane for an installed package: metadata, graph neighbours, and update/remove actions.
struct PackageDetailView: View {
    @Environment(AppModel.self) private var model
    var package: InstalledPackage

    @State private var confirmRemove = false

    var body: some View {
        let detail = model.details[package.id]
        let outdated = model.outdatedEntry(package.id)
        let graph = model.inventory.value?.graph
        let advisories = model.advisories(for: package.id)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(outdated: outdated, advisories: advisories)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    SectionHeader(title: "Details").gridCellColumns(2)
                    DetailRow(label: "Installed", value: package.version, monospaced: true)
                    if let outdated {
                        DetailRow(label: "Latest version", value: outdated.latestVersion, monospaced: true)
                    } else if model.outdated.isLoading {
                        DetailRow(label: "Latest version", value: "Checking…")
                    } else if model.outdated.value != nil {
                        DetailRow(label: "Latest version", value: "Up to date")
                    }
                    if let constraint = constraint {
                        DetailRow(label: "Constraint", value: constraint, monospaced: true)
                    }
                    if let detail {
                        DetailRow(label: "Type", value: detail.type)
                        if !detail.licenses.isEmpty {
                            DetailRow(label: "License", value: detail.licenses.map { $0.spdx ?? $0.name }.joined(separator: ", "))
                        }
                        if let released = Format.short(detail.released) {
                            DetailRow(label: "Released", value: released)
                        }
                    }
                    if let homepage = package.homepage ?? detail?.homepage {
                        LinkRow(label: "Homepage", url: homepage)
                    }
                    if let source = detail?.sourceURL ?? package.source {
                        LinkRow(label: "Source", url: source, title: source.host().map { $0.replacingOccurrences(of: "www.", with: "") })
                    }
                    if let packagist = package.id.packagistURL {
                        LinkRow(label: "Packagist", url: packagist, title: "packagist.org")
                    }
                    if let path = detail?.installPath {
                        GridRow {
                            Text("Location").foregroundStyle(.secondary)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            } label: {
                                Label(path.replacingOccurrences(of: model.project.rootURL.path + "/", with: ""), systemImage: "folder")
                                    .font(.callout.monospaced())
                            }
                            .buttonStyle(.link)
                        }
                    }
                }

                if !advisories.isEmpty {
                    Divider()
                    SectionHeader(title: "Security advisories")
                    ForEach(advisories) { advisory in
                        AdvisoryCard(advisory: advisory)
                    }
                }

                if let detail, !detail.keywords.isEmpty {
                    Divider()
                    SectionHeader(title: "Keywords")
                    Text(detail.keywords.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }

                Divider()
                graphSection(title: "Dependencies", ids: graph?.dependencies(of: package.id) ?? detail?.requires.map(\.id).filter { !$0.isPlatform } ?? [], empty: "No dependencies.")
                Divider()
                graphSection(title: "Dependents", ids: graph?.dependents(of: package.id) ?? [], empty: package.isDirect ? "Required directly by this project." : "No installed package requires it.")

                if let detail, !detail.suggests.isEmpty {
                    Divider()
                    SectionHeader(title: "Suggests")
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(detail.suggests.keys.sorted(), id: \.self) { key in
                            HStack(alignment: .top) {
                                Text(key).font(.callout.monospaced())
                                Text(detail.suggests[key] ?? "").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider()
                actions(outdated: outdated)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: package.id) { model.loadDetail(for: package.id) }
    }

    private var constraint: String? {
        guard let json = model.inventory.value?.composerJSON else { return nil }
        return json.require.first { ComposerPackageID($0.key) == package.id }?.value
            ?? json.requireDev.first { ComposerPackageID($0.key) == package.id }?.value
    }

    @ViewBuilder
    private func header(outdated: OutdatedPackage?, advisories: [SecurityAdvisory]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PackageIcon(color: Theme.color(for: package.scope), size: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(package.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                    ScopeBadge(scope: package.scope)
                    if package.isAbandoned { Badge(text: "abandoned", color: Theme.danger) }
                    if !advisories.isEmpty {
                        Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.red).help("\(advisories.count) security advisories")
                    } else if outdated != nil {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.blue).help("Update available")
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Installed")
                    }
                }
                if !package.description.isEmpty {
                    Text(package.description).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if package.isAbandoned {
                    Text(package.replacement.map { "Abandoned. The author suggests \($0) instead." } ?? "Abandoned by its author. No replacement suggested.")
                        .font(.callout).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func graphSection(title: String, ids: [ComposerPackageID], empty: String) -> some View {
        SectionHeader(title: title)
        if ids.isEmpty {
            Text(empty).foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    let installed = model.inventory.value?.package(id)
                    Button {
                        if installed != nil { model.selectedPackage = id; model.sidebar = .installed }
                    } label: {
                        HStack(spacing: 4) {
                            Text(id.name).font(.callout.monospaced())
                            if installed == nil { Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(.secondary) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .overlay(Capsule().stroke(Color(nsColor: .separatorColor)))
                    }
                    .buttonStyle(.plain)
                    .disabled(installed == nil)
                    .help(installed == nil ? "Not installed (provided by another package or a platform requirement)" : "Show \(id.name)")
                }
            }
        }
    }

    @ViewBuilder
    private func actions(outdated: OutdatedPackage?) -> some View {
        if let outdated {
            SectionHeader(title: "Update")
            let command = ComposerCommands.update([package.id], in: model.project)
            TerminalCommandView(
                command: command,
                explanation: outdated.status == .semverSafe
                    ? "Updates \(package.name) to \(outdated.latestVersion) within the constraint in composer.json, along with its dependencies."
                    : "\(outdated.latestVersion) is outside the constraint in composer.json. Run this to update within the constraint, or change the constraint first.",
                workingDirectory: model.project.isGlobal ? nil : model.project.rootURL.path
            )
            HStack {
                Button("Update") { model.update([package.id]) }
                    .disabled(model.console.isBusy)
                if outdated.status == .updatePossible {
                    Button("Require \(outdated.latestVersion)") {
                        model.require(package.id, constraint: "^\(outdated.latestVersion.trimmingCharacters(in: CharacterSet(charactersIn: "v")))", dev: package.isDev)
                    }
                    .disabled(model.console.isBusy)
                    .help("Changes the constraint in composer.json to ^\(outdated.latestVersion) and updates")
                }
            }
        }

        SectionHeader(title: "Remove")
        if package.isDirect {
            let command = ComposerCommands.remove(package.id, dev: package.isDev, in: model.project)
            TerminalCommandView(
                command: command,
                explanation: "Removes \(package.name) from composer.json and uninstalls it, together with dependencies nothing else needs.",
                workingDirectory: model.project.isGlobal ? nil : model.project.rootURL.path
            )
            Button("Remove", role: .destructive) { confirmRemove = true }
                .disabled(model.console.isBusy)
                .confirmationDialog("Remove \(package.name)?", isPresented: $confirmRemove) {
                    Button("Remove", role: .destructive) { model.remove(package) }
                } message: {
                    Text("This runs composer remove and updates composer.json and composer.lock.")
                }
        } else {
            Text("This package is installed because another package requires it. Remove the packages that depend on it and it goes away with them.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct AdvisoryCard: View {
    var advisory: SecurityAdvisory
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Badge(text: advisory.severity.rawValue, color: Theme.color(for: advisory.severity))
                if let cve = advisory.cve { Text(cve).font(.caption.monospaced()).foregroundStyle(.secondary) }
                Spacer()
                if let reported = Format.short(advisory.reportedAt) { Text(reported).font(.caption).foregroundStyle(.tertiary) }
            }
            Text(advisory.title).font(.callout.weight(.medium)).textSelection(.enabled)
            HStack {
                Text("Affects ").foregroundStyle(.secondary) + Text(advisory.affectedVersions).font(.callout.monospaced())
                Spacer()
                if let link = advisory.link {
                    Link(destination: link) { Label("Details", systemImage: "arrow.up.right").font(.caption) }
                }
            }
            .font(.callout)
        }
        .padding(10)
        .background(Theme.color(for: advisory.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Wraps chips onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
