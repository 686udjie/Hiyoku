//
//  PlaceholderGridView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/17/26.
//

import SwiftUI

struct PlaceholderGridView: View {
    private let gridColumns = [
        GridItem(.adaptive(minimum: 140), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(0..<16, id: \.self) { _ in
                    PlaceholderGridCard()
                }
            }
            .padding()
        }
        .shimmering()
    }
}

struct PlaceholderGridCard: View {
    var body: some View {
        MangaGridItem.placeholder
    }
}
