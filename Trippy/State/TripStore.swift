//
//  TripStore.swift
//  Trippy
//
//  Owns which trip and moment are on screen, and every interaction with the
//  on-device model. All writes go through `TripLibrary.mutate` so they are always
//  persisted.
//
//  Model-backed features check `ai.isAvailable` first, so on an unsupported
//  device the app simply runs without them.
//

import Foundation
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class TripStore {

    let ai = FoundationModelService()

    /// Every trip. The single owner of trip data.
    let library: TripLibrary

    // MARK: - Selection

    /// The trip whose journal is on screen. `nil` means the traveller has not
    /// chosen one, or the one they chose was deleted.
    private(set) var selectedTripID: UUID?

    /// The moment shown in the detail column. `nil` means "no moment chosen",
    /// which is the normal state in a two-column layout.
    private(set) var selectedMomentID: UUID?

    /// Which column sits on top once the split view collapses on iPhone. Starts
    /// on the sidebar so the app opens on the list of trips.
    var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    /// How the journal column orders this trip's moments.
    var sortOrder: TripSortOrder = .chronological

    // MARK: - Search

    var searchQuery: String = ""
    private(set) var searchKeywords: [String] = []
    private(set) var isSearching = false
    private var searchTask: Task<Void, Never>?

    // MARK: - Import

    private(set) var isImporting = false

    // MARK: - In-flight model work

    private(set) var suggestingTitleIDs: Set<UUID> = []
    private(set) var describingIDs: Set<UUID> = []
    private(set) var summarizingDays: Set<Date> = []

    var errorMessage: String?

    /// Vision output, kept only for the lifetime of the session.
    private var visionNotes: [UUID: String] = [:]

    init(library: TripLibrary? = nil) {
        let library = library ?? TripLibrary()
        self.library = library
        library.load()
        selectedTripID = library.orderedTrips.first?.id
    }

    // MARK: - Derived state

    /// Every AI-powered control is behind this one flag.
    var isAIEnabled: Bool { ai.isAvailable }

    var trips: [Trip] { library.orderedTrips }

    var selectedTrip: Trip? {
        guard let selectedTripID else { return nil }
        return library.trip(with: selectedTripID)
    }

    var selectedMoment: Moment? {
        guard let momentID = selectedMomentID else { return nil }
        return selectedTrip?.moment(with: momentID)
    }

    var moments: [Moment] {
        selectedTrip?.chronologicalMoments ?? []
    }

    var hasMoments: Bool { !(selectedTrip?.moments.isEmpty ?? true) }

    /// The journal split into days, in the traveller's chosen order within each
    /// day. Days with no moments left after a search are dropped entirely.
    var dayGroups: [DayGroup] {
        guard let trip = selectedTrip else { return [] }

        let matches = visibleMomentIDs
        return trip
            .dayGroups(sortedBy: sortOrder)
            .compactMap { group in
                let kept = group.moments.filter { matches.contains($0.id) }
                guard !kept.isEmpty else { return nil }
                return DayGroup(day: group.day, moments: kept, summary: group.summary)
            }
    }

    /// Moments shown in the journal: everything, or the search matches.
    var visibleMoments: [Moment] {
        dayGroups.flatMap(\.moments)
    }

    var favoriteMoments: [Moment] {
        moments.filter(\.isFavorite)
    }

    /// The plain-text journal, for the share sheet.
    var shareText: String {
        selectedTrip?.plainTextSummary ?? ""
    }

    // MARK: - Search terms

    /// Terms a moment is matched against: whatever the model expanded the query
    /// into, plus the raw words. The raw words are always included, so search
    /// still works on a device without Apple Intelligence.
    var searchTerms: [String] {
        let raw = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        var terms = searchKeywords + raw
        terms = terms
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return Array(Set(terms))
    }

    private var visibleMomentIDs: Set<UUID> {
        let terms = searchTerms
        let trip = selectedTrip
        let ordered = trip?.moments(sortedBy: sortOrder) ?? []

        guard !terms.isEmpty else { return Set(ordered.map(\.id)) }
        return Set(
            ordered
                .filter { moment in
                    let haystack = moment.searchableText
                    return terms.contains { term in
                        haystack.range(of: term) != nil
                    }
                }
                .map(\.id)
        )
    }

    var isSearchingForSomething: Bool { !searchTerms.isEmpty }

    var hasNoSearchResults: Bool {
        isSearchingForSomething && visibleMoments.isEmpty
    }

    // MARK: - Selection

    func select(tripID: UUID?) {
        guard tripID != selectedTripID else { return }
        selectedTripID = tripID
        selectedMomentID = nil
        resetTransientState()
    }

    func select(momentID: UUID?) {
        guard momentID != selectedMomentID else { return }
        selectedMomentID = momentID
    }

    func moment(with id: UUID) -> Moment? {
        selectedTrip?.moment(with: id)
    }

    /// Clears the detail column, which is what a moment's delete button does once
    /// the moment is gone.
    private func clearSelectionIfNeeded(for momentID: UUID) {
        if selectedMomentID == momentID {
            selectedMomentID = nil
        }
    }

    // MARK: - Trip lifecycle

    @discardableResult
    func newTrip(name: String, destination: String, startDate: Date? = nil, endDate: Date? = nil) -> Trip {
        let trip = library.addTrip(name: name, destination: destination, startDate: startDate, endDate: endDate)
        select(tripID: trip.id)
        return trip
    }

    @discardableResult
    func addSampleTrip() -> Trip? {
        let trip = library.addSampleTrip()
        if let trip { select(tripID: trip.id) }
        return trip
    }

    @discardableResult
    func duplicateSelectedTrip() -> Trip? {
        guard let id = selectedTripID, let copy = library.duplicate(id) else { return nil }
        select(tripID: copy.id)
        return copy
    }

    func deleteTrip(_ id: UUID) {
        library.delete(id)
        if selectedTripID == id {
            selectedTripID = library.orderedTrips.first?.id
            selectedMomentID = nil
            resetTransientState()
        }
    }

    /// Renames a trip and sets the dates the traveller chose for it.
    func updateTripDetails(
        id: UUID,
        name: String,
        destination: String,
        startDate: Date?,
        endDate: Date?
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        library.mutate(id) { trip in
            trip.name = trimmed.isEmpty ? "Untitled Trip" : trimmed
            trip.destination = destination
            trip.startDate = startDate
            trip.endDate = endDate
        }
    }

    private func resetTransientState() {
        clearSearch()
        suggestingTitleIDs.removeAll()
        describingIDs.removeAll()
        summarizingDays.removeAll()
        visionNotes.removeAll()
    }

    // MARK: - Moment mutations

    func deleteMoment(_ id: UUID) {
        library.mutate(selectedTripID) { $0.moments.removeAll { $0.id == id } }
        clearSelectionIfNeeded(for: id)
    }

    func toggleFavorite(_ id: UUID) {
        updateMoment(id) { moment in
            moment.isFavorite.toggle()
        }
    }

    func setTimestamp(_ date: Date, for id: UUID) {
        updateMoment(id) { $0.timestamp = date }
    }

    /// Drops one photo or video out of a moment, removing the moment entirely once
    /// it has nothing left in it.
    func deleteMedia(momentID: UUID, assetID: UUID) {
        var becameEmpty = false
        library.mutate(selectedTripID) { trip in
            guard let index = trip.moments.firstIndex(where: { $0.id == momentID }) else { return }
            trip.moments[index].mediaAssets.removeAll { $0.id == assetID }
            becameEmpty = trip.moments[index].mediaAssets.isEmpty
        }

        if becameEmpty {
            deleteMoment(momentID)
        }
    }

    // MARK: - Day summaries

    func daySummary(for day: Date) -> DaySummary? {
        selectedTrip?.summary(for: day)
    }

    func updateDaySummary(for day: Date, text: String) {
        updateSummary(for: day) { summary in
            summary.text = text
            // Anything the traveller has typed is no longer a draft.
            summary.isDraft = false
        }
    }

    func deleteDaySummary(for day: Date) {
        let calendar = Calendar.current
        library.mutate(selectedTripID) { trip in
            trip.daySummaries.removeAll { calendar.isDate($0.day, inSameDayAs: day) }
        }
    }

    // MARK: - Bindings

    /// Selection for the sidebar, routed through `select(tripID:)` so that
    /// changing trip still clears the moment selection and any search.
    var selectedTripIDBinding: Binding<UUID?> {
        Binding(
            get: { self.selectedTripID },
            set: { self.select(tripID: $0) }
        )
    }

    /// Selection for the journal list.
    var selectedMomentIDBinding: Binding<UUID?> {
        Binding(
            get: { self.selectedMomentID },
            set: { self.select(momentID: $0) }
        )
    }

    func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.moment(with: id)?.title ?? "" },
            set: { [weak self] newValue in self?.updateMoment(id) { $0.title = newValue } }
        )
    }

    func captionBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.moment(with: id)?.caption ?? "" },
            set: { [weak self] newValue in self?.updateMoment(id) { $0.caption = newValue } }
        )
    }

    func favoriteBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.moment(with: id)?.isFavorite ?? false },
            set: { [weak self] newValue in self?.updateMoment(id) { $0.isFavorite = newValue } }
        )
    }

    func timestampBinding(for id: UUID) -> Binding<Date> {
        Binding(
            get: { [weak self] in self?.moment(with: id)?.timestamp ?? .now },
            set: { [weak self] newValue in self?.setTimestamp(newValue, for: id) }
        )
    }

    func summaryTextBinding(for day: Date) -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard let self else { return "" }
                return self.daySummary(for: day)?.text ?? ""
            },
            set: { [weak self] newValue in
                self?.updateDaySummary(for: day, text: newValue)
            }
        )
    }

    // MARK: - Model: titles

    func suggestTitle(for id: UUID) async {
        guard isAIEnabled, !suggestingTitleIDs.contains(id), let moment = moment(with: id) else { return }

        suggestingTitleIDs.insert(id)
        defer { suggestingTitleIDs.remove(id) }

        do {
            let title = try await ai.suggestTitle(for: moment, extraContext: visionNotes[id])
            updateMoment(id) { $0.suggestedTitle = title }
        } catch {
            report(error, fallback: "Couldn't suggest a title.")
        }
    }

    /// One tap moves the model's proposal into the real title.
    func acceptSuggestion(for id: UUID) {
        guard let suggestion = moment(with: id)?.suggestedTitle,
              !suggestion.isEmpty else { return }
        updateMoment(id) { $0.title = suggestion }
    }

    // MARK: - Model: descriptions

    /// Re-reads a moment's media and caches a description for search. Also
    /// available by hand, so a moment imported before the model was ready can
    /// still be described later.
    func describe(momentID: UUID) async {
        guard isAIEnabled, !describingIDs.contains(momentID),
              let original = moment(with: momentID) else { return }

        if let image = MediaImage.attachments(for: original, maxPixelSize: 512).first {
            visionNotes[momentID] = await ImageAnalyzer.analyze(image)
        }

        guard let enriched = moment(with: momentID) else { return }
        describingIDs.insert(momentID)
        defer { describingIDs.remove(momentID) }

        do {
            let text = try await ai.describe(enriched, extraContext: visionNotes[momentID])
            updateMoment(momentID) { $0.aiDescription = text }
        } catch {
            report(error, fallback: "Couldn't describe that moment.")
        }
    }

    func isDescribing(_ momentID: UUID) -> Bool { describingIDs.contains(momentID) }

    // MARK: - Model: day summaries

    func summarize(day: Date) async {
        guard isAIEnabled, !summarizingDays.contains(day) else { return }

        let calendar = Calendar.current
        let dayMoments = moments.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
        guard !dayMoments.isEmpty else { return }

        summarizingDays.insert(day)
        defer { summarizingDays.remove(day) }

        do {
            let text = try await ai.daySummary(for: dayMoments, on: day, trip: selectedTrip)
            library.mutate(selectedTripID) { trip in
                if let index = trip.daySummaries.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
                    trip.daySummaries[index].text = text
                    trip.daySummaries[index].isDraft = true
                } else {
                    trip.daySummaries.append(DaySummary(id: UUID(), day: day, text: text, isDraft: true))
                }
            }
        } catch {
            report(error, fallback: "Couldn't write a summary for that day.")
        }
    }

    func isSummarizing(day: Date) -> Bool { summarizingDays.contains(day) }

    // MARK: - Search

    func searchQueryChanged(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        searchTask = nil
        searchKeywords = []
        isSearching = false

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAIEnabled, trimmed.count > 2 else { return }

        searchTask = Task { [weak self] in
            // Wait for the traveller to stop typing before spending a request.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }

            self.isSearching = true
            let keywords = await self.ai.keywords(for: trimmed)
            guard !Task.isCancelled else {
                self.isSearching = false
                return
            }
            self.searchKeywords = keywords ?? []
            self.isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
        searchKeywords = []
        isSearching = false
    }

    // MARK: - Import

    /// Adds photos and videos to the trip, grouping them into new moments by
    /// capture time.
    func importItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, let tripID = selectedTripID else { return }
        isImporting = true
        defer { isImporting = false }

        let assets = await MediaImportService.load(items: items)
        guard !assets.isEmpty else { return }

        let newMoments = MediaImportService.cluster(assets)
        library.mutate(tripID) { $0.moments.append(contentsOf: newMoments) }

        // Describe each new moment once so natural-language search has something
        // to match against later.
        for moment in newMoments where isAIEnabled {
            await describe(momentID: moment.id)
        }
    }

    /// Adds photos and videos to a moment that already exists, so an existing
    /// entry can be corrected without deleting and re-importing it.
    func addItems(_ items: [PhotosPickerItem], to momentID: UUID) async {
        guard !items.isEmpty, selectedTripID != nil else { return }
        isImporting = true
        defer { isImporting = false }

        let assets = await MediaImportService.load(items: items)
        guard !assets.isEmpty else { return }

        library.mutate(selectedTripID) { trip in
            guard let index = trip.moments.firstIndex(where: { $0.id == momentID }) else { return }
            trip.moments[index].mediaAssets.append(contentsOf: assets)
            trip.moments[index].mediaAssets.sort { $0.createdAt < $1.createdAt }
        }
    }

    // MARK: - Mutation helpers

    private func updateMoment(_ id: UUID, _ body: (inout Moment) -> Void) {
        library.mutate(selectedTripID) { trip in
            guard let index = trip.moments.firstIndex(where: { $0.id == id }) else { return }
            body(&trip.moments[index])
        }
    }

    private func updateSummary(for day: Date, _ body: (inout DaySummary) -> Void) {
        let calendar = Calendar.current
        library.mutate(selectedTripID) { trip in
            if let index = trip.daySummaries.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
                body(&trip.daySummaries[index])
            } else {
                var summary = DaySummary(id: UUID(), day: day, text: "", isDraft: false)
                body(&summary)
                trip.daySummaries.append(summary)
            }
        }
    }

    private func report(_ error: Error, fallback: String) {
        errorMessage = Self.message(for: error) ?? fallback
    }

    private static func message(for error: Error) -> String? {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return nil
    }
}
