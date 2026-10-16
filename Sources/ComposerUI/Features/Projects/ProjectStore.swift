import AppKit
import ComposerCore
import Foundation
import Observation

/// The open project and the recent-projects list, persisted in UserDefaults.
@MainActor
@Observable
public final class ProjectStore {
    public private(set) var recents: [ComposerProject] = []
    public var current: ComposerProject? {
        didSet { persist() }
    }
    public let global: ComposerProject

    private let defaults: UserDefaults
    private let recentsKey = "composerui.recentProjects"
    private let currentKey = "composerui.currentProject"

    public init(globalHome: URL, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        global = .global(home: globalHome)
        load()
    }

    private func load() {
        if let data = defaults.data(forKey: recentsKey),
           let list = try? JSONDecoder().decode([ComposerProject].self, from: data) {
            recents = list.filter { FileManager.default.fileExists(atPath: $0.composerJSONURL.path) }
        }
        if let data = defaults.data(forKey: currentKey),
           let saved = try? JSONDecoder().decode(ComposerProject.self, from: data) {
            if saved.isGlobal {
                current = global
            } else if FileManager.default.fileExists(atPath: saved.composerJSONURL.path) {
                current = saved
            }
        }
        if current == nil { current = recents.first ?? global }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: recentsKey) }
        if let current, let data = try? JSONEncoder().encode(current) { defaults.set(data, forKey: currentKey) }
    }

    public enum OpenError: LocalizedError {
        case noComposerJSON(URL)
        public var errorDescription: String? {
            switch self {
            case let .noComposerJSON(url):
                "\(url.lastPathComponent) has no composer.json. Choose a folder that contains one."
            }
        }
    }

    @discardableResult
    public func open(folder url: URL) throws -> ComposerProject {
        let project = ComposerProject.project(at: url)
        guard FileManager.default.fileExists(atPath: project.composerJSONURL.path) else {
            throw OpenError.noComposerJSON(url)
        }
        recents.removeAll { $0.id == project.id }
        recents.insert(project, at: 0)
        if recents.count > 12 { recents.removeLast(recents.count - 12) }
        current = project
        return project
    }

    public func forget(_ project: ComposerProject) {
        recents.removeAll { $0.id == project.id }
        if current?.id == project.id { current = recents.first ?? global }
        persist()
    }

    /// Shows the standard open panel and opens the chosen folder.
    public func presentOpenPanel() async -> Result<ComposerProject, any Error>? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .folder]
        panel.message = "Choose a project folder or its composer.json"
        panel.prompt = "Open Project"
        guard panel.runModal() == .OK, var url = panel.url else { return nil }
        if url.lastPathComponent == "composer.json" { url = url.deletingLastPathComponent() }
        do {
            return .success(try open(folder: url))
        } catch {
            return .failure(error)
        }
    }
}
