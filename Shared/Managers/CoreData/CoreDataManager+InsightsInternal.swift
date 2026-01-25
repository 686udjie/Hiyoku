//
//  CoreDataManager+InsightsInternal.swift
//  Hiyoku
//
//  Created by 686udjie on 1/25/26.
//

import CoreData
import Foundation

extension CoreDataManager {
    // MARK: Helpers for Insights

    func getInternalStreakLengths(entityName: String, dateProperty: String, context: NSManagedObjectContext?) -> (current: Int, longest: Int) {
        let context = context ?? self.context

        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: entityName)
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.propertiesToFetch = [dateProperty]
        let results = try? context.fetch(fetchRequest)
        guard let results else { return (0, 0) }

        let calendar = Calendar.current
        let daysSet = Set(results.compactMap { dict in
            (dict[dateProperty] as? Date).map { calendar.startOfDay(for: $0) }
        })
        let days = Array(daysSet).sorted()

        guard days.count >= 2 else { return (0, 0) }
        var current = 1
        var longest = 1

        for i in 1..<days.count {
            let prev = days[i - 1]
            let curr = days[i]
            let diff = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }

        let today = calendar.startOfDay(for: Date.now)
        let lastDay = days.last!
        let diff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        let isCurrent = (diff == 0 || diff == 1) && longest >= 2

