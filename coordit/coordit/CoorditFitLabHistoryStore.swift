import CryptoKit
import Darwin
@preconcurrency import Foundation

#if os(iOS)
protocol CoorditFitLabHistoryStoring: Sendable {
    func load(userID: String) async throws -> [CoorditFitLabHistorySnapshot]
    func save(_ snapshot: CoorditFitLabHistorySnapshot) async throws
    func delete(snapshotID: String, userID: String) async throws
    func deleteAll(userID: String) async throws
    func recoveryNotice(userID: String) async -> String?
}

enum CoorditFitLabHistoryStoreError: LocalizedError, Equatable {
    case invalidUser
    case unsafeStorage
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidUser: "저장할 사용자 정보를 확인할 수 없어요."
        case .unsafeStorage: "안전한 히스토리 저장 공간을 준비하지 못했어요."
        case .writeFailed: "핏 분석 히스토리를 안전하게 저장하지 못했어요."
        }
    }
}

actor CoorditFitLabFileHistoryStore: CoorditFitLabHistoryStoring {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let snapshots: [CoorditFitLabHistorySnapshot]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case snapshots
        }
    }

    private struct EnvelopeHeader: Decodable {
        let schemaVersion: Int

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
        }
    }

    private struct LegacyEnvelope: Decodable {
        struct Snapshot: Decodable {
            let id: String
            let userID: String
            let savedAt: Date
            let recommendation: CoorditFitLabRecommendationResponse
            let report: CoorditFitLabReportResponse?
        }

        let snapshots: [Snapshot]
    }

    private let rootDirectory: URL
    private let manager = FileManager.default
    private var notices: [String: String] = [:]
    private let failMigrationRewrite: Bool

    init(
        rootDirectory: URL? = nil,
        failMigrationRewrite: Bool = false
    ) {
        self.failMigrationRewrite = failMigrationRewrite
        if let rootDirectory {
            self.rootDirectory = rootDirectory.standardizedFileURL
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootDirectory = applicationSupport.appendingPathComponent("CoorditFitLabHistory", isDirectory: true)
        }
    }

    func load(userID: String) throws -> [CoorditFitLabHistorySnapshot] {
        let directory = try validatedDirectory(for: userID)
        let fileURL = directory.appendingPathComponent("history.json", isDirectory: false)
        guard manager.fileExists(atPath: fileURL.path) else {
            notices[userID] = nil
            return []
        }
        try rejectSymbolicLink(at: fileURL)

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let snapshots: [CoorditFitLabHistorySnapshot]
        let needsMigration: Bool
        do {
            let decoder = Self.decoder
            let header = try decoder.decode(EnvelopeHeader.self, from: data)
            switch header.schemaVersion {
            case CoorditFitLabHistorySnapshot.currentSchemaVersion:
                snapshots = try decoder.decode(Envelope.self, from: data).snapshots
                needsMigration = false
            case 1:
                snapshots = try migrate(decoder.decode(LegacyEnvelope.self, from: data), userID: userID)
                needsMigration = true
            default:
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Unsupported history schema")
                )
            }
            guard snapshots.allSatisfy({ $0.userID == userID }) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "History user mismatch")
                )
            }
            notices[userID] = nil
        } catch {
            try quarantine(fileURL, userID: userID)
            return []
        }
        if needsMigration {
            do {
                if failMigrationRewrite { throw CoorditFitLabHistoryStoreError.writeFailed }
                try writeEnvelope(snapshots, userID: userID)
            } catch {
                notices[userID] = "이전 히스토리는 읽었지만 새 형식으로 저장하지 못했어요. 원본은 안전하게 유지했어요."
                return normalized(snapshots)
            }
        }
        return normalized(snapshots)
    }

    func save(_ snapshot: CoorditFitLabHistorySnapshot) throws {
        guard snapshot.schemaVersion == CoorditFitLabHistorySnapshot.currentSchemaVersion else {
            throw CoorditFitLabHistoryStoreError.writeFailed
        }
        var snapshots = try load(userID: snapshot.userID)
        snapshots.removeAll { $0.analysisID == snapshot.analysisID }
        snapshots.append(snapshot)
        try writeEnvelope(normalized(snapshots), userID: snapshot.userID)
        notices[snapshot.userID] = nil
    }

    func delete(snapshotID: String, userID: String) throws {
        try Task.checkCancellation()
        var snapshots = try load(userID: userID)
        snapshots.removeAll { $0.id == snapshotID }
        try Task.checkCancellation()
        try writeEnvelope(snapshots, userID: userID)
    }

    func deleteAll(userID: String) throws {
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoorditFitLabHistoryStoreError.invalidUser
        }
        let directory = rootDirectory
            .appendingPathComponent(Self.safeDirectoryName(userID), isDirectory: true)
            .standardizedFileURL
        let rootPath = rootDirectory.standardizedFileURL.path + "/"
        guard directory.path.hasPrefix(rootPath) else {
            throw CoorditFitLabHistoryStoreError.unsafeStorage
        }
        guard manager.fileExists(atPath: directory.path) else {
            notices[userID] = nil
            return
        }
        try rejectSymbolicLink(at: directory)
        try manager.removeItem(at: directory)
        notices[userID] = nil
    }

    func recoveryNotice(userID: String) async -> String? {
        notices[userID]
    }

    private func normalized(_ snapshots: [CoorditFitLabHistorySnapshot]) -> [CoorditFitLabHistorySnapshot] {
        Array(
            snapshots
                .sorted {
                    if $0.savedAt == $1.savedAt { return $0.analysisID > $1.analysisID }
                    return $0.savedAt > $1.savedAt
                }
                .prefix(50)
        )
    }

    private func migrate(_ envelope: LegacyEnvelope, userID: String) throws -> [CoorditFitLabHistorySnapshot] {
        try envelope.snapshots.map { legacy in
            guard legacy.userID == userID else { throw CoorditFitLabHistoryStoreError.unsafeStorage }
            let garmentKind: CoorditFitLabGarmentKind = legacy.recommendation.diff.keys.contains(where: {
                $0.garmentKind == .lower
            }) ? .lower : .upper
            let category: CoorditFitLabCategory = garmentKind == .lower ? .pants : .tshirt
            return CoorditFitLabHistorySnapshot(
                id: legacy.id,
                analysisID: legacy.recommendation.fitAnalysisResultID,
                userID: userID,
                savedAt: legacy.savedAt,
                product: .init(name: "저장된 상품", brand: nil, mallName: nil, url: nil),
                category: category,
                garmentKind: garmentKind,
                references: [],
                originalSource: .manual,
                recommendation: legacy.recommendation,
                report: legacy.report,
                chartData: legacy.report?.chartData ?? .init()
            )
        }
    }

    private func writeEnvelope(_ snapshots: [CoorditFitLabHistorySnapshot], userID: String) throws {
        let directory = try validatedDirectory(for: userID)
        let destination = directory.appendingPathComponent("history.json", isDirectory: false)
        if manager.fileExists(atPath: destination.path) {
            try rejectSymbolicLink(at: destination)
        }
        let temporary = directory.appendingPathComponent(".history-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        do {
            let data = try Self.encoder.encode(
                Envelope(schemaVersion: CoorditFitLabHistorySnapshot.currentSchemaVersion, snapshots: snapshots)
            )
            try data.write(to: temporary, options: [.atomic])
            try Task.checkCancellation()
            guard Darwin.rename(temporary.path, destination.path) == 0 else {
                throw CoorditFitLabHistoryStoreError.writeFailed
            }
        } catch let error as CoorditFitLabHistoryStoreError {
            throw error
        } catch {
            throw CoorditFitLabHistoryStoreError.writeFailed
        }
    }

    private func validatedDirectory(for userID: String) throws -> URL {
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoorditFitLabHistoryStoreError.invalidUser
        }
        try manager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try rejectSymbolicLink(at: rootDirectory)
        let directory = rootDirectory.appendingPathComponent(Self.safeDirectoryName(userID), isDirectory: true)
        let rootPath = rootDirectory.standardizedFileURL.path + "/"
        guard directory.standardizedFileURL.path.hasPrefix(rootPath) else {
            throw CoorditFitLabHistoryStoreError.unsafeStorage
        }
        if manager.fileExists(atPath: directory.path) {
            try rejectSymbolicLink(at: directory)
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        return directory
    }

    private func rejectSymbolicLink(at url: URL) throws {
        guard manager.fileExists(atPath: url.path) else { return }
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw CoorditFitLabHistoryStoreError.unsafeStorage
        }
    }

    private func quarantine(_ fileURL: URL, userID: String) throws {
        let quarantineURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("history.json.corrupt-\(UUID().uuidString)")
        try manager.moveItem(at: fileURL, to: quarantineURL)
        notices[userID] = "손상된 히스토리를 격리하고 빈 목록으로 복구했어요."
    }

    private nonisolated static func safeDirectoryName(_ userID: String) -> String {
        let normalized = userID.precomposedStringWithCanonicalMapping
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_") )
        let slug = String(normalized.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" })
            .prefix(32)
        let digest = SHA256.hash(data: Data(userID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "user-\(slug)-\(digest)"
    }

    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    #if DEBUG
    func debugReset() throws {
        if manager.fileExists(atPath: rootDirectory.path) {
            try manager.removeItem(at: rootDirectory)
        }
        notices.removeAll()
    }

    func debugCorrupt(userID: String) throws {
        let directory = try validatedDirectory(for: userID)
        try Data("{\"truncated\":".utf8).write(
            to: directory.appendingPathComponent("history.json"),
            options: [.atomic]
        )
    }

    func debugQuarantineCount(userID: String) throws -> Int {
        let directory = try validatedDirectory(for: userID)
        return try manager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("history.json.corrupt-") }
            .count
    }

    func debugAudit(sample: CoorditFitLabHistorySnapshot) async -> String {
        var results: [String: Bool] = [:]

        let traversalUser = "../outside/.."
        do {
            let copied = Self.copy(sample, userID: traversalUser, analysisID: "audit-path")
            try save(copied)
            let directory = try validatedDirectory(for: traversalUser)
            results["path"] = directory.path.hasPrefix(rootDirectory.path + "/") && !directory.lastPathComponent.contains("..")
        } catch { results["path"] = false }

        let symlinkUser = "audit-symlink"
        do {
            let directory = rootDirectory.appendingPathComponent(Self.safeDirectoryName(symlinkUser))
            try? manager.removeItem(at: directory)
            try manager.createSymbolicLink(at: directory, withDestinationURL: rootDirectory)
            do {
                _ = try load(userID: symlinkUser)
                results["symlink"] = false
            } catch {
                results["symlink"] = true
            }
            try? manager.removeItem(at: directory)
        } catch { results["symlink"] = false }

        let atomicUser = "audit-atomic"
        do {
            let directory = try validatedDirectory(for: atomicUser)
            let destination = directory.appendingPathComponent("history.json")
            let sentinel = rootDirectory.appendingPathComponent("audit-atomic-sentinel")
            try Data("unchanged".utf8).write(to: sentinel, options: [.atomic])
            try manager.createSymbolicLink(at: destination, withDestinationURL: sentinel)
            do {
                try save(Self.copy(sample, userID: atomicUser, analysisID: "audit-atomic"))
                results["atomic"] = false
            } catch {
                results["atomic"] = (try? String(contentsOf: sentinel, encoding: .utf8)) == "unchanged"
            }
            try? manager.removeItem(at: destination)
            try? manager.removeItem(at: sentinel)
        } catch { results["atomic"] = false }

        let truncatedUser = "audit-truncated"
        do {
            try debugCorrupt(userID: truncatedUser)
            results["truncated"] = try load(userID: truncatedUser).isEmpty && notices[truncatedUser] != nil
        } catch { results["truncated"] = false }

        let versionUser = "audit-version"
        do {
            let directory = try validatedDirectory(for: versionUser)
            try Data("{\"schema_version\":999,\"snapshots\":[]}".utf8).write(
                to: directory.appendingPathComponent("history.json"),
                options: [.atomic]
            )
            results["version"] = try load(userID: versionUser).isEmpty && notices[versionUser] != nil
        } catch { results["version"] = false }

        let migrationUser = "audit-migration"
        do {
            let directory = try validatedDirectory(for: migrationUser)
            let legacyFixture = Data(
                #"{"schema_version":1,"snapshots":[{"id":"legacy-id","userID":"audit-migration","savedAt":"2025-01-02T03:04:05Z","recommendation":{"fitAnalysisResultId":"legacy-analysis","recommendedSize":"M","fitScore":91,"fitLabel":"good_fit","fitComment":"legacy","recommendationConfidence":"high","diff":{"shoulder_width":1}},"report":null}]}"#.utf8
            )
            let fileURL = directory.appendingPathComponent("history.json")
            try legacyFixture.write(to: fileURL, options: [.atomic])
            let migrated = try load(userID: migrationUser)
            let rewrittenHeader = try Self.decoder.decode(
                EnvelopeHeader.self,
                from: Data(contentsOf: fileURL)
            )
            results["migration"] = migrated.count == 1
                && migrated.first?.schemaVersion == CoorditFitLabHistorySnapshot.currentSchemaVersion
                && migrated.first?.analysisID == "legacy-analysis"
                && migrated.first?.userID == migrationUser
                && rewrittenHeader.schemaVersion == CoorditFitLabHistorySnapshot.currentSchemaVersion
        } catch { results["migration"] = false }

        let interruptUser = "audit-interrupt"
        do {
            let directory = try validatedDirectory(for: interruptUser)
            try Data("partial".utf8).write(to: directory.appendingPathComponent(".history-interrupted.tmp"))
            results["interrupt"] = try load(userID: interruptUser).isEmpty
        } catch { results["interrupt"] = false }

        return ["path", "symlink", "atomic", "truncated", "version", "migration", "interrupt"]
            .map { "\($0)=\(results[$0] == true ? "pass" : "fail")" }
            .joined(separator: "|")
    }

    func debugMigrationRewriteFailureAudit() async -> String {
        let auditRoot = rootDirectory.appendingPathComponent("migration-write-failure", isDirectory: true)
        try? manager.removeItem(at: auditRoot)
        defer { try? manager.removeItem(at: auditRoot) }
        let store = await CoorditFitLabFileHistoryStore(rootDirectory: auditRoot, failMigrationRewrite: true)
        let userID = "audit-migration-write"
        do {
            let directory = try await store.validatedDirectory(for: userID)
            let legacy = Data(
                #"{"schema_version":1,"snapshots":[{"id":"legacy-id","userID":"audit-migration-write","savedAt":"2025-01-02T03:04:05Z","recommendation":{"fitAnalysisResultId":"legacy-analysis","recommendedSize":"M","fitScore":91,"fitLabel":"good_fit","fitComment":"legacy","recommendationConfidence":"high","diff":{"shoulder_width":1}},"report":null}]}"#.utf8
            )
            let fileURL = directory.appendingPathComponent("history.json")
            try legacy.write(to: fileURL, options: [.atomic])
            let loaded = try await store.load(userID: userID)
            let retained = try Data(contentsOf: fileURL) == legacy
            let quarantines = try manager.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix("history.json.corrupt-") }
            let notice = await store.recoveryNotice(userID: userID)
            return "loaded=\(loaded.count)|analysis=\(loaded.first?.analysisID ?? "nil")|retained=\(retained)|quarantine=\(quarantines.count)|notice=\(notice == nil ? "nil" : "present")"
        } catch {
            return "error=\(error.localizedDescription)"
        }
    }

    private nonisolated static func copy(
        _ snapshot: CoorditFitLabHistorySnapshot,
        userID: String,
        analysisID: String
    ) -> CoorditFitLabHistorySnapshot {
        CoorditFitLabHistorySnapshot(
            id: analysisID,
            analysisID: analysisID,
            userID: userID,
            savedAt: snapshot.savedAt,
            product: snapshot.product,
            category: snapshot.category,
            garmentKind: snapshot.garmentKind,
            references: snapshot.references,
            originalSource: snapshot.originalSource,
            recommendation: snapshot.recommendation,
            report: snapshot.report,
            chartData: snapshot.chartData
        )
    }
    #endif
}

extension CoorditFitLabHistoryStoring {
    func deleteAll(userID: String) async throws {}
    func recoveryNotice(userID: String) async -> String? { nil }
}
#endif
