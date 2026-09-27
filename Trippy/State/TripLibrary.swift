//
//  TripLibrary.swift
//  Trippy
//
//  Owns every trip in the app. Trips live in a single JSON file in Application
//  Support, so a trip survives relaunch.
//
//  Which trip is on screen is a navigation concern and lives in `TripStore`;
//  this type only knows about the collection and how to persist it.
//

import Foundation
import Observation

@MainActor
@Observable
final class TripLibrary {

    private(set) var trips: [Trip] = []

    private let fileURL: URL
    private var isLoaded = false

    init(fileURL: URL = TripLibrary.defaultFileURL()) {
        self.fileURL = fileURL
    }

    // MARK: - Derived state

    var hasTrips: Bool { !trips.isEmpty }

    /// Journeys most recently added first, which is the order a new trip should
    /// appear in at the top of the list.
    var orderedTrips: [Trip] {
        trips.reversed()
    }

    func trip(with id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    var isEmpty: Bool { trips.isEmpty }

    // MARK: - Aggregates, for the settings screen

    var totalMomentCount: Int {
        trips.reduce(0) { $0 + $1.momentCount }
    }

    var totalMediaCount: Int {
        trips.reduce(0) { $0 + $1.mediaCount }
    }

    var totalStorageDescription: String? {
        try? dataSizeDescription()
    }

    // MARK: - Lifecycle

    /// Loads from disk, seeding the sample trip the first time the app runs.
    func load() {
        guard !isLoaded else { return }
        isLoaded = true

        if let stored = Self.read(from: fileURL) {
            trips = stored
            return
        }

        trips = [DemoTrip.make()]
        save()
    }

    // MARK: - Creating, duplicating, deleting

    @discardableResult
    func addTrip(name: String, destination: String, startDate: Date? = nil, endDate: Date? = nil) -> Trip {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trip = Trip.empty(
            name: trimmedName.isEmpty ? "Untitled Trip" : trimmedName,
            destination: destination
        )
        var created = trip
        created.startDate = startDate
        created.endDate = endDate

        trips.append(created)
        save()
        return created
    }

    /// Adds the pre-populated sample trip, unless it is already in the library.
    @discardableResult
    func addSampleTrip() -> Trip? {
        guard !trips.contains(where: { $0.name == DemoTrip.name }) else { return nil }
        let trip = DemoTrip.make()
        trips.append(trip)
        save()
        return trip
    }

    @discardableResult
    func duplicate(_ id: UUID) -> Trip? {
        guard let source = trip(with: id) else { return nil }

        let copy = Trip(
            id: UUID(),
            name: "\(source.name) Copy",
            destination: source.destination,
            startDate: source.startDate,
            endDate: source.endDate,
            moments: source.moments.map { moment in
                Moment(
                    id: UUID(),
                    timestamp: moment.timestamp,
                    mediaAssets: moment.mediaAssets,
                    suggestedTitle: moment.suggestedTitle,
                    title: moment.title,
                    caption: moment.caption,
                    aiDescription: moment.aiDescription,
                    isFavorite: moment.isFavorite
                )
            },
            daySummaries: source.daySummaries.map { summary in
                DaySummary(id: UUID(), day: summary.day, text: summary.text, isDraft: summary.isDraft)
            }
        )

        trips.append(copy)
        save()
        return copy
    }

    /// The last remaining trip is kept, so the library is never emptied out from
    /// under the traveller.
    var canDeleteAnyTrip: Bool { trips.count > 1 }

    func canDelete(_ id: UUID) -> Bool {
        canDeleteAnyTrip && trips.contains { $0.id == id }
    }

    func delete(_ id: UUID) {
        guard canDelete(id) else { return }
        trips.removeAll { $0.id == id }
        save()
    }

    // MARK: - Mutation

    /// The only way the rest of the app edits a trip. Keeping every write behind
    /// this one function is what makes saving to disk reliable.
    func mutate(_ id: UUID?, _ body: (inout Trip) -> Void) {
        guard let id,
              let index = trips.firstIndex(where: { $0.id == id }) else { return }
        body(&trips[index])
        save()
    }

    // MARK: - Storage

    private func save() {
        guard isLoaded else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(trips)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A failed save is not worth interrupting the traveller over; the
            // in-memory library stays correct for this session.
        }
    }

    private func dataSizeDescription() throws -> String? {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber else { return nil }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private static func read(from url: URL) -> [Trip]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Trip].self, from: data)
    }

    private nonisolated static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(filePath: NSTemporaryDirectory())
        return base.appending(path: "Trippy", directoryHint: .isDirectory)
            .appending(path: "trips.json")
    }
}
