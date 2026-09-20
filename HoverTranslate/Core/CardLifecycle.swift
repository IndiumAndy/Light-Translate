import Foundation

/// Lifecycle of the result card: live while the trigger key is held, frozen for
/// a short window after release, pinned only on an explicit user click.
struct CardLifecycle {
    enum Phase: Equatable {
        case hidden
        case live
        case frozen
        case pinned
    }

    private(set) var phase: Phase = .hidden
    private var closeAt: Date?

    var isVisible: Bool { phase != .hidden }

    /// A pinned card is never replaced by a new hover.
    var acceptsNewContent: Bool { phase != .pinned }

    /// Buttons are only offered once the trigger key is released, because a
    /// held card stays click-through.
    var showsButtons: Bool { phase == .frozen || phase == .pinned }

    var hasPendingClose: Bool { closeAt != nil && phase != .pinned }

    mutating func showLive(now: Date) {
        guard phase != .pinned else { return }
        phase = .live
        closeAt = nil
    }

    mutating func release(now: Date, freeze: TimeInterval = 1.0) {
        guard phase == .live else { return }
        phase = .frozen
        closeAt = now.addingTimeInterval(freeze)
    }

    mutating func pointerInside() {
        guard phase == .live || phase == .frozen else { return }
        closeAt = nil
    }

    mutating func pointerOutside(now: Date, grace: TimeInterval = 0.6) {
        guard phase == .frozen else { return }
        closeAt = now.addingTimeInterval(grace)
    }

    mutating func pin() {
        guard phase != .hidden else { return }
        phase = .pinned
        closeAt = nil
    }

    mutating func dismiss() {
        phase = .hidden
        closeAt = nil
    }

    func shouldClose(now: Date) -> Bool {
        guard let closeAt else { return false }
        return now >= closeAt
    }
}
