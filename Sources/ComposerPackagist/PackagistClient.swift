import ComposerCore
import Foundation

/// Packagist's public JSON API: search and package metadata.
public struct PackagistClient: Sendable {
    public enum ClientError: Error, LocalizedError {
        case badStatus(Int)
        case decoding(String)
        case offline(String)

        public var errorDescription: String? {
            switch self {
            case let .badStatus(code): "Packagist answered with HTTP \(code)."
            case let .decoding(detail): "Packagist returned data the app could not read: \(detail)"
            case let .offline(detail): "Packagist could not be reached: \(detail)"
            }
        }
    }

    public struct SearchPage: Sendable {
        public var results: [DiscoveredPackage]
        public var total: Int
        public var nextPage: Int?
    }

    private let session: URLSession
    private let baseURL = URL(string: "https://packagist.org")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(_ query: String, page: Int = 1, perPage: Int = 30) async throws -> SearchPage {
        var components = URLComponents(url: baseURL.appendingPathComponent("search.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        let data = try await get(components.url!)
        let root: SearchJSON
        do {
            root = try JSONDecoder().decode(SearchJSON.self, from: data)
        } catch {
            throw ClientError.decoding(error.localizedDescription)
        }
        let results = root.results.compactMap { hit -> DiscoveredPackage? in
            guard let name = hit.name, !name.isEmpty else { return nil }
            return DiscoveredPackage(
                id: ComposerPackageID(name),
                description: hit.description ?? "",
                repository: hit.repository.flatMap(URL.init(string:)),
                downloads: hit.downloads ?? 0,
                favers: hit.favers ?? 0,
                isAbandoned: hit.abandoned?.isAbandoned ?? false,
                replacement: hit.abandoned?.replacement
            )
        }
        let next = root.next.flatMap { URLComponents(string: $0)?.queryItems?.first { $0.name == "page" }?.value }.flatMap(Int.init)
        return SearchPage(results: results, total: root.total ?? results.count, nextPage: next)
    }

    public func package(_ id: ComposerPackageID) async throws -> PackagistPackage {
        let url = baseURL.appendingPathComponent("packages/\(id.name).json")
        let data = try await get(url)
        let root: PackageJSON
        do {
            root = try JSONDecoder().decode(PackageJSON.self, from: data)
        } catch {
            throw ClientError.decoding(error.localizedDescription)
        }
        let p = root.package
        let versions = (p.versions ?? [:]).values.compactMap { v -> PackagistPackage.Version? in
            guard let version = v.version else { return nil }
            return PackagistPackage.Version(
                version: version,
                normalized: v.versionNormalized ?? version,
                releasedAt: v.time.flatMap(Self.date),
                license: v.license ?? [],
                requiresPHP: v.require?["php"]
            )
        }
        .sorted { lhs, rhs in
            // Newest first: dev branches last, then by normalized version descending.
            if lhs.isDev != rhs.isDev { return !lhs.isDev }
            return lhs.normalized.compare(rhs.normalized, options: .numeric) == .orderedDescending
        }
        let latest = versions.first(where: \.isStable) ?? versions.first
        let latestRecord = latest.flatMap { l in p.versions?.values.first { $0.version == l.version } }
        return PackagistPackage(
            id: ComposerPackageID(p.name ?? id.name),
            description: p.description ?? "",
            type: p.type ?? latestRecord?.type ?? "library",
            repository: p.repository.flatMap(URL.init(string:)),
            homepage: latestRecord?.homepage.flatMap(URL.init(string:)),
            downloadsTotal: p.downloads?.total ?? 0,
            downloadsMonthly: p.downloads?.monthly ?? 0,
            favers: p.favers ?? 0,
            githubStars: p.githubStars,
            maintainers: (p.maintainers ?? []).compactMap(\.name),
            keywords: latestRecord?.keywords ?? [],
            versions: versions,
            isAbandoned: p.abandoned?.isAbandoned ?? false,
            replacement: p.abandoned?.replacement
        )
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("ComposerUI (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.offline(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.badStatus(http.statusCode)
        }
        return data
    }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func date(_ text: String) -> Date? { formatter.date(from: text) }
}

struct Abandoned: Decodable {
    let isAbandoned: Bool
    let replacement: String?
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let flag = try? c.decode(Bool.self) {
            isAbandoned = flag; replacement = nil
        } else if let name = try? c.decode(String.self) {
            isAbandoned = true; replacement = name.isEmpty ? nil : name
        } else {
            isAbandoned = false; replacement = nil
        }
    }
}

struct SearchJSON: Decodable {
    struct Hit: Decodable {
        var name: String?
        var description: String?
        var url: String?
        var repository: String?
        var downloads: Int?
        var favers: Int?
        var abandoned: Abandoned?
    }
    var results: [Hit]
    var total: Int?
    var next: String?
}

struct PackageJSON: Decodable {
    struct Package: Decodable {
        struct Downloads: Decodable { var total: Int?; var monthly: Int?; var daily: Int? }
        struct Maintainer: Decodable { var name: String? }
        struct Version: Decodable {
            var version: String?
            var versionNormalized: String?
            var time: String?
            var license: [String]?
            var homepage: String?
            var keywords: [String]?
            var type: String?
            var require: [String: String]?
            enum CodingKeys: String, CodingKey {
                case version, time, license, homepage, keywords, type, require
                case versionNormalized = "version_normalized"
            }
        }
        var name: String?
        var description: String?
        var type: String?
        var repository: String?
        var downloads: Downloads?
        var favers: Int?
        var githubStars: Int?
        var maintainers: [Maintainer]?
        var versions: [String: Version]?
        var abandoned: Abandoned?
        enum CodingKeys: String, CodingKey {
            case name, description, type, repository, downloads, favers, maintainers, versions, abandoned
            case githubStars = "github_stars"
        }
    }
    var package: Package
}
