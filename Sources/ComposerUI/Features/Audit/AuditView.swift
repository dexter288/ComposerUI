import ComposerCore
import SwiftUI

struct AuditView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: AuditSelection?

    enum AuditSelection: Hashable {
        case advisories(ComposerPackageID)
        case abandoned(ComposerPackageID)
    }

    var body: some View {
        ListDetailLayout {
            VStack(alignment: .leading, spacing: 0) {
                FeatureHeader(item: .audit)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline).font(.headline)
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.refreshAudit() }
                    } label: { Label("Run Again", systemImage: "arrow.clockwise") }
                        .disabled(model.console.isBusy)
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
                Divider()
                list
            }
        } detail: {
            detail
        }
        .onChange(of: model.audit.loadedAt, initial: true) {
            if selected == nil, let want = model.launchOptions.package, model.audit.value?.affectedPackages.contains(want) == true {
                selected = .advisories(want)
            }
        }
    }

    private var headline: String {
        guard let report = model.audit.value else { return model.audit.isLoading ? "Auditing…" : "Audit" }
        if report.isClean { return "No known vulnerabilities" }
        return "\(report.advisories.count) advisories in \(report.affectedPackages.count) packages"
    }

    private var subtitle: String {
        if let at = Format.relative(model.audit.loadedAt) { return "Checked \(at) against Packagist's advisory database" }
        return "Composer checks composer.lock against Packagist's security advisories"
    }

    @ViewBuilder
    private var list: some View {
        if let error = model.audit.errorMessage {
            ErrorBanner(message: error) { Task { await model.refreshAudit() } }.padding()
        }
        if model.audit.isLoading, model.audit.value == nil {
            VStack { Spacer(); ProgressView("Running composer audit…"); Spacer() }.frame(maxWidth: .infinity)
        } else if let report = model.audit.value {
            if report.isClean {
                EmptyState(symbol: "checkmark.shield", title: "All clear", message: "No security advisories affect the installed packages, and none are abandoned.")
            } else {
                List(selection: $selected) {
                    if !report.advisories.isEmpty {
                        Section("Security advisories") {
                            ForEach(report.affectedPackages, id: \.self) { id in
                                let items = report.advisories.filter { $0.package == id }
                                let worst = items.map(\.severity).max() ?? .unknown
                                PackageRow(
                                    name: id.name,
                                    description: items.first?.title ?? "",
                                    version: model.inventory.value?.package(id)?.version,
                                    color: Theme.color(for: worst),
                                    badge: AnyView(Badge(text: "\(items.count) \(items.count == 1 ? "advisory" : "advisories")", color: Theme.color(for: worst))),
                                    trailing: AnyView(Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.color(for: worst)))
                                )
                                .tag(AuditSelection.advisories(id))
                            }
                        }
                    }
                    if !report.abandoned.isEmpty {
                        Section("Abandoned packages") {
                            ForEach(report.abandoned.keys.sorted { $0.name < $1.name }, id: \.self) { id in
                                PackageRow(
                                    name: id.name,
                                    description: report.abandoned[id]?.flatMap { "Suggested replacement: \($0)" } ?? "No replacement suggested",
                                    version: model.inventory.value?.package(id)?.version,
                                    color: Theme.danger,
                                    badge: AnyView(Badge(text: "abandoned", color: Theme.danger))
                                )
                                .tag(AuditSelection.abandoned(id))
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selected {
        case let .advisories(id):
            if let package = model.inventory.value?.package(id) {
                PackageDetailView(package: package)
            } else {
                advisoriesOnly(id)
            }
        case let .abandoned(id):
            if let package = model.inventory.value?.package(id) {
                PackageDetailView(package: package)
            } else {
                EmptyState(symbol: "shippingbox", title: id.name, message: "Abandoned by its author.")
            }
        case nil:
            EmptyState(symbol: "checkmark.shield", title: "Select a finding", message: "Advisories come from Packagist's security database. Updating the affected package is usually the fix.")
        }
    }

    private func advisoriesOnly(_ id: ComposerPackageID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(id.name).font(.title2.weight(.semibold))
                ForEach(model.advisories(for: id)) { AdvisoryCard(advisory: $0) }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
