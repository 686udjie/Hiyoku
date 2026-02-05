//
//  MangaGridItem.swift
//  Aidoku
//
//  Created by Skitty on 8/16/23.
//

import AidokuRunner
import SwiftUI
import NukeUI

struct MangaGridItem: View {
    var source: AidokuRunner.Source?
    let title: String
    let coverImage: String
    var bookmarked: Bool = false
    var badge: Int = 0
    var badge2: Int = 0

    var body: some View {
        let view = Rectangle()
            .fill(Color.clear)
            .aspectRatio(2/3, contentMode: .fill)
            .background {
                SourceImageView(
                    source: source,
                    imageUrl: coverImage,
                    downsampleWidth: 400 // reduces stuttering caused by rendering large images
                )
            }
            .overlay(
                LinearGradient(
                    gradient: UIConstants.imageOverlayGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                bookmarkView,
                alignment: .topTrailing
            )
            .overlay(
                badgeView,
                alignment: .topLeading
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
            )
            .overlay(
                Text(title)
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .padding(8),
                alignment: .bottomLeading
            )
        if coverImage.hasSuffix("gif") {
            // if the image is a gif, we can't use drawingGroup (static image)
            view
        } else {
            view.drawingGroup()
        }
    }

    @ViewBuilder
    var bookmarkView: some View {
        if bookmarked {
            Image("bookmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.tint)
                .frame(width: 17, height: 27, alignment: .topTrailing)
                .padding(.trailing, 8)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    var badgeView: some View {
        HStack(spacing: 0) {
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 20)
                    .background(Color.accentColor)
                    .clipShape(
                        SpecificRoundedCorner(
                            radius: 5,
                            corners: [
                                .topLeft,
                                .bottomLeft,
                                badge2 > 0 ? [] : .bottomRight,
                                badge2 > 0 ? [] : .topRight
                            ].reduce(into: UIRectCorner()) { $0.insert($1) }
                        )
                    )
            }
            if badge2 > 0 {
                Text("\(badge2)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 20)
                    .background(Color.indigo)
                    .clipShape(
                        SpecificRoundedCorner(
                            radius: 5,
                            corners: [
                                badge > 0 ? [] : .topLeft,
                                badge > 0 ? [] : .bottomLeft,
                                .bottomRight,
                                .topRight
                            ].reduce(into: UIRectCorner()) { $0.insert($1) }
                        )
                    )
            }
        }
        .padding([.top, .leading], 5)
    }

    static var placeholder: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemFill))
            .aspectRatio(2/3, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
            )
    }
}

private struct SpecificRoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
