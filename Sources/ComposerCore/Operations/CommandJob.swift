import Foundation

/// One line of process output, tagged by stream.
public struct CommandOutputLine: Identifiable, Hashable, Sendable {
    public enum Stream: Sendable { case stdout, stderr, system }

    public let id: Int
    public let stream: Stream
    public let text: String

    public init(id: Int, stream: Stream, text: String) {
        self.id = id
        self.stream = stream
        self.text = text
    }
}

public enum CommandPhase: Hashable, Sendable {
    case queued
    case running
    case succeeded
    case failed(exitCode: Int32)
    case cancelled
    case launchFailed(String)

    public var isFinished: Bool {
        switch self {
        case .queued, .running: false
        default: true
        }
    }

    public var isSuccess: Bool { self == .succeeded }
}

/// The observable record of a command the centre has accepted.
public struct CommandJob: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let command: ComposerCommand
    public var phase: CommandPhase
    public var output: [CommandOutputLine]
    public let enqueuedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(id: UUID = UUID(), command: ComposerCommand, phase: CommandPhase = .queued, output: [CommandOutputLine] = [], enqueuedAt: Date = .now) {
        self.id = id
        self.command = command
        self.phase = phase
        self.output = output
        self.enqueuedAt = enqueuedAt
    }

    public var stdout: String {
        output.filter { $0.stream == .stdout }.map(\.text).joined(separator: "\n")
    }

    public var stderr: String {
        output.filter { $0.stream == .stderr }.map(\.text).joined(separator: "\n")
    }

    public var transcript: String {
        output.map(\.text).joined(separator: "\n")
    }
}

public struct CommandResult: Sendable {
    public let job: CommandJob
    public init(job: CommandJob) { self.job = job }
    public var stdout: String { job.stdout }
    public var stderr: String { job.stderr }
    public var isSuccess: Bool { job.phase.isSuccess }
}

public enum CommandError: Error, LocalizedError, Sendable, Hashable {
    case composerNotFound
    case phpNotFound
    case launchFailed(String)
    case failed(exitCode: Int32, stderr: String, stdout: String)
    case cancelled
    case malformedOutput(String)

    public var errorDescription: String? {
        switch self {
        case .composerNotFound:
            return "Composer was not found. Install it from getcomposer.org or set its path in Configuration."
        case .phpNotFound:
            return "PHP was not found. Composer needs a PHP interpreter; install one (Homebrew, Herd or MAMP) or set its path in Configuration."
        case let .launchFailed(reason):
            return "Composer could not be launched: \(reason)"
        case let .failed(code, stderr, stdout):
            let text = stderr.isEmpty ? stdout : stderr
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Composer exited with code \(code)." : trimmed
        case .cancelled:
            return "The command was cancelled."
        case let .malformedOutput(detail):
            return "Composer returned output the app could not read: \(detail)"
        }
    }
}

/// Executes Composer commands one at a time and publishes their progress.
public protocol CommandCenter: Sendable {
    /// Runs the command and waits for it. Throws `CommandError` when it fails.
    func run(_ command: ComposerCommand) async throws -> CommandResult
    /// Cancels the running or queued job with this ID.
    func cancel(jobID: UUID) async
}
