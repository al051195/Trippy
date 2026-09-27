//
//  MediaAsset.swift
//  Trippy
//
//  A single photo or video belonging to a `Moment`.
//

import Foundation

/// Procedurally drawn artwork used by the pre-populated demo trip, so the sample
/// journal can be explored without importing a single photo.
struct DemoArtwork: Codable, Hashable {
    var hue: Double
    var secondaryHue: Double
    var symbolName: String
}

struct MediaAsset: Codable, Identifiable, Hashable {

    enum Kind: String, Codable, Hashable {
        case photo
        case video

        var symbolName: String {
            switch self {
            case .photo: "photo"
            case .video: "video"
            }
        }

        var displayName: String {
            switch self {
            case .photo: "Photo"
            case .video: "Video"
            }
        }
    }

    let id: UUID

    var kind: Kind

    /// Capture date, used for chronological ordering and moment clustering.
    var createdAt: Date

    /// Compressed image data used to render a thumbnail. `nil` for demo artwork.
    var imageData: Data?

    /// Duration in seconds, only meaningful for videos.
    var duration: TimeInterval?

    /// Procedurally drawn placeholder used when there is no image data.
    var demoArtwork: DemoArtwork?

    /// A clip longer than this is not worth calling a moment in a journal.
    var isLongFormVideo: Bool { (duration ?? 0) > 60 }

    var durationDescription: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
