//
//  PlayerHistoryObjectProtocol.swift
//  Hiyoku
//
//  Created by 686udjie on 1/10/26.
//

import Foundation
import CoreData

protocol PlayerHistoryObjectProtocol: NSManagedObject {
    var playerTitle: String { get set }
    var dateWatched: Date { get set }
    var episodeId: String { get set }
    var episodeNumber: Int16 { get set }
    var episodeTitle: String? { get set }
    var moduleId: String { get set }
    var progress: Int16 { get set }
    var sourceUrl: String { get set }
    var total: Int16? { get set }
    var watchedDuration: Int32 { get set }
}
