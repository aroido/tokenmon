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

    @Test
    func shellLookupReturnsAbsolutePathOnSuccess() {
        let result = TokenmonProviderDiscovery.runShellLookup(
            shell: "/bin/sh",
            args: ["-c", "echo /usr/bin/true"],
            terminateAfter: 2.0,
            killAfter: 2.5
        )
        #expect(result == "/usr/bin/true")
    }

    @Test
    func shellLookupTerminatesBlockingSubprocess() {
        let start = Date()
        let result = TokenmonProviderDiscovery.runShellLookup(
            shell: "/bin/sh",
            args: ["-c", "sleep 30; echo /never/printed"],
            terminateAfter: 0.3,
            killAfter: 0.6
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(result == nil)
        #expect(elapsed < 3.0)
    }

    @Test
    func shellLookupSurvivesLargeOutputWithoutDeadlock() {
        // Emit ~200KB of noise (well past the 64KB pipe buffer) before the
        // path line to ensure the async drain prevents deadlock.
        let result = TokenmonProviderDiscovery.runShellLookup(
            shell: "/bin/sh",
            args: ["-c", "yes banner | head -c 204800; echo; echo /usr/bin/true"],
            terminateAfter: 5.0,
            killAfter: 5.5
        )
        #expect(result == "/usr/bin/true")
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
