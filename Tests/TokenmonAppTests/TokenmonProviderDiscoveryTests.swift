import Foundation
import Testing
@testable import TokenmonApp

struct TokenmonProviderDiscoveryTests {
    @Test
    func candidateExecutablePathsIncludesMiseAndAsdfShims() throws {
        let home = try makeTempHome()
        let candidates = TokenmonProviderDiscovery.candidateExecutablePaths(named: "codex", home: home)

        #expect(candidates.contains(home.appendingPathComponent(".local/share/mise/shims/codex").path))
        #expect(candidates.contains(home.appendingPathComponent(".asdf/shims/codex").path))
        #expect(candidates.contains(home.appendingPathComponent(".volta/bin/codex").path))
        #expect(candidates.contains(home.appendingPathComponent(".bun/bin/codex").path))
        #expect(candidates.contains(home.appendingPathComponent("Library/pnpm/codex").path))
    }

    @Test
    func miseNodeBinDirectoriesEnumeratesInstalledVersions() throws {
        let home = try makeTempHome()
        let installsRoot = home.appendingPathComponent(".local/share/mise/installs/node", isDirectory: true)
        let versionA = installsRoot.appendingPathComponent("20.10.0/bin", isDirectory: true)
        let versionB = installsRoot.appendingPathComponent("24.12.0/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: versionA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: versionB, withIntermediateDirectories: true)

        let dirs = TokenmonProviderDiscovery.miseNodeBinDirectories(home: home)

        #expect(dirs.contains(versionA.path))
        #expect(dirs.contains(versionB.path))
    }

    @Test
    func miseNodeBinDirectoriesReturnsEmptyWhenInstallsRootMissing() throws {
        let home = try makeTempHome()
        let dirs = TokenmonProviderDiscovery.miseNodeBinDirectories(home: home)
        #expect(dirs.isEmpty)
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
