import Foundation

/// Lifecycle state for the global capture panel.
enum CaptureState: String, Equatable, CaseIterable {
    case hidden
    case opening
    case capturing
    case switchingBucket
    case saving
    case discarding
    case preservingDraft
    case closing

    /// Whether the panel is logically visible or transitioning to visible.
    var isVisible: Bool {
        switch self {
        case .hidden, .closing, .discarding, .preservingDraft:
            return false
        case .opening, .capturing, .switchingBucket, .saving:
            return true
        }
    }
}
