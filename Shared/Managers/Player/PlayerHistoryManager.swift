//
//  PlayerHistoryManager.swift
//  Hiyoku
//
//  Created by 686udjie on 1/10/26.
//

import CoreData

final class PlayerHistoryManager: Sendable {
    static let shared = PlayerHistoryManager()
}

extension PlayerHistoryManager {

    struct PlayerWatchingSession {
        let startDate: Date
        let endDate: Date
        let watchedDuration: TimeInterval // in seconds
    }

    struct EpisodeHistoryData {
        let playerTitle: String
        let episodeId: String
        let episodeNumber: Int
        let episodeTitle: String?
        let sourceUrl: String
        let moduleId: String
        let progress: Int
        let total: Int?
        let watchedDuration: TimeInterval
        let date: Date
    }

    func addEpisodeHistory(_ data: EpisodeHistoryData) async {
        // Check if incognito mode is enabled
        guard !UserDefaults.standard.bool(forKey: UserDefaultsKey.General.incognitoMode) else {
            return
        }

        await CoreDataManager.shared.container.performBackgroundTask { context in
            self.saveEpisodeHistory(data: data, context: context)
        }

        postHistoryAddedNotification(data: data)
    }

    private func saveEpisodeHistory(data: EpisodeHistoryData, context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "episodeId == %@ AND moduleId == %@",
            data.episodeId,
            data.moduleId
        )

