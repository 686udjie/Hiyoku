//
//  InsightsData.swift
//  Aidoku
//
//  Created by Skitty on 12/20/25.
//

import Foundation

struct InsightsData {
    enum Kind: String, CaseIterable {
        case reader
        case player

        var itemLabel: String {
            self == .reader ? NSLocalizedString("PAGE_PLURAL") : NSLocalizedString("EPISODE_PLURAL")
        }
        var itemSingularLabel: String {
            self == .reader ? NSLocalizedString("PAGE_SINGULAR") : NSLocalizedString("EPISODE_SINGULAR")
        }
        var entityName: String {
            self == .reader ? "ReadingSession" : "PlayerHistory"
        }
        var dateProperty: String {
            self == .reader ? "endDate" : "dateWatched"
        }
        var durationProperty: String? {
            self == .reader ? "startDate" : "watchedDuration"
        }
        var countProperty: String? {
            self == .reader ? "pagesRead" : nil
        }
        var identityProperties: [String] {
            self == .reader ? ["history.sourceId", "history.mangaId", "history.chapterId"] : ["moduleId", "episodeId"]
        }
        var basicStatsIdentityProperties: [String] {
            self == .reader ? ["history.sourceId", "history.mangaId"] : ["moduleId", "sourceUrl"]
        }
    }

    var currentStreak: Int
    var longestStreak: Int
    var heatmapData: HeatmapData
    var chartData: [YearlyMonthData]
    let statsData: [SmallStatData]

    init(
        kind: Kind = .reader,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        heatmapData: HeatmapData = .empty(),
        chartData: [YearlyMonthData] = [],
        stats: BasicStats = .init()
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.heatmapData = heatmapData
        self.chartData = chartData
        self.statsData = [
            .init(
                total: stats.countTotal,
                thisMonth: stats.countMonth,
                thisYear: stats.countYear,
                subtitle: kind.itemLabel,
                singularSubtitle: kind.itemSingularLabel
            ),
            .init(
                total: stats.seriesTotal,
                thisMonth: stats.seriesMonth,
                thisYear: stats.seriesYear,
                subtitle: NSLocalizedString("SERIES_PLURAL"),
                singularSubtitle: NSLocalizedString("SERIES_SINGULAR")
            ),
            .init(
                total: stats.hoursTotal,
                thisMonth: stats.hoursMonth,
                thisYear: stats.hoursYear,
                subtitle: NSLocalizedString("HOUR_PLURAL"),
                singularSubtitle: NSLocalizedString("HOUR_SINGULAR")
            )
        ]
    }

    static func get(kind: Kind = .reader) async -> InsightsData {
        await CoreDataManager.shared.fetchInsights(kind: kind)
    }

    static let demoData: InsightsData = .init(
        kind: .reader,
        currentStreak: 2,
        longestStreak: 3,
        heatmapData: .demo(),
        chartData: [
            .init(year: 2025, data: .init(
                january: 0,
                february: 0,
                march: 0,
                april: 0,
                may: 8,
                june: 0,
                july: 0,
                august: 0,
                september: 9,
                october: 0,
                november: 10,
                december: 1
            )),
            .init(year: 2024, data: .init(
                january: 1,
                february: 0,
                march: 0,
                april: 0,
                may: 8,
                june: 0,
                july: 0,
                august: 0,
                september: 0,
                october: 2,
                november: 7,
                december: 8
            ))
        ],
        stats: BasicStats(
            countTotal: 2354, countMonth: 34, countYear: 1234,
            seriesTotal: 4, seriesMonth: 0, seriesYear: 2,
            hoursTotal: 1, hoursMonth: 0, hoursYear: 1
        )
    )
}
