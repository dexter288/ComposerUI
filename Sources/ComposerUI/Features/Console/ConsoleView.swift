import ComposerCore
import SwiftUI

/// The bottom panel: a status bar that expands into the transcript of the selected job.
struct ConsoleView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("console.height") private var height: Double = 220

    var body: some View {
        @Bindable var console = model.console
        VStack(spacing: 0) {
            Divider()
            statusBar
            if console.isExpanded {
                Divider()
                transcript
                    .frame(height: height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBar: some View {
        @Bindable var console = model.console
        return HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(console.statusText).font(.callout).lineLimit(1)
            if let job = console.runningJob {
                Button("Cancel") { model.cancel(jobID: job.id) }.controlSize(.small)
            }
            Spacer()
            if !console.jobs.isEmpty {
                Picker("Job", selection: $console.selectedJobID) {
                    ForEach(console.jobs.reversed()) { job in
                        Text("\(phaseSymbol(job.phase)) \(job.command.title)").tag(Optional(job.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
                .controlSize(.small)
                Button("Clear") { console.clear() }.controlSize(.small).disabled(console.isBusy && console.jobs.count <= 1)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { console.isExpanded.toggle() }
            } label: {
                Image(systemName: console.isExpanded ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("`", modifiers: .command)
            .help(console.isExpanded ? "Hide console (⌘`)" : "Show console (⌘`)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var statusColor: Color {
        let console = model.console
        if console.runningJob != nil { return .blue }
        switch console.jobs.last?.phase {
        case .failed, .launchFailed: return .red
        case .cancelled: return .orange
        default: return .secondary.opacity(0.6)
        }
    }

    private func phaseSymbol(_ phase: CommandPhase) -> String {
        switch phase {
        case .queued: "◌"
        case .running: "●"
        case .succeeded: "✓"
        case .failed, .launchFailed: "✗"
        case .cancelled: "–"
        }
    }

    @ViewBuilder
    private var transcript: some View {
        let console = model.console
        if let job = console.selectedJob {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(job.output) { line in
                            Text(line.text)
                                .font(.callout.monospaced())
                                .foregroundStyle(color(for: line.stream))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                        footer(job).id("footer")
                    }
                    .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: job.output.count) {
                    if console.followsOutput { proxy.scrollTo("footer", anchor: .bottom) }
                }
                .onChange(of: job.id) { proxy.scrollTo("footer", anchor: .bottom) }
            }
        } else {
            Text("Commands you run appear here with their full output.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func footer(_ job: CommandJob) -> some View {
        switch job.phase {
        case .succeeded:
            Text("Finished\(duration(job))").font(.caption).foregroundStyle(.green).padding(.top, 4)
        case let .failed(code):
            Text("Exited with code \(code)\(duration(job))").font(.caption).foregroundStyle(.red).padding(.top, 4)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(.orange).padding(.top, 4)
        case let .launchFailed(reason):
            Text(reason).font(.caption).foregroundStyle(.red).padding(.top, 4)
        case .running:
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Running…").font(.caption).foregroundStyle(.secondary) }.padding(.top, 4)
        case .queued:
            Text("Queued").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private func duration(_ job: CommandJob) -> String {
        guard let start = job.startedAt, let end = job.finishedAt else { return "" }
        let seconds = end.timeIntervalSince(start)
        return seconds < 1 ? "" : " in \(seconds.formatted(.number.precision(.fractionLength(1))))s"
    }

    private func color(for stream: CommandOutputLine.Stream) -> Color {
        switch stream {
        case .stdout: .primary
        case .stderr: .secondary
        case .system: .blue
        }
    }
}
