import ComposerCLI
import ComposerCore
import Foundation
import Observation

/// Receives job updates from the command centre and keeps the transcript the console shows.
@MainActor
@Observable
public final class ConsoleStore: CommandJobObserver {
    public private(set) var jobs: [CommandJob] = []
    public var selectedJobID: UUID?
    public var isExpanded = false
    /// Follows the newest output unless the user scrolled up.
    public var followsOutput = true
    private let maxJobs = 40

    public init() {}

    nonisolated public func jobDidChange(_ job: CommandJob) async {
        await MainActor.run { apply(job) }
    }

    private func apply(_ job: CommandJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
            if jobs.count > maxJobs { jobs.removeFirst(jobs.count - maxJobs) }
        }
        if job.phase == .running || selectedJobID == nil || !jobs.contains(where: { $0.id == selectedJobID }) {
            selectedJobID = job.id
        }
        if job.command.effect == .mutate, job.phase == .running {
            isExpanded = true
        }
    }

    public var selectedJob: CommandJob? {
        jobs.first { $0.id == selectedJobID } ?? jobs.last
    }

    public var runningJob: CommandJob? { jobs.first { $0.phase == .running } }
    public var queuedCount: Int { jobs.filter { $0.phase == .queued }.count }
    public var isBusy: Bool { runningJob != nil || queuedCount > 0 }

    public func clear() {
        jobs.removeAll { $0.phase.isFinished }
        selectedJobID = jobs.last?.id
    }

    public var statusText: String {
        if let running = runningJob {
            let queued = queuedCount
            return queued > 0 ? "\(running.command.title)… (\(queued) queued)" : "\(running.command.title)…"
        }
        if let last = jobs.last {
            switch last.phase {
            case .succeeded: return "\(last.command.title) finished"
            case let .failed(code): return "\(last.command.title) failed (exit \(code))"
            case .cancelled: return "\(last.command.title) cancelled"
            case let .launchFailed(reason): return reason
            default: break
            }
        }
        return "Ready"
    }
}
