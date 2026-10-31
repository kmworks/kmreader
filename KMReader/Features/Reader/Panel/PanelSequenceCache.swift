//
// PanelSequenceCache.swift
//
//

import Foundation

/// Module-owned, in-memory cache of detected `PanelSequence`s, keyed by a
/// `PanelCacheKey.fingerprint` string. Bounded by a TTL and a max-entry budget.
/// Separate from the page-image cache; never on `KomgaBook`; not persisted.
actor PanelSequenceCache {
    private struct Entry {
        let sequence: PanelSequence
        let insertedAt: Date
    }

    private let ttl: TimeInterval
    private let maxEntries: Int
    private var entries: [String: Entry] = [:]

    init(ttl: TimeInterval = 600, maxEntries: Int = 64) {
        self.ttl = ttl
        self.maxEntries = maxEntries
    }

    /// Fresh cached sequence, or `nil` on miss / expiry.
    func sequence(for fingerprint: String, now: Date = Date()) -> PanelSequence? {
        guard let entry = entries[fingerprint] else { return nil }
        guard now.timeIntervalSince(entry.insertedAt) < ttl else {
            entries[fingerprint] = nil
            return nil
        }
        return entry.sequence
    }

    /// Store a sequence. The degenerate `panels([])` (no interior panels) collapses to
    /// `.empty`, so a "no panels" page is represented one way.
    func store(_ sequence: PanelSequence, for fingerprint: String, now: Date = Date()) {
        entries[fingerprint] = Entry(sequence: Self.coalesced(sequence), insertedAt: now)
        evictIfNeeded(now: now)
    }

    func removeAll() {
        entries.removeAll()
    }

    // MARK: - Private

    private static func coalesced(_ sequence: PanelSequence) -> PanelSequence {
        if case .panels(let rects) = sequence, rects.isEmpty {
            return .empty
        }
        return sequence
    }

    /// Drop expired entries, then evict oldest-first until within the entry budget.
    private func evictIfNeeded(now: Date) {
        guard entries.count > maxEntries else { return }

        for (fingerprint, entry) in entries where now.timeIntervalSince(entry.insertedAt) >= ttl {
            entries[fingerprint] = nil
        }
        guard entries.count > maxEntries else { return }

        let overflow = entries.count - maxEntries
        let oldest = entries
            .sorted { $0.value.insertedAt < $1.value.insertedAt }
            .prefix(overflow)
            .map(\.key)
        for fingerprint in oldest {
            entries[fingerprint] = nil
        }
    }
}
