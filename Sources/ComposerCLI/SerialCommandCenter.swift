import ComposerCore
import Foundation

/// Observers of command progress. The console implements this on the main actor.
public protocol CommandJobObserver: AnyObject, Sendable {
    func jobDidChange(_ job: CommandJob) async
}

/// Runs Composer commands one after another so two mutations never race on `vendor`, coalesces
/// duplicate operation IDs and publishes every job's phase and output to the observer.
public actor SerialCommandCenter: CommandCenter {
    private let locator: any ComposerExecutableLocating
    private weak var observer: (any CommandJobObserver)?
    private var queue: [QueuedJob] = []
    private var running: RunningJob?
    private var isDraining = false

    private struct QueuedJob {
        var job: CommandJob
        var waiters: [CheckedContinuation<CommandResult, any Error>]
    }

    private struct RunningJob {
        var job: CommandJob
        let process: Process
        var waiters: [CheckedContinuation<CommandResult, any Error>]
        var cancelled = false
    }

    public init(locator: any ComposerExecutableLocating) {
        self.locator = locator
    }

    public func setObserver(_ observer: any CommandJobObserver) {
        self.observer = observer
    }

    public func run(_ command: ComposerCommand) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            if let index = queue.firstIndex(where: { $0.job.command.operationID == command.operationID }) {
                queue[index].waiters.append(continuation)
                return
            }
            if var current = running, current.job.command.operationID == command.operationID, !current.cancelled {
                current.waiters.append(continuation)
                running = current
                return
            }
            let job = CommandJob(command: command)
            queue.append(QueuedJob(job: job, waiters: [continuation]))
            Task { await observer?.jobDidChange(job) }
            Task { await drain() }
        }
    }

    public func cancel(jobID: UUID) async {
        if let index = queue.firstIndex(where: { $0.job.id == jobID }) {
            var entry = queue.remove(at: index)
            entry.job.phase = .cancelled
            entry.job.finishedAt = .now
            await observer?.jobDidChange(entry.job)
            for waiter in entry.waiters { waiter.resume(throwing: CommandError.cancelled) }
            return
        }
        if var current = running, current.job.id == jobID {
            current.cancelled = true
            running = current
            // Terminate the whole process group so child processes (git, scripts) go too.
            let pid = current.process.processIdentifier
            if pid > 0 {
                kill(-pid, SIGTERM)
                current.process.terminate()
            }
        }
    }

    private func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while running == nil, !queue.isEmpty {
            let entry = queue.removeFirst()
            await execute(entry)
        }
    }

    private func execute(_ entry: QueuedJob) async {
        var job = entry.job
        let toolchain: ComposerToolchain
        switch locator.locate() {
        case let .success(found):
            toolchain = found
        case let .failure(error):
            job.phase = .launchFailed(error.localizedDescription)
            job.finishedAt = .now
            await observer?.jobDidChange(job)
            for waiter in entry.waiters { waiter.resume(throwing: error) }
            return
        }

        let runner = ProcessRunner(toolchain: toolchain)
        let launch: ProcessRunner.Launch
        do {
            launch = try runner.launch(job.command)
        } catch {
            let message = (error as? CommandError)?.localizedDescription ?? error.localizedDescription
            job.phase = .launchFailed(message)
            job.finishedAt = .now
            await observer?.jobDidChange(job)
            for waiter in entry.waiters { waiter.resume(throwing: error) }
            return
        }

        job.phase = .running
        job.startedAt = .now
        job.output.append(CommandOutputLine(id: 0, stream: .system, text: "$ \(job.command.terminalText)"))
        running = RunningJob(job: job, process: launch.process, waiters: entry.waiters)
        await observer?.jobDidChange(job)

        var pending: [CommandOutputLine] = []
        var lastFlush = ContinuousClock.now
        for await line in launch.lines {
            pending.append(line)
            if ContinuousClock.now - lastFlush > .milliseconds(60) || pending.count > 200 {
                appendOutput(pending)
                pending.removeAll(keepingCapacity: true)
                lastFlush = .now
                if let current = running { await observer?.jobDidChange(current.job) }
            }
        }
        if !pending.isEmpty { appendOutput(pending) }

        launch.process.waitUntilExit()
        guard var finished = running else { return }
        running = nil
        finished.job.finishedAt = .now
        if finished.cancelled {
            finished.job.phase = .cancelled
        } else if launch.process.terminationReason == .exit, launch.process.terminationStatus == 0 {
            finished.job.phase = .succeeded
        } else if launch.process.terminationReason == .uncaughtSignal {
            finished.job.phase = .cancelled
        } else if finished.job.command.effect == .read, !finished.job.stdout.isEmpty {
            // `composer audit` and `composer outdated` exit non-zero to signal findings while still
            // printing a valid report. The read succeeded; note the code in the transcript.
            finished.job.phase = .succeeded
            finished.job.output.append(CommandOutputLine(id: Int.max, stream: .system, text: "(exit code \(launch.process.terminationStatus): findings reported)"))
        } else {
            finished.job.phase = .failed(exitCode: launch.process.terminationStatus)
        }
        await observer?.jobDidChange(finished.job)

        let result = CommandResult(job: finished.job)
        for waiter in finished.waiters {
            switch finished.job.phase {
            case .succeeded:
                waiter.resume(returning: result)
            case .cancelled:
                waiter.resume(throwing: CommandError.cancelled)
            case let .failed(code):
                // `composer audit` and `composer outdated` use non-zero exit codes to signal findings
                // while still printing valid JSON; callers decide, so hand them the output.
                if finished.job.command.effect == .read, !finished.job.stdout.isEmpty {
                    waiter.resume(returning: result)
                } else {
                    waiter.resume(throwing: CommandError.failed(exitCode: code, stderr: finished.job.stderr, stdout: finished.job.stdout))
                }
            default:
                waiter.resume(throwing: CommandError.failed(exitCode: -1, stderr: finished.job.stderr, stdout: finished.job.stdout))
            }
        }
    }

    private func appendOutput(_ lines: [CommandOutputLine]) {
        guard var current = running else { return }
        current.job.output.append(contentsOf: lines)
        running = current
    }
}
