//
//  PlayerHistoryManager.swift
//  Hiyoku
//
//  Created by 686udjie on 1/10/26.
//

import Foundation
import CoreData

final class PlayerHistoryManager: Sendable {
    static let shared = PlayerHistoryManager()

    struct PlayerHistoryItem: Identifiable, Sendable {
        let id: String
        let playerTitle: String
        let episodeId: String
        let episodeNumber: Double
        let episodeTitle: String?
        let sourceUrl: String
        let moduleId: String
        let progress: Int
        let total: Int?
        let dateWatched: Date

        var progressPercentage: Double {
            guard let total = total, total > 0 else { return 0 }
            return Double(progress) / Double(total)
        }
    }

    struct EpisodeHistoryData {
        let playerTitle: String
        let episodeId: String
        let episodeNumber: Double
        let episodeTitle: String
        let sourceUrl: String
        let moduleId: String
        let progress: Int
        let total: Int?
        let watchedDuration: TimeInterval
        let date: Date
    }

    private init() {}

    func setProgress(data: EpisodeHistoryData) async {

        await CoreDataManager.shared.container.performBackgroundTask { context in
            _ = CoreDataManager.shared.createOrUpdatePlayerHistory(data, context: context)
            do {
                try context.save()

            } catch {
                LogManager.logger.error("PlayerHistoryManager.setProgress: \(error)")
            }
        }
        NotificationCenter.default.post(name: .playerHistoryUpdated, object: data)
    }

    func getEpisodeUrl(episodeId: String, moduleId: String) async -> String? {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let history = CoreDataManager.shared.getPlayerHistory(episodeId: episodeId, moduleId: moduleId, context: context)
            return history?.sourceUrl
        }
    }

    func getAllHistory() async -> [PlayerHistoryItem] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let objects = CoreDataManager.shared.getAllPlayerHistory(context: context)

            return objects.map { obj in
                PlayerHistoryItem(
                    id: "\(obj.moduleId ?? "")-\(obj.episodeId ?? "")",
                    playerTitle: obj.playerTitle ?? "",
                    episodeId: obj.episodeId ?? "",
                    episodeNumber: Double(obj.episodeNumber),
                    episodeTitle: obj.episodeTitle,
                    sourceUrl: obj.sourceUrl ?? "",
                    moduleId: obj.moduleId ?? "",
                    progress: Int(obj.progress),
                    total: Int(obj.total),
                    dateWatched: obj.dateWatched ?? Date()
                )
            }
        }
    }

    func removeHistory(episodeId: String, moduleId: String) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removePlayerHistory(episodeId: episodeId, moduleId: moduleId, context: context)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("PlayerHistoryManager.removeHistory: \(error)")
            }
        }
        NotificationCenter.default.post(name: .playerHistoryRemoved, object: ["episodeId": episodeId, "moduleId": moduleId])
    }

    func removeHistoryForContent(sourceUrl: String, moduleId: String) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removePlayerHistoryForContent(sourceUrl: sourceUrl, moduleId: moduleId, context: context)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("PlayerHistoryManager.removeHistoryForContent: \(error)")
            }
        }
        NotificationCenter.default.post(name: .playerHistoryRemoved, object: ["sourceUrl": sourceUrl, "moduleId": moduleId])
    }

    func clearHistory() async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.clearAllPlayerHistory(context: context)
            do {
                try context.save()
            } catch {
                LogManager.logger.error("PlayerHistoryManager.clearHistory: \(error)")
            }
        }
        NotificationCenter.default.post(name: .updateHistory, object: nil)
    }
}
