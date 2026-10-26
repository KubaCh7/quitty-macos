import AppKit

/// Checks GitHub Releases for a newer Quitty and installs it in place.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: String
        let notes: String
        let downloadURL: URL
        let pageURL: URL
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case installing
        case failed(String)
    }

    /// The newest release, when it is newer than the running app.
    @Published private(set) var release: Release?
    @Published private(set) var status: Status = .idle

    /// Called when a check finds a release the user should be told about.
    var onUpdateFound: ((Release) -> Void)?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private let settings = Settings.shared
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/KubaCh7/quitty-macos/releases/latest")!
    private static let assetName = "Quitty.zip"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Checks shortly after launch, then once a day while automatic checks are on.
    func startAutomaticChecks() {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            while true {
                let due = settings.lastUpdateCheck.map { Date().timeIntervalSince($0) >= Self.checkInterval } ?? true
                if settings.autoCheckForUpdates && due {
                    await check(userInitiated: false)
                }
                try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)
            }
        }
    }

    func check(userInitiated: Bool) async {
        guard status != .checking, status != .installing else { return }
        status = .checking
        do {
            let latest = try await fetchLatestRelease()
            settings.lastUpdateCheck = Date()
            if Self.isVersion(latest.version, newerThan: currentVersion) {
                release = latest
                status = .idle
                if userInitiated || settings.skippedVersion != latest.version {
                    onUpdateFound?(latest)
                }
            } else {
                release = nil
                status = .upToDate
            }
        } catch {
            status = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    func skip(_ release: Release) {
        settings.skippedVersion = release.version
    }

    /// Downloads the release, swaps it in for the running app and relaunches.
    func install(_ release: Release) async {
        guard status != .installing else { return }
        status = .installing
        do {
            let newApp = try await downloadAndExtract(release)
            try replaceRunningApp(with: newApp)
            Relauncher.relaunch(at: Bundle.main.bundleURL)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - GitHub

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }

        let tagName: String
        let body: String?
        let htmlUrl: URL
        let assets: [Asset]
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Quitty/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let github = try decoder.decode(GitHubRelease.self, from: data)
        guard let asset = github.assets.first(where: { $0.name == Self.assetName }) else {
            throw UpdateError.missingDownload
        }
        let version = github.tagName.hasPrefix("v") ? String(github.tagName.dropFirst()) : github.tagName
        return Release(version: version, notes: github.body ?? "", downloadURL: asset.browserDownloadUrl, pageURL: github.htmlUrl)
    }

    private static func checkResponse(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.badResponse(http.statusCode)
        }
    }

    /// Compares dotted version numbers, e.g. "1.10.0" > "1.9.2".
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y {
                return x > y
            }
        }
        return false
    }

    // MARK: - Installing

    private func downloadAndExtract(_ release: Release) async throws -> URL {
        var request = URLRequest(url: release.downloadURL)
        request.setValue("Quitty/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (downloaded, response) = try await URLSession.shared.download(for: request)
        try Self.checkResponse(response)

        // Unpack next to the installed app so the swap stays on one volume.
        let fileManager = FileManager.default
        let workDir: URL
        do {
            workDir = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: Bundle.main.bundleURL, create: true)
        } catch {
            throw UpdateError.notWritable
        }
        let zip = workDir.appendingPathComponent(Self.assetName)
        try fileManager.moveItem(at: downloaded, to: zip)
        try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, workDir.path])

        let newApp = workDir.appendingPathComponent("Quitty.app")
        guard let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.invalidDownload
        }
        try? await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        return newApp
    }

    private func replaceRunningApp(with newApp: URL) throws {
        let current = Bundle.main.bundleURL
        if current.path.contains("/AppTranslocation/") {
            throw UpdateError.translocated
        }
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
        } catch {
            throw UpdateError.notWritable
        }
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.invalidDownload)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case missingDownload
    case invalidDownload
    case notWritable
    case translocated

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "GitHub returned an error (HTTP \(code)). Try again later."
        case .missingDownload:
            return "The latest release doesn't include Quitty.zip."
        case .invalidDownload:
            return "The downloaded update isn't a valid copy of Quitty."
        case .notWritable:
            return "Quitty can't replace itself. Move Quitty to your Applications folder and try again."
        case .translocated:
            return "macOS is running Quitty from a temporary location. Move Quitty to your Applications folder, open it from there and try again."
        }
    }
}
