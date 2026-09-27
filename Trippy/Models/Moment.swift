//
//  Moment.swift
//  Trippy
//
//  A group of media captured close together in time: the journal's basic unit.
//

import Foundation

struct Moment: Codable, Identifiable, Hashable {

    let id: UUID

    var timestamp: Date
    var mediaAssets: [MediaAsset]

    /// Title proposed by the on-device model, kept so the user can re-accept it.
    var suggestedTitle: String?

    /// The title actually shown. Starts empty until accepted or typed.
    var title: String

    var caption: String

    /// Cached natural-language description of the moment's media, used by search.
    var aiDescription: String?

    /// Favourited moments are pinned to the top of the journal and can be shared
    /// on their own.
    var isFavorite: Bool

    // MARK: - Derived

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedCaption: String {
        caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasUserTitle: Bool { !trimmedTitle.isEmpty }

    /// The text a list row shows as its title, whether the traveller wrote it or
    /// the model suggested it.
    var displayTitle: String {
        if hasUserTitle { return trimmedTitle }
        if let suggestion = suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggestion.isEmpty {
            return suggestion
        }
        return "Untitled moment"
    }

    /// A model proposal is only worth offering while the traveller has not
    /// written a title of their own.
    var pendingSuggestion: String? {
        guard !hasUserTitle,
              let suggestion = suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggestion.isEmpty else { return nil }
        return suggestion
    }

    var coverAsset: MediaAsset? { mediaAssets.first }

    var mediaCount: Int { mediaAssets.count }

    var photoCount: Int { mediaAssets.filter { $0.kind == .photo }.count }

    var videoCount: Int { mediaAssets.filter { $0.kind == .video }.count }

    var isEmpty: Bool { mediaAssets.isEmpty }

    /// A short, locale-aware time of day, for list rows and model prompts.
    var shortTimeDescription: String {
        timestamp.formatted(date: .omitted, time: .shortened)
    }

    /// Everything search should match a free-text query against.
    var searchableText: String {
        [title, suggestedTitle ?? "", caption, aiDescription ?? ""]
            .joined(separator: " ")
            .lowercased()
    }

    // MARK: - Creating

    /// Spelled out because the custom `init(from:)` below stops Swift from
    /// synthesising the memberwise initialiser.
    init(
        id: UUID = UUID(),
        timestamp: Date,
        mediaAssets: [MediaAsset],
        suggestedTitle: String? = nil,
        title: String = "",
        caption: String = "",
        aiDescription: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mediaAssets = mediaAssets
        self.suggestedTitle = suggestedTitle
        self.title = title
        self.caption = caption
        self.aiDescription = aiDescription
        self.isFavorite = isFavorite
    }

    // MARK: - Persistence

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case mediaAssets
        case suggestedTitle
        case title
        case caption
        case aiDescription
        case isFavorite
    }

    /// Decoded field by field so journals written by an earlier version of the
    /// app — which had no `isFavorite` — keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        mediaAssets = try container.decode([MediaAsset].self, forKey: .mediaAssets)
        suggestedTitle = try container.decodeIfPresent(String.self, forKey: .suggestedTitle)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        aiDescription = try container.decodeIfPresent(String.self, forKey: .aiDescription)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}
