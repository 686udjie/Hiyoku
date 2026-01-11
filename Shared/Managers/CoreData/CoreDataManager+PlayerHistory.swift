//
//  CoreDataManager+PlayerHistory.swift
//  Hiyoku
//
//  Created by 686udjie on 1/10/26.
//

import CoreData

extension CoreDataManager {
    func getPlayerHistory(
        episodeId: String,
        moduleId: String,
        context: NSManagedObjectContext? = nil
    ) -> PlayerHistoryObject? {
        let context = context ?? container.viewContext

        let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "episodeId == %@ AND moduleId == %@",
            episodeId,
            moduleId
        )
        fetchRequest.fetchLimit = 1

        return try? context.fetch(fetchRequest).first
    }

    func getAllPlayerHistory(
        context: NSManagedObjectContext? = nil
    ) -> [PlayerHistoryObject] {
        let context = context ?? container.viewContext

        let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "dateWatched", ascending: false)]

        return (try? context.fetch(fetchRequest)) ?? []
    }

    func getPlayerHistoryForContent(
        sourceUrl: String,
        moduleId: String,
        context: NSManagedObjectContext? = nil
    ) -> [PlayerHistoryObject] {
        let context = context ?? container.viewContext

        let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "sourceUrl == %@ AND moduleId == %@",
            sourceUrl,
            moduleId
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "episodeNumber", ascending: true)]

        return (try? context.fetch(fetchRequest)) ?? []
    }

    func createOrUpdatePlayerHistory(
        _ data: PlayerHistoryManager.EpisodeHistoryData,
        context: NSManagedObjectContext? = nil
    ) -> PlayerHistoryObject {
        let context = context ?? container.viewContext
        let existingHistory = getPlayerHistory(episodeId: data.episodeId, moduleId: data.moduleId, context: context)
        let historyObject = existingHistory ?? PlayerHistoryObject(context: context)
        historyObject.playerTitle = data.playerTitle
        historyObject.episodeId = data.episodeId
        historyObject.episodeNumber = Int16(data.episodeNumber)
        historyObject.episodeTitle = data.episodeTitle
        historyObject.sourceUrl = data.sourceUrl
        historyObject.moduleId = data.moduleId
        historyObject.progress = Int16(data.progress)
        historyObject.total = data.total.map(Int16.init)
        historyObject.watchedDuration = Int32(data.watchedDuration)
        historyObject.dateWatched = data.date

        return historyObject
    }

    func updatePlayerHistoryProgress(
        episodeId: String,
        moduleId: String,
        progress: Int,
        total: Int? = nil,
        watchedDuration: TimeInterval = 0,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        let context = context ?? container.viewContext

        guard let historyObject = getPlayerHistory(episodeId: episodeId, moduleId: moduleId, context: context) else {
            return false
        }

        historyObject.progress = Int16(progress)
        historyObject.total = total.map(Int16.init)
        historyObject.watchedDuration += Int32(watchedDuration)
        historyObject.dateWatched = Date()

        return true
    }

    func markPlayerEpisodeCompleted(
        episodeId: String,
        moduleId: String,
        watchedDuration: TimeInterval = 0,
        context: NSManagedObjectContext? = nil
    ) -> Bool {
        let context = context ?? container.viewContext

        guard let historyObject = getPlayerHistory(episodeId: episodeId, moduleId: moduleId, context: context) else {
            return false
        }

        historyObject.progress = historyObject.total
        historyObject.watchedDuration += Int32(watchedDuration)
        historyObject.dateWatched = Date()

        return true
    }

    func removePlayerHistory(
        episodeId: String,
        moduleId: String,
        context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? container.viewContext

        let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "episodeId == %@ AND moduleId == %@",
            episodeId,
            moduleId
        )

        do {
            let results = try context.fetch(fetchRequest)
            for historyObject in results {
                context.delete(historyObject)
            }
        } catch { }
    }

    func removePlayerHistoryForContent(
        sourceUrl: String,
        moduleId: String,
        context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? container.viewContext

        let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "sourceUrl == %@ AND moduleId == %@",
            sourceUrl,
            moduleId
        )

        do {
            let results = try context.fetch(fetchRequest)
            for historyObject in results {
                context.delete(historyObject)
            }
        } catch { }
    }

    func clearAllPlayerHistory(context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext

        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = PlayerHistoryObject.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

        do {
            try context.execute(deleteRequest)
        } catch { }
    }

    func getPlayerHistoryCount(context: NSManagedObjectContext? = nil) -> Int {
        let context = context ?? container.viewContext

        let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()

        return (try? context.count(for: fetchRequest)) ?? 0
    }

    func getRecentlyWatchedPlayer(
        limit: Int = 10,
        context: NSManagedObjectContext? = nil
    ) -> [PlayerHistoryObject] {
        let context = context ?? container.viewContext

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "dateWatched >= %@", thirtyDaysAgo as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "dateWatched", ascending: false)]
        fetchRequest.fetchLimit = limit

        return (try? context.fetch(fetchRequest)) ?? []
    }
}
