//
//  DemoTrip.swift
//  Trippy
//
//  A pre-populated trip so the journal can be explored without granting photo
//  library access or relying on a live import flow.
//

import Foundation

/// `Calendar.current` is main-actor isolated, and the demo is only ever built
/// from the trip library, which is too.
@MainActor
enum DemoTrip {

    /// Fixed dates so the demo is deterministic.
    static let dayOne = date(year: 2026, month: 4, day: 14)
    static let dayTwo = date(year: 2026, month: 4, day: 15)

    static let name = "A day in Cupertino"
    static let destination = "Cupertino, California"

    static func make() -> Trip {
        let moments = arrivalBlueprints.map { $0.makeMoment(on: dayOne) }
            + exploringBlueprints.map { $0.makeMoment(on: dayTwo) }

        return Trip(
            id: UUID(),
            name: name,
            destination: destination,
            startDate: dayOne,
            endDate: dayTwo,
            moments: moments,
            daySummaries: [dayOne, dayTwo].map(summary(for:))
        )
    }

    // MARK: - Blueprints

    private struct Blueprint {
        var hour: Int
        var minute: Int
        var title: String
        var caption: String
        var description: String
        var symbolName: String
        var hue: Double
        var secondaryHue: Double
        var extraAssetCount: Int
        var includesVideo: Bool
        var isFavorite: Bool = false

        func makeMoment(on day: Date) -> Moment {
            let calendar = Calendar.current
            let timestamp = calendar.date(
                bySettingHour: hour, minute: minute, second: 0, of: day
            ) ?? day

            var assets: [MediaAsset] = [makePhoto(at: timestamp, hue: hue, secondaryHue: secondaryHue)]

            for index in 0..<extraAssetCount {
                assets.append(makePhoto(
                    at: timestamp.addingTimeInterval(Double(90 * (index + 1))),
                    hue: (hue + Double(index + 1) * 24).truncatingRemainder(dividingBy: 360),
                    secondaryHue: (secondaryHue + Double(index + 1) * 30).truncatingRemainder(dividingBy: 360)
                ))
            }

            if includesVideo {
                assets.append(MediaAsset(
                    id: UUID(),
                    kind: .video,
                    createdAt: timestamp.addingTimeInterval(240),
                    imageData: nil,
                    duration: 14,
                    demoArtwork: DemoArtwork(
                        hue: (hue + 48).truncatingRemainder(dividingBy: 360),
                        secondaryHue: (secondaryHue + 48).truncatingRemainder(dividingBy: 360),
                        symbolName: "video"
                    )
                ))
            }

            return Moment(
                id: UUID(),
                timestamp: timestamp,
                mediaAssets: assets,
                suggestedTitle: nil,
                title: title,
                caption: caption,
                aiDescription: description,
                isFavorite: isFavorite
            )
        }

        private func makePhoto(at date: Date, hue: Double, secondaryHue: Double) -> MediaAsset {
            MediaAsset(
                id: UUID(),
                kind: .photo,
                createdAt: date,
                imageData: nil,
                duration: nil,
                demoArtwork: DemoArtwork(hue: hue, secondaryHue: secondaryHue, symbolName: symbolName)
            )
        }
    }

    private static let arrivalBlueprints: [Blueprint] = [
        Blueprint(
            hour: 8, minute: 55,
            title: "Touchdown in thick fog",
            caption: "The whole bay was white when we landed. Rental shuttle, then straight for the highway.",
            description: "Travellers with luggage carts walking out of an airport terminal at dawn, a departures board overhead and heavy fog outside the windows.",
            symbolName: "airplane",
            hue: 208, secondaryHue: 226,
            extraAssetCount: 1, includesVideo: false
        ),
        Blueprint(
            hour: 11, minute: 20,
            title: "Queuing for a rental car",
            caption: "Forty minutes and three re-shuffles of the line. Worth it for the playlist.",
            description: "A line of people waiting at a car rental counter inside an airport rental centre, with suitcases and a row of car keys on the desk.",
            symbolName: "car.fill",
            hue: 32, secondaryHue: 12,
            extraAssetCount: 0, includesVideo: true
        ),
        Blueprint(
            hour: 13, minute: 5,
            title: "Tacos on Santana Row",
            caption: "First real food in two days. Carnitas, and we did not regret the order.",
            description: "A plate of street tacos with lime wedges on an outdoor restaurant patio, string lights overhead and people eating at tables in the afternoon sun.",
            symbolName: "fork.knife",
            hue: 14, secondaryHue: 40,
            extraAssetCount: 1, includesVideo: false, isFavorite: true
        )
    ]

    private static let exploringBlueprints: [Blueprint] = [
        Blueprint(
            hour: 10, minute: 40,
            title: "The ring from the visitor deck",
            caption: "Sat on the bench far longer than planned. The whole campus is smaller in person.",
            description: "A huge circular glass office building with a reflecting pond and a stainless steel sculpture out front, photographed in bright clear daylight.",
            symbolName: "building.2.fill",
            hue: 196, secondaryHue: 172,
            extraAssetCount: 2, includesVideo: false
        ),
        Blueprint(
            hour: 14, minute: 25,
            title: "Redwoods off the beaten path",
            caption: "Took the wrong turn on purpose and found a footbridge over a creek.",
            description: "Tall redwood trees in a shaded forest grove with a small wooden footbridge crossing a stream, soft green light filtering through the canopy.",
            symbolName: "tree.fill",
            hue: 128, secondaryHue: 96,
            extraAssetCount: 1, includesVideo: true
        ),
        Blueprint(
            hour: 18, minute: 5,
            title: "Sunset over the foothills",
            caption: "The reason we stayed an extra night.",
            description: "A golden sunset over rolling green hills with long shadows stretching across the grass and a hazy warm sky.",
            symbolName: "sun.horizon.fill",
            hue: 28, secondaryHue: 350,
            extraAssetCount: 2, includesVideo: false, isFavorite: true
        ),
        Blueprint(
            hour: 20, minute: 15,
            title: "Late dinner in Little Italy",
            caption: "Patio under the string lights, sharing everything.",
            description: "An outdoor restaurant table set for dinner under warm string lights, plates of pasta and wine glasses, people talking at neighbouring tables at night.",
            symbolName: "wineglass.fill",
            hue: 268, secondaryHue: 300,
            extraAssetCount: 0, includesVideo: false
        )
    ]

    // MARK: - Pre-written summaries

    private static func summary(for day: Date) -> DaySummary {
        let text = Calendar.current.isDate(day, inSameDayAs: dayOne)
            ? """
            Arrival day, mostly fought against the fog. We made it from the airport to \
            Santana Row with one very long rental counter queue and immediately found \
            tacos, which fixed the mood for the rest of the afternoon.
            """
            : """
            A slower day built around two anchors: the ring building in the morning \
            light, and the redwood grove in the shade of the afternoon. The sunset over \
            the foothills was the moment the whole trip turned around, and we closed it \
            out sharing plates under string lights.
            """

        return DaySummary(id: UUID(), day: day, text: text, isDraft: false)
    }

    // MARK: - Helpers

    private static func date(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
