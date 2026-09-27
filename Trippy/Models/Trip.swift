//
//  Trip.swift
//  Trippy
//
//  A whole journey: its identity, the days it spans and every moment in it.
//

import Foundation

/// How the journal column orders a trip's moments.
enum TripSortOrder: String, CaseIterable, Identifiable, Hashable {
    case chronological
    case newestFirst
    case favoritesFirst

    var id: Self { self }

    var title: String {
        switch self {
        case .chronological: "Oldest First"
        case .newestFirst: "Newest First"
        case .favoritesFirst: "Favorites First"
        }
    }

    var symbolName: String {
        switch self {
        case .chronological: "arrow.up.arrow.down"
        case .newestFirst: "arrow.down"
        case .favoritesFirst: "star"
        }
    }

    /// The comparison a list uses to order moments for this sort order.
    var comparator: (Moment, Moment) -> Bool {
        switch self {
        case .chronological:
            { $0.timestamp < $1.timestamp }
        case .newestFirst:
            { $0.timestamp > $1.timestamp }
        case .favoritesFirst:
            { lhs, rhs in
                lhs.isFavorite == rhs.isFavorite
                    ? lhs.timestamp < rhs.timestamp
                    : lhs.isFavorite
            }
        }
    }
}

struct Trip: Codable, Identifiable, Hashable {

    let id: UUID

    var name: String
    var destination: String

    /// Optional dates the traveller sets themselves. A trip can be planned before
    /// anything is imported, and an imported photo's capture date is not always
    /// the day the traveller was actually there.
    var startDate: Date?
    var endDate: Date?

    var moments: [Moment]
    var daySummaries: [DaySummary]

    // MARK: - Derived

    /// Moments sorted oldest first — the canonical order for the journal.
    var chronologicalMoments: [Moment] {
        moments.sorted { $0.timestamp < $1.timestamp }
    }

    func moments(sortedBy order: TripSortOrder) -> [Moment] {
        chronologicalMoments.sorted(by: order.comparator)
    }

    /// Every distinct day that has at least one moment, oldest first.
    var days: [Date] {
        let calendar = Calendar.current
        return Array(Set(chronologicalMoments.map { calendar.startOfDay(for: $0.timestamp) }))
            .sorted()
    }

    func summary(for day: Date) -> DaySummary? {
        let calendar = Calendar.current
        return daySummaries.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// The journal split into days, in the requested order within each day.
    func dayGroups(sortedBy order: TripSortOrder) -> [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: chronologicalMoments) {
            calendar.startOfDay(for: $0.timestamp)
        }

        return grouped
            .map { day, moments in
                DayGroup(
                    day: day,
                    moments: moments.sorted(by: order.comparator),
                    summary: summary(for: day)
                )
            }
            .sorted { $0.day < $1.day }
    }

    func moment(with id: UUID) -> Moment? {
        moments.first { $0.id == id }
    }

    /// The day a moment belongs to.
    func day(of moment: Moment) -> Date {
        Calendar.current.startOfDay(for: moment.timestamp)
    }

    var momentCount: Int { moments.count }

    var mediaCount: Int {
        moments.reduce(0) { $0 + $1.mediaAssets.count }
    }

    var favoriteCount: Int {
        moments.filter(\.isFavorite).count
    }

    var isEmpty: Bool { moments.isEmpty }

    var trimmedDestination: String {
        destination.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The trip's own dates when the traveller set them, otherwise the span its
    /// photos were taken over.
    var resolvedStartDate: Date? {
        startDate ?? chronologicalMoments.first?.timestamp
    }

    var resolvedEndDate: Date? {
        endDate ?? chronologicalMoments.last?.timestamp
    }

    /// A compact "Apr 14 – 18, 2026" style span, or `nil` when nothing is known.
    var dateRangeDescription: String? {
        guard let first = resolvedStartDate else { return nil }
        guard let last = resolvedEndDate else {
            return first.formatted(.dateTime.month(.abbreviated).day().year())
        }

        let calendar = Calendar.current
        if calendar.isDate(first, inSameDayAs: last) {
            return first.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    /// A one-line description of the trip for lists and share sheets.
    var subtitleDescription: String {
        [trimmedDestination, dateRangeDescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The trip rendered as plain text, for sharing a journal out of the app.
    var plainTextSummary: String {
        var lines: [String] = [name]
        let subtitle = subtitleDescription
        if !subtitle.isEmpty { lines.append(subtitle) }
        lines.append("")

        for group in dayGroups(sortedBy: .chronological) {
            lines.append(group.weekday)
            lines.append(group.dateDescription)
            if let summary = group.summary, !summary.isEmpty {
                lines.append("")
                lines.append(summary.trimmedText)
            }
            for moment in group.moments {
                lines.append("")
                let time = moment.timestamp.formatted(date: .omitted, time: .shortened)
                lines.append("  \(time) — \(moment.displayTitle)")
                if !moment.trimmedCaption.isEmpty {
                    lines.append("  \(moment.trimmedCaption)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Creating

    /// Spelled out because the custom `init(from:)` below stops Swift from
    /// synthesising the memberwise initialiser.
    init(
        id: UUID = UUID(),
        name: String,
        destination: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        moments: [Moment] = [],
        daySummaries: [DaySummary] = []
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.moments = moments
        self.daySummaries = daySummaries
    }

    static func empty(name: String, destination: String) -> Trip {
        Trip(
            id: UUID(),
            name: name,
            destination: destination,
            startDate: nil,
            endDate: nil,
            moments: [],
            daySummaries: []
        )
    }

    // MARK: - Persistence

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case destination
        case startDate
        case endDate
        case moments
        case daySummaries
    }

    /// Decoded field by field so trips saved before the traveller could set their
    /// own dates keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        destination = try container.decodeIfPresent(String.self, forKey: .destination) ?? ""
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        moments = try container.decodeIfPresent([Moment].self, forKey: .moments) ?? []
        daySummaries = try container.decodeIfPresent([DaySummary].self, forKey: .daySummaries) ?? []
    }
}
