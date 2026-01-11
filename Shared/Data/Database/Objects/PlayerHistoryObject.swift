//
//  PlayerHistoryObject.swift
//  Hiyoku
//
//  Created by 686udjie on 1/10/26.
//

import Foundation
import CoreData

@objc(PlayerHistoryObject)
public class PlayerHistoryObject: NSManagedObject {

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        dateWatched = Date.distantPast
        progress = 0
        total = 0
        watchedDuration = 0
    }
}

extension PlayerHistoryObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PlayerHistoryObject> {
        NSFetchRequest<PlayerHistoryObject>(entityName: "PlayerHistory")
    }

    @NSManaged public var playerTitle: String
    @NSManaged public var dateWatched: Date
    @NSManaged public var episodeId: String
    @NSManaged public var episodeNumber: Int16
    @NSManaged public var episodeTitle: String?
    @NSManaged public var moduleId: String
    @NSManaged public var progress: Int16
    @NSManaged public var sourceUrl: String
    @NSManaged public var total: Int16?
    @NSManaged public var watchedDuration: Int32
}

extension PlayerHistoryObject: Identifiable {

}
