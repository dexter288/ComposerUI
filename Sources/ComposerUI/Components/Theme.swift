import ComposerCore
import SwiftUI

enum Theme {
    static let production = Color(red: 0.95, green: 0.55, blue: 0.10)
    static let development = Color(red: 0.55, green: 0.40, blue: 0.90)
    static let transitive = Color(nsColor: .tertiaryLabelColor)
    static let danger = Color.red
    static let success = Color.green
    static let discover = Color(red: 0.20, green: 0.55, blue: 0.95)

    static func color(for scope: InstalledPackage.Scope) -> Color {
        switch scope {
        case .production: production
        case .development: development
        case .transitive: transitive
        }
    }

    static func color(for severity: SecurityAdvisory.Severity) -> Color {
        switch severity {
        case .critical: .purple
        case .high: .red
        case .medium: .orange
        case .low: .yellow
        case .unknown: .gray
        }
    }
}

enum Format {
    static func compact(_ number: Int) -> String {
        number.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func relative(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.relative(presentation: .named))
    }

    static func short(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Small uppercase pill, like BrewUI's FORMULA / CASK tags.
struct Badge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.4)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color.opacity(0.7), lineWidth: 1))
    }
}

struct ScopeBadge: View {
    var scope: InstalledPackage.Scope
    var body: some View {
        Badge(text: label, color: Theme.color(for: scope))
    }
    private var label: String {
        switch scope {
        case .production: "require"
        case .development: "dev"
        case .transitive: "transitive"
        }
    }
}

/// Circular icon with a tinted ring, keyed by scope or feature.
struct PackageIcon: View {
    var color: Color
    var symbol: String = "shippingbox.fill"
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: 1.5)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

struct DetailRow: View {
    var label: String
    var value: String
    var monospaced = false

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value)
                .font(monospaced ? .body.monospaced() : .body.weight(.medium))
                .textSelection(.enabled)
        }
    }
}

struct LinkRow: View {
    var label: String
    var url: URL
    var title: String? = nil

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Link(destination: url) {
                HStack(spacing: 3) {
                    Text(title ?? url.host() ?? url.absoluteString)
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
            }
        }
    }
}

struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }
}

/// The copyable Terminal command shown before every mutating action.
struct TerminalCommandView: View {
    var command: ComposerCommand
    var explanation: String
    var workingDirectory: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Terminal command", systemImage: "apple.terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
            Text(command.terminalText)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }

    private var fullText: String {
        if let workingDirectory { return "cd \(ComposerCommandQuote.quote(workingDirectory)) && \(command.terminalText)" }
        return command.terminalText
    }
}

enum ComposerCommandQuote {
    static func quote(_ text: String) -> String {
        text.contains(" ") || text.contains("'") ? "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" : text
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
    }
}

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).textSelection(.enabled)
            Spacer()
            if let retry { Button("Retry", action: retry).controlSize(.small) }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Column header used by every feature: title, subtitle, optional count.
struct FeatureHeader: View {
    var item: SidebarItem
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.title3.weight(.semibold))
            Text(item.subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

/// Generic list/detail split used inside the content column.
struct ListDetailLayout<List: View, Detail: View>: View {
    var listWidth: ClosedRange<CGFloat> = 380...560
    @ViewBuilder var list: () -> List
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HSplitView {
            list()
                .frame(minWidth: listWidth.lowerBound, idealWidth: 440, maxWidth: listWidth.upperBound, maxHeight: .infinity)
            detail()
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PackageRow: View {
    var name: String
    var description: String
    var version: String?
    var color: Color
    var badge: AnyView?
    var trailing: AnyView?
    var abandoned = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PackageIcon(color: color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(name).font(.body.weight(.medium)).lineLimit(1)
                    badge
                    if abandoned { Badge(text: "abandoned", color: Theme.danger) }
                }
                if !description.isEmpty {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if let version {
                    Text(version).font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 6)
    }
}
