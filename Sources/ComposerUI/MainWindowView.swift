import ComposerCore
import SwiftUI

/// The window: sidebar, the selected feature, and the console along the bottom.
public struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                feature
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ConsoleView()
            }
        }
        .navigationTitle(model.project.isGlobal ? "ComposerUI" : model.project.displayName)
        .navigationSubtitle(model.project.isGlobal ? "Global packages" : model.project.rootURL.path(percentEncoded: false))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ProjectMenu()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.refreshProject() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.console.isBusy)
                .keyboardShortcut("r", modifiers: .command)
                .help("Re-read installed packages, updates and audit (⌘R)")
            }
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .frame(minWidth: 1040, minHeight: 640)
        .onAppear { model.start() }
    }

    @ViewBuilder
    private var feature: some View {
        switch model.sidebar {
        case .installed: InstalledView()
        case .updates: UpdatesView()
        case .discover: DiscoverView()
        case .audit: AuditView()
        case .scripts: ScriptsView()
        case .configuration: ConfigurationView()
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    Label {
                        HStack {
                            Text(item.title)
                            Spacer()
                            badge(for: item)
                        }
                    } icon: {
                        Image(systemName: item.symbol)
                    }
                    .tag(item)
                }
            }
            Section("Projects") {
                projectRow(model.projects.global)
                ForEach(model.projects.recents) { project in
                    projectRow(project)
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.rootURL]) }
                            Button("Remove from Recents") { model.projects.forget(project); if model.projects.current?.id != project.id { } else { model.select(project: model.projects.current ?? model.projects.global) } }
                        }
                }
                Button {
                    model.openProjectFromPanel()
                } label: {
                    Label("Open Project…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .listStyle(.sidebar)
    }

    private func projectRow(_ project: ComposerProject) -> some View {
        Button {
            model.select(project: project)
        } label: {
            HStack {
                Image(systemName: project.isGlobal ? "globe" : "folder")
                    .foregroundStyle(model.project.id == project.id ? Color.accentColor : .secondary)
                Text(project.displayName)
                    .fontWeight(model.project.id == project.id ? .semibold : .regular)
                Spacer()
                if model.project.id == project.id { Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(.plain)
        .help(project.rootURL.path)
    }

    @ViewBuilder
    private func badge(for item: SidebarItem) -> some View {
        switch item {
        case .updates where model.updateCount > 0:
            countBadge(model.updateCount, color: .blue)
        case .audit where model.auditIssueCount > 0:
            countBadge(model.auditIssueCount, color: .red)
        default:
            EmptyView()
        }
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }
}

struct ProjectMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button {
                model.select(project: model.projects.global)
            } label: {
                Label("Global", systemImage: "globe")
            }
            if !model.projects.recents.isEmpty { Divider() }
            ForEach(model.projects.recents) { project in
                Button {
                    model.select(project: project)
                } label: {
                    Label(project.displayName, systemImage: "folder")
                }
            }
            Divider()
            Button("Open Project…") { model.openProjectFromPanel() }
        } label: {
            Label(model.project.displayName, systemImage: model.project.isGlobal ? "globe" : "folder")
        }
        .help("Switch project")
    }
}
