import Foundation

/// Runtime-only authority. Restoring data never revives an old request.
final class AIChatOperationFence: @unchecked Sendable {
    struct Lease: Equatable, Sendable {
        let generation: UUID
        let sessionID: UUID
        let sessionGeneration: UUID
        let bookID: UUID?
    }

    static let shared = AIChatOperationFence()
    private let lock = NSLock()
    private var generation = UUID()
    private var sessions: [UUID: UUID] = [:]

    func capture(sessionID: UUID, bookID: UUID?) -> Lease {
        lock.lock()
        defer { lock.unlock() }
        let sessionGeneration = sessions[sessionID] ?? UUID()
        sessions[sessionID] = sessionGeneration
        return Lease(generation: generation, sessionID: sessionID,
                     sessionGeneration: sessionGeneration, bookID: bookID)
    }

    func isCurrent(_ lease: Lease) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lease.generation == generation &&
            sessions[lease.sessionID] == lease.sessionGeneration
    }

    func invalidate(sessionID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        sessions[sessionID] = UUID()
    }

    func invalidateDatabase() {
        lock.lock()
        defer { lock.unlock() }
        generation = UUID()
        sessions.removeAll()
    }
}

struct AIChatCompletionMetadata: Codable, Equatable {
    let version: Int
    let thinkingSeconds: Int
    let interrupted: Bool

    init(thinkingSeconds: Int, interrupted: Bool) {
        version = 1
        self.thinkingSeconds = max(0, thinkingSeconds)
        self.interrupted = interrupted
    }
}
