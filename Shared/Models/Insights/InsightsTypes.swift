//
//  InsightsTypes.swift
//  Hiyoku
//
//  Created by 686udjie on 1/25/26.
//

import Foundation

struct SmallStatData: Identifiable {
    var id: String { subtitle }
    let total: Int
    let thisMonth: Int
    let thisYear: Int
    let subtitle: String
    let singularSubtitle: String?
}

struct YearlyMonthData: Identifiable {
    var id: Int { year }
    let year: Int
    let data: MonthData
}

struct MonthData: Equatable {
    var january: Int = 0
    var february: Int = 0
    var march: Int = 0
    var april: Int = 0
    var may: Int = 0
    var june: Int = 0
    var july: Int = 0
    var august: Int = 0
    var september: Int = 0
    var october: Int = 0
    var november: Int = 0
    var december: Int = 0

    var maxValue: Int {
        max(
            january, february, march, april, may, june,
            july, august, september, october, november, december
        )
    }

    var total: Int {
        january + february + march + april + may + june +
        july + august + september + october + november + december
    }

    func value(for month: Month) -> Int {
        switch month {
        case .january: january
        case .february: february
        case .march: march
        case .april: april
        case .may: may
        case .june: june
        case .july: july
        case .august: august
        case .september: september
        case .october: october
        case .november: november
        case .december: december
        }
    }
}

enum Month: Int, CaseIterable {
    case january = 1, february, march, april, may, june, july, august, september, october, november, december
}

struct BasicStats {
    var countTotal: Int = 0
    var countMonth: Int = 0
    var countYear: Int = 0
    var seriesTotal: Int = 0
    var seriesMonth: Int = 0
    var seriesYear: Int = 0
    var hoursTotal: Int = 0
    var hoursMonth: Int = 0
    var hoursYear: Int = 0
}
