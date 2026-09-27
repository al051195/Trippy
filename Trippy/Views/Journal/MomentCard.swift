//
//  MomentCard.swift
//  Trippy
//
//  One moment in the journal: the cover photo and the words the traveller wrote
//  for it, together on a single glass card. The photo runs edge to edge across
//  the top of the card and the words sit inside it below, the way the old present
//  view stacked a day — but as one surface rather than two.
//

import SwiftUI

struct MomentCard: View {

    let moment: Moment

    /// True while the model is reading this moment's photos for search.
    let isDescribing: Bool

    /// True when this moment is the one shown in the detail column.
    let isSelected: Bool

    /// The same corner radius and inset the day card uses, so the journal reads
    /// as one stack of cards rather than two competing styles.
    static let cornerRadius: CGFloat = 28
    static let inset: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover = moment.coverAsset {
                coverImage(cover)
            }

            words
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.inset)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(.rect)
    }

    /// Only the top corners are rounded. The bottom of the photo runs straight
    /// into the words beneath it, because they share the one card.
    private func coverImage(_ cover: MediaAsset) -> some View {
        MediaThumbnail(asset: cover)
            .frame(height: 210)
            .clipShape(.rect(
                topLeadingRadius: Self.cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Self.cornerRadius
            ))
            .overlay(alignment: .topTrailing) {
                if moment.mediaCount > 1 {
                    Text("\(moment.mediaCount)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .padding(10)
                }
            }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(moment.timestamp, format: .dateTime.hour().minute())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(8)
                    .glassEffect(.regular.interactive())

                if isDescribing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                if moment.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(8)
                        .glassEffect(.regular.interactive())
                }
            }

            Text(moment.displayTitle)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if !moment.trimmedCaption.isEmpty {
                Text(moment.trimmedCaption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let suggestion = moment.pendingSuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 26) {
            MomentCard(
                moment: DemoTrip.make().moments[0],
                isDescribing: false,
                isSelected: false
            )
            MomentCard(
                moment: DemoTrip.make().moments[2],
                isDescribing: true,
                isSelected: true
            )
        }
        .padding(18)
    }
}

