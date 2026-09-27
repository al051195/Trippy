//
//  DaySummary.swift
//  Trippy
//
//  The narrative that opens one day of a trip, and the grouping the journal list
//  is built from.
//

import Foundation

/// A model-written narrative for a single day of the trip. Always user-editable.
struct DaySummary: Codable, Identifiable, Hashable {

    let id: UUID
    var day: Date
    var text: String

    /// `true` while the text is the model's proposal that the traveller has not
    /// rewritten, so the UI can label it as a starting point rather than a
    /// finished note.
    var isDraft: Bool

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool { trimmedText.isEmpty }
}

/// One calendar day of a journal: its narrative plus the moments captured on it.
struct DayGroup: Identifiable, Hashable {

    /// Midnight of the day, in the calendar's time zone.
    let day: Date
    let moments: [Moment]
    let summary: DaySummary?

    var id: Date { day }

    var mediaCount: Int {
        moments.reduce(0) { $0 + $1.mediaAssets.count }
    }

    var hasMedia: Bool { !moments.isEmpty }

    var weekday: String {
        day.formatted(.dateTime.weekday(.wide))
    }

    var dateDescription: String {
        day.formatted(.dateTime.month(.wide).day().year())
    }

    var shortDateDescription: String {
        day.formatted(.dateTime.month(.abbreviated).day())
    }
}
