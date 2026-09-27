//
//  FoundationModelService.swift
//  Trippy
//
//  Every on-device model capability the journal uses, behind a single runtime
//  availability check. `SystemLanguageModel.availability` is the source of truth
//  — no device-model list is hardcoded anywhere in the app.
//

import Foundation
import FoundationModels
import Observation
import UIKit

// Guided-generation shapes. These are declared at file scope rather than nested
// inside the service: the `@Generable` macro expands into a synthesized source
// file, which cannot reach `private` or `fileprivate` declarations. Keeping them
// at file scope also documents each prompt's expected output.

@Generable
struct TitleSuggestion {
    @Guide(description: "A short evocative title between 5 and 8 words. Title case, no quotes, no trailing full stop.")
    var title: String
}

@Generable
struct MomentDescription {
    @Guide(description: "One or two sentences describing what is visible: subjects, setting, time of day and mood. No speculation about who the people are.")
    var description: String
    @Guide(description: "Up to 8 comma separated keywords that someone might use to search for this photo later.", .count(6))
    var keywords: [String]
}

@Generable
struct QueryKeywords {
    @Guide(description: "Up to 8 comma separated keywords describing what someone would want to see. Include the literal word used in the query when it makes sense.")
    var keywords: [String]
}

@Generable
struct NarrativeDraft {
    @Guide(description: "2 to 4 sentences of warm, plain prose summarising the day of a travel journal. No bullet points, no headings, no emoji.")
    var text: String
}

@MainActor
@Observable
final class FoundationModelService {

    /// Why the on-device model can or cannot be used right now.
    enum Availability: Equatable {
        case available
        case unavailable(reason: String)

        var isAvailable: Bool { self == .available }
    }

    private static let systemModel = SystemLanguageModel.default

    /// Re-read from the system rather than cached: the model can finish
    /// downloading, or Apple Intelligence can be switched on, while we are running.
    private(set) var availability: Availability = FoundationModelService.currentAvailability()

    var isAvailable: Bool { availability.isAvailable }

    var availabilityDescription: String {
        switch availability {
        case .available:
            "On-device model ready"
        case let .unavailable(reason):
            reason
        }
    }

    /// Call when returning to the foreground, in case availability changed.
    func refreshAvailability() {
        availability = Self.currentAvailability()
    }

    // MARK: - Title suggestion

    /// Proposes a 5-8 word title for a moment. On iOS 27 and later the photos
    /// are attached to the prompt directly; on iOS 26 — where the on-device
    /// model has no image input — the moment's caption and any Vision notes are
    /// used as the textual stand-in.
    func suggestTitle(for moment: Moment, extraContext: String? = nil) async throws -> String {
        let session = LanguageModelSession(instructions: """
        You name the sections of a personal travel journal. You are terse, warm and \
        concrete. You never use hashtags, emoji, quotation marks or full stops at \
        the end of a title.
        """)

        let assets = moment.mediaAssets
        let imageCount = assets.filter { $0.kind == .photo }.count
        let videoCount = assets.filter { $0.kind == .video }.count
        let context = Self.textualContext(for: moment, extraContext: extraContext)

        let response = try await session.respond(generating: TitleSuggestion.self) {
            Prompt("""
            Suggest one title for a journal section made of \
            \(imageCount) photo\(imageCount == 1 ? "" : "s")\
            \(videoCount > 0 ? " and \(videoCount) short video\(videoCount == 1 ? "" : "s")" : "") \
            captured at \(moment.shortTimeDescription).
            \(context)

            Title it after what the images actually show.
            """)

            if #available(iOS 27, *) {
                for (index, image) in MediaImage.attachments(for: moment).enumerated() {
                    Attachment(image).label("photo-\(index)")
                }
            }
        }

        return sanitizedTitle(response.content.title)
    }

    // MARK: - Natural-language search

    /// Produces the cached description used to match free-text queries.
    /// Called once per moment on import, then stored on the moment.
    func describe(_ moment: Moment, extraContext: String? = nil) async throws -> String {
        let session = LanguageModelSession(instructions: """
        You catalogue photographs for a personal travel journal so they can be found \
        later by describing them. You only describe what is visible.
        """)

        let context = Self.textualContext(for: moment, extraContext: extraContext)

        let response = try await session.respond(generating: MomentDescription.self) {
            Prompt("""
            Describe these images from a travel journal, taken at \
            \(moment.shortTimeDescription).
            \(context)
            """)

            if #available(iOS 27, *) {
                for (index, image) in MediaImage.attachments(for: moment).enumerated() {
                    Attachment(image).label("photo-\(index)")
                }
            }
        }

        let keywords = response.content.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return ([response.content.description.trimmingCharacters(in: .whitespacesAndNewlines)] + keywords)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Turns a free-text query into keywords that are matched against the cached
    /// descriptions. Returns `nil` so callers can fall back to the raw query.
    func keywords(for query: String) async -> [String]? {
        let session = LanguageModelSession(instructions: """
        You turn a person's casual request into search keywords for a photo library. \
        You answer with keywords only.
        """)

        do {
            let response = try await session.respond(generating: QueryKeywords.self) {
                Prompt("""
                A traveller is looking through their trip journal and typed: \
                "\(query)". List the keywords their photos would be described with.
                """)
            }
            let keywords = response.content.keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            return keywords.isEmpty ? nil : keywords
        } catch {
            return nil
        }
    }

    // MARK: - Day summary

    /// Writes a short narrative from a day's titles and captions.
    func daySummary(for moments: [Moment], on day: Date, trip: Trip?) async throws -> String {
        let session = LanguageModelSession(instructions: """
        You write the short narrative that opens each day of a personal travel journal. \
        You write 2 to 4 sentences of plain, reflective prose in the first person \
        plural. You never invent events that are not in the notes, and you never use \
        bullet points, headings or emoji.
        """)

        let notes = moments
            .sorted { $0.timestamp < $1.timestamp }
            .map { moment in
                let title = moment.displayTitle
                let caption = moment.caption.trimmingCharacters(in: .whitespacesAndNewlines)
                return caption.isEmpty ? "- \(title)" : "- \(title) — \(caption)"
            }
            .joined(separator: "\n")

        let place = trip.map { "\($0.name) in \($0.trimmedDestination)" } ?? "a personal travel journal"

        let response = try await session.respond(generating: NarrativeDraft.self) {
            Prompt("""
            Summarise this day of \(place) into a short narrative draft.

            \(day.formatted(date: .complete, time: .omitted).capitalized)
            \(notes)
            """)
        }

        return response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Availability

    /// The text that stands in for the photographs on iOS 26, and supplements
    /// them on iOS 27+: the moment's own words plus whatever Vision observed.
    private static func textualContext(for moment: Moment, extraContext: String?) -> String {
        var lines: [String] = []

        let caption = moment.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            lines.append("The traveller captioned these: \"\(caption)\"")
        }

        if let extraContext,
           !extraContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("On-device analysis of the images reported: \(extraContext)")
        }

        guard !lines.isEmpty else { return "" }
        return "\n" + lines.joined(separator: "\n")
    }

    private static func currentAvailability() -> Availability {
        switch systemModel.availability {
        case .available:
            .available
        case .unavailable(let reason):
            .unavailable(reason: describe(reason))
        }
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "Not available — this device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Not available — Apple Intelligence is turned off in Settings."
        case .modelNotReady:
            "Not available yet — the model is still downloading."
        @unknown default:
            "Not available on this device."
        }
    }

    private func sanitizedTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = title.last, ".!?\"'".contains(last) {
            title = String(title.dropLast())
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