        do {
            let existingHistory = try context.fetch(fetchRequest)
            let historyObject = existingHistory.first ?? PlayerHistoryObject(context: context)
            updateHistoryObject(historyObject, with: data)

            try context.save()
        } catch {
            LogManager.logger.error("PlayerHistoryManager.saveEpisodeHistory: \(error.localizedDescription)")
        }
    }

    private func updateHistoryObject(_ historyObject: PlayerHistoryObject, with data: EpisodeHistoryData) {
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
    }

    private func postHistoryAddedNotification(data: EpisodeHistoryData) {
        NotificationCenter.default.post(
            name: .playerHistoryAdded,
            object: PlayerHistoryItem(
                playerTitle: data.playerTitle,
                episodeId: data.episodeId,
                episodeNumber: data.episodeNumber,
                episodeTitle: data.episodeTitle,
                sourceUrl: data.sourceUrl,
                moduleId: data.moduleId,
                progress: data.progress,
                total: data.total,
                watchedDuration: data.watchedDuration,
                dateWatched: data.date
            )
            )
    }

    func updateProgress(
        episodeId: String,
        moduleId: String,
        progress: Int,
        total: Int? = nil,
        watchedDuration: TimeInterval = 0
    ) async {
        // Check if incognito mode is enabled
        guard !UserDefaults.standard.bool(forKey: UserDefaultsKey.General.incognitoMode) else {
            return
        }

        await CoreDataManager.shared.container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "episodeId == %@ AND moduleId == %@",
                episodeId,
                moduleId
            )

            do {
                let results = try context.fetch(fetchRequest)
                if let historyObject = results.first {
                    historyObject.progress = Int16(progress)
                    historyObject.total = total.map(Int16.init)
                    historyObject.watchedDuration += Int32(watchedDuration)
                    historyObject.dateWatched = Date() // Update last watched time

                    try context.save()
                }
            } catch {
                LogManager.logger.error("PlayerHistoryManager.updateProgress: \(error.localizedDescription)")
            }
        }
    }

    func markCompleted(
        episodeId: String,
        moduleId: String,
        watchedDuration: TimeInterval = 0
    ) async {
        // Check if incognito mode is enabled
        guard !UserDefaults.standard.bool(forKey: UserDefaultsKey.General.incognitoMode) else {
            return
        }

        await CoreDataManager.shared.container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "episodeId == %@ AND moduleId == %@",
                episodeId,
                moduleId
            )

            do {
                let results = try context.fetch(fetchRequest)
                if let historyObject = results.first {
                    historyObject.progress = historyObject.total // Mark as fully watched
                    historyObject.watchedDuration += Int32(watchedDuration)
                    historyObject.dateWatched = Date()

                    try context.save()
                }
            } catch {
                LogManager.logger.error("PlayerHistoryManager.markCompleted: \(error.localizedDescription)")
            }
        }

        NotificationCenter.default.post(
            name: .playerHistoryUpdated,
            object: (episodeId: episodeId, moduleId: moduleId)
        )
    }

    func removeHistory(episodeId: String, moduleId: String) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
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
                try context.save()
            } catch {
                // Error handling without debug logging
            }
        }

        NotificationCenter.default.post(
            name: .playerHistoryRemoved,
            object: (episodeId: episodeId, moduleId: moduleId)
        )
    }

    func removeHistoryForContent(sourceUrl: String, moduleId: String) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
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
                try context.save()
            } catch {
                // Error handling without debug logging
            }
        }

        NotificationCenter.default.post(
            name: .playerHistoryRemoved,
            object: (sourceUrl: sourceUrl, moduleId: moduleId)
        )
    }

    func getAllHistory() async -> [PlayerHistoryItem] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "dateWatched", ascending: false)]

            do {
                let results = try context.fetch(fetchRequest)
                return results.compactMap { historyObject in
                    guard let playerTitle = historyObject.playerTitle,
                          let episodeId = historyObject.episodeId,
                          let sourceUrl = historyObject.sourceUrl,
                          let moduleId = historyObject.moduleId,
                          let dateWatched = historyObject.dateWatched else {
                        return nil
                    }

                    return PlayerHistoryItem(
                        playerTitle: playerTitle,
                        episodeId: episodeId,
                        episodeNumber: Int(historyObject.episodeNumber),
                        episodeTitle: historyObject.episodeTitle,
                        sourceUrl: sourceUrl,
                        moduleId: moduleId,
                        progress: Int(historyObject.progress),
                        total: historyObject.total.map(Int.init),
                        watchedDuration: TimeInterval(historyObject.watchedDuration),
                        dateWatched: dateWatched
                    )
                }
            } catch {
                return []
            }
        }
    }

    func getHistoryForContent(sourceUrl: String, moduleId: String) async -> [PlayerHistoryItem] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "sourceUrl == %@ AND moduleId == %@",
                sourceUrl,
                moduleId
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "episodeNumber", ascending: true)]

            do {
                let results = try context.fetch(fetchRequest)
                return results.compactMap { historyObject in
                    guard let playerTitle = historyObject.playerTitle,
                          let episodeId = historyObject.episodeId,
                          let sourceUrl = historyObject.sourceUrl,
                          let moduleId = historyObject.moduleId,
                          let dateWatched = historyObject.dateWatched else {
                        return nil
                    }

                    return PlayerHistoryItem(
                        playerTitle: playerTitle,
                        episodeId: episodeId,
                        episodeNumber: Int(historyObject.episodeNumber),
                        episodeTitle: historyObject.episodeTitle,
                        sourceUrl: sourceUrl,
                        moduleId: moduleId,
                        progress: Int(historyObject.progress),
                        total: historyObject.total.map(Int.init),
                        watchedDuration: TimeInterval(historyObject.watchedDuration),
                        dateWatched: dateWatched
                    )
                }
            } catch {
                return []
            }
        }
    }
}

struct PlayerHistoryItem: Identifiable {
    let id = UUID()

    let playerTitle: String
    let episodeId: String
    let episodeNumber: Int
    let episodeTitle: String?
    let sourceUrl: String
    let moduleId: String
    let progress: Int
    let total: Int?
    let watchedDuration: TimeInterval
    let dateWatched: Date

    var isCompleted: Bool {
        guard let total = total else { return false }
        return progress >= total
    }

    var progressPercentage: Double {
        guard let total = total, total > 0 else { return 0 }
        return Double(progress) / Double(total)
    }
}
