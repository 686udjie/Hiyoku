//
//  EpisodeSortOption.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import Foundation

enum EpisodeSortOption: Int, CaseIterable {
    case sourceOrder = 0
    case episode

    var title: String {
        switch self {
        case .sourceOrder:
            return NSLocalizedString("SOURCE_ORDER", comment: "")
        case .episode:
            return NSLocalizedString("EPISODE", comment: "")
        }
    }
}
