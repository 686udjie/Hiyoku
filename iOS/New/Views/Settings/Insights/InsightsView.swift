//
//  InsightsView.swift
//  Aidoku
//
//  Created by Skitty on 12/16/25.
//

import SwiftUI

struct InsightsView: View {
    @State private var kind: InsightsData.Kind = .reader
    @State private var readerData: InsightsData = .init(kind: .reader)
    @State private var playerData: InsightsData = .init(kind: .player)
    @State private var statsGridHeight: CGFloat = .zero
    @State private var shouldAnimateGridHeightChange = false

    var body: some View {
        let data = kind == .reader ? readerData : playerData
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Picker("", selection: $kind) {
                        Text(NSLocalizedString("READER")).tag(InsightsData.Kind.reader)
                        Text(NSLocalizedString("PLAYER")).tag(InsightsData.Kind.player)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(NSLocalizedString("STREAKS"))
                            .font(.system(size: 15).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                InsightPlatterView {
                                    Group {
                                        if data.currentStreak > 1 {
                                            VStack(spacing: 0) {
                                                Text(NSLocalizedString("CURRENT_STREAK"))
                                                    .font(.system(size: 14))
                                                VStack(spacing: -5) {
                                                    Text(data.currentStreak, format: .number.notation(.compactName))
                                                        .font(.system(size: 38).weight(.bold))
                                                    Text(NSLocalizedString("DAYS"))
                                                        .font(.body.weight(.semibold))
                                                        .multilineTextAlignment(.center)
                                                }
                                            }
                                        } else {
                                            VStack(spacing: 4) {
                                                Text(NSLocalizedString("NO_CURRENT_STREAK"))
                                                    .font(.headline)
                                                Text(NSLocalizedString("NO_CURRENT_STREAK_TEXT"))
                                                    .font(.subheadline)
                                                    .multilineTextAlignment(.center)
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .frame(height: 110)
                                    .frame(maxWidth: .infinity)
                                }

                                if data.longestStreak > data.currentStreak && data.longestStreak > 1 {
                                    InsightPlatterView {
                                        VStack(spacing: 0) {
                                            Text(NSLocalizedString("LONGEST_STREAK"))
                                                .font(.system(size: 14))
                                            VStack(spacing: -5) {
                                                Text(data.longestStreak, format: .number.notation(.compactName))
                                                    .font(.system(size: 38).weight(.bold))
                                                Text(NSLocalizedString("DAYS"))
                                                    .font(.body.weight(.semibold))
                                                    .multilineTextAlignment(.center)
                                            }
                                        }
                                        .padding(12)
                                        .frame(height: 110)
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }

                            InsightPlatterView {
                                HStack(spacing: 0) {
                                    LinearGradient(
                                        gradient: Gradient(
                                            colors: [
                                                Color(UIColor.secondarySystemGroupedBackground),
                                                Color(UIColor.secondarySystemGroupedBackground).opacity(0)
                                            ]
                                        ),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .flipsForRightToLeftLayoutDirection(true)
                                    .frame(width: 12)
                                    .zIndex(1)

                                    HeatmapView(data: data.heatmapData)
                                        .padding(.vertical, 12)
                                        .zIndex(0)

                                    LinearGradient(
                                        gradient: Gradient(
                                            colors: [
                                                Color(UIColor.secondarySystemGroupedBackground).opacity(0),
                                                Color(UIColor.secondarySystemGroupedBackground)
                                            ]
                                        ),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .flipsForRightToLeftLayoutDirection(true)
                                    .frame(width: 12)
                                    .zIndex(1)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(NSLocalizedString("STATS"))
                            .font(.system(size: 15).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        StatsGridView(
                            chartLabel: kind == .reader ? NSLocalizedString("CHAPTER_PLURAL") : NSLocalizedString("EPISODE_PLURAL"),
                            chartSingularLabel: kind == .reader ? NSLocalizedString("CHAPTER_SINGULAR") : NSLocalizedString("EPISODE_SINGULAR"),
                            chartData: data.chartData,
                            items: data.statsData,
                            height: $statsGridHeight
                        )
                        .frame(height: statsGridHeight)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .animation(shouldAnimateGridHeightChange ? .default : nil, value: statsGridHeight)
            .onChangeWrapper(of: statsGridHeight) { oldValue, _ in
                // prevent animation on initial height set
                if oldValue != 0 {
                    shouldAnimateGridHeightChange = true
                }
            }
        }
        .onChangeWrapper(of: kind) { _, _ in
            shouldAnimateGridHeightChange = false
        }
        .navigationTitle(NSLocalizedString("INSIGHTS"))
        .task {
            async let reader = InsightsData.get(kind: .reader)
            async let player = InsightsData.get(kind: .player)
            let (r, p) = await (reader, player)
            readerData = r
            playerData = p
        }
    }
}

#Preview {
    PlatformNavigationStack {
        InsightsView()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {} label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
    }
}