        return (
            current: isCurrent ? current : 0,
            longest: longest >= 2 ? longest : 0
        )
    }

    func getInternalHeatmapData(
        entityName: String,
        dateProperty: String,
        identityProperties: [String],
        context: NSManagedObjectContext?
    ) -> HeatmapData {
        let context = context ?? self.context

        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date.now))!
        let (totalDays, startDate) = HeatmapData.getDaysAndStartDate()

        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: entityName)
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.predicate = NSPredicate(
            format: "%K >= %@ AND %K <= %@",
            dateProperty, startDate as NSDate, dateProperty, startOfTomorrow as NSDate
        )
        fetchRequest.propertiesToFetch = [dateProperty] + identityProperties

        guard let results = try? context.fetch(fetchRequest) else {
            return .empty()
        }

        var dayToHistorySet: [Date: Set<String>] = [:]
        for dict in results {
            guard let date = dict[dateProperty] as? Date else { continue }

            let identity = identityProperties.compactMap { dict[$0] as? String }.joined(separator: "-")
            let day = calendar.startOfDay(for: date)
            dayToHistorySet[day, default: []].insert(identity)
        }

        return .init(
            startDate: startDate,
            values: (0..<totalDays).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: startDate)!
                return dayToHistorySet[date]?.count ?? 0
            }
        )
    }

    func getInternalYearlyData(
        entityName: String,
        dateProperty: String,
        groupingProperties: [String],
        context: NSManagedObjectContext?,
        isCounted: @escaping (NSDictionary) -> Bool
    ) -> [YearlyMonthData] {
        let context = context ?? self.context

        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: entityName)
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.propertiesToFetch = [dateProperty] + groupingProperties
        guard let results = try? context.fetch(fetchRequest) else { return [] }

        var yearlyMonthCounts: [Int: [Int: Int]] = [:] // [year: [month: count]]
        let calendar = Calendar.current

        for dict in results {
            guard let date = dict[dateProperty] as? Date, isCounted(dict) else { continue }

            let comps = calendar.dateComponents([.year, .month], from: date)
            guard let year = comps.year, let month = comps.month else { continue }

            yearlyMonthCounts[year, default: [:]][month, default: 0] += 1
        }

        let sortedYears = yearlyMonthCounts.keys.sorted()
        var result: [YearlyMonthData] = []

        for year in sortedYears {
            let data = MonthData(
                january: yearlyMonthCounts[year]?[1] ?? 0,
                february: yearlyMonthCounts[year]?[2] ?? 0,
                march: yearlyMonthCounts[year]?[3] ?? 0,
                april: yearlyMonthCounts[year]?[4] ?? 0,
                may: yearlyMonthCounts[year]?[5] ?? 0,
                june: yearlyMonthCounts[year]?[6] ?? 0,
                july: yearlyMonthCounts[year]?[7] ?? 0,
                august: yearlyMonthCounts[year]?[8] ?? 0,
                september: yearlyMonthCounts[year]?[9] ?? 0,
                october: yearlyMonthCounts[year]?[10] ?? 0,
                november: yearlyMonthCounts[year]?[11] ?? 0,
                december: yearlyMonthCounts[year]?[12] ?? 0
            )
            result.append(.init(year: year, data: data))
        }

        return result
    }

    struct BasicStatsConfig {
        let entityName: String
        let dateProperty: String
        let durationProperty: String?
        let countProperty: String?
        let identityProperties: [String]
    }

    func getInternalBasicStats(config: BasicStatsConfig, context: NSManagedObjectContext?) -> BasicStats {
        let context = context ?? self.context

        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: config.entityName)
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.propertiesToFetch = [config.dateProperty] + config.identityProperties
            + (config.durationProperty.map { [$0] } ?? [])
            + (config.countProperty.map { [$0] } ?? [])

        if config.entityName == "ReadingSession" {
            fetchRequest.propertiesToFetch?.append("startDate")
        }

        guard let results = try? context.fetch(fetchRequest) else {
            return .init()
        }

        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        var countTotal = 0, countMonth = 0, countYear = 0
        var durationTotal: Double = 0, durationMonth: Double = 0, durationYear: Double = 0

        var seriesTotalSet = Set<String>()
        var seriesMonthSet = Set<String>()
        var seriesYearSet = Set<String>()

        for dict in results {
            guard let date = dict[config.dateProperty] as? Date else { continue }
            let countValue = (config.countProperty.flatMap { dict[$0] as? Int }) ?? 1

            let duration: Double = if let durationProperty = config.durationProperty {
                if let val = dict[durationProperty] as? Int32 {
                    Double(val)
                } else if let val = dict[durationProperty] as? Int {
                    Double(val)
                } else if let val = dict[durationProperty] as? Double {
                    val
                } else {
                    0
                }
            } else {
                0
            }
            // shitcode
            let sessionDuration: Double = if config.entityName == "ReadingSession", let startDate = dict["startDate"] as? Date {
                date.timeIntervalSince(startDate)
            } else {
                duration
            }

            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let seriesKey = config.identityProperties.compactMap { dict[$0] as? String }.joined(separator: "-")

            countTotal += countValue
            durationTotal += sessionDuration
            seriesTotalSet.insert(seriesKey)

            if year == currentYear {
                countYear += countValue
                durationYear += sessionDuration
                seriesYearSet.insert(seriesKey)

                if month == currentMonth {
                    countMonth += countValue
                    durationMonth += sessionDuration
                    seriesMonthSet.insert(seriesKey)
                }
            }
        }

        return BasicStats(
            countTotal: countTotal,
            countMonth: countMonth,
            countYear: countYear,
            seriesTotal: seriesTotalSet.count,
            seriesMonth: seriesMonthSet.count,
            seriesYear: seriesYearSet.count,
            hoursTotal: Int(durationTotal / 3600),
            hoursMonth: Int(durationMonth / 3600),
            hoursYear: Int(durationYear / 3600)
        )
    }

    func fetchInsights(kind: InsightsData.Kind) async -> InsightsData {
        await container.performBackgroundTask { context in
            let (currentStreak, longestStreak) = self.getInternalStreakLengths(
                entityName: kind.entityName,
                dateProperty: kind.dateProperty,
                context: context
            )
            let heatmapData = self.getInternalHeatmapData(
                entityName: kind.entityName,
                dateProperty: kind.dateProperty,
                identityProperties: kind.identityProperties,
                context: context
            )
            let basicStats = self.getInternalBasicStats(
                config: .init(
                    entityName: kind.entityName,
                    dateProperty: kind.dateProperty,
                    durationProperty: kind.durationProperty,
                    countProperty: kind.countProperty,
                    identityProperties: kind.basicStatsIdentityProperties
                ),
                context: context
            )
            let chartData = self.getInternalYearlyData(
                entityName: kind.entityName,
                dateProperty: kind.dateProperty,
                groupingProperties: kind == .reader ? ["pagesRead", "history.total", "history.completed"] : [],
                context: context
            ) { dict in
                if kind == .reader {
                    let totalPagesRead = dict["pagesRead"] as? Int ?? 0
                    let totalPageCount = dict["history.total"] as? Int
                    let isCompleted = dict["history.completed"] as? Bool ?? false
                    if let totalPageCount {
                        return totalPagesRead >= totalPageCount
                    } else {
                        return isCompleted
                    }
                } else {
                    return true
                }
            }
            return InsightsData(
                kind: kind,
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                heatmapData: heatmapData,
                chartData: chartData,
                stats: basicStats
            )
        }
    }
}
