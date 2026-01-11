//
//  CoreDataManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import CoreData

final class CoreDataManager {

    static let shared = CoreDataManager()

    init() {}

    private var _container: NSPersistentContainer?
    var container: NSPersistentContainer {
        if let container = _container {
            return container
        }

        let newContainer = createContainer()
        _container = newContainer
        return newContainer
    }

    private func createContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Aidoku")

        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let cloudDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Aidoku.sqlite"))
        cloudDescription.configuration = "Cloud"
        cloudDescription.shouldMigrateStoreAutomatically = true
        cloudDescription.shouldInferMappingModelAutomatically = true

        let localDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Local.sqlite"))
        localDescription.configuration = "Local"
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true

        container.persistentStoreDescriptions = [
            cloudDescription,
            localDescription
        ]

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                LogManager.logger.error("Error loading persistent stores \(error), \(error.userInfo)")
                // Handle read-only database error by recreating store
                if error.code == 134110 || (error.domain == NSCocoaErrorDomain && error.code == 134110) {
                    LogManager.logger.error("Attempting to recreate read-only database store")
                    // Get store URL
                    if let storeURL = storeDescription.url {
                        do {
                            // Remove existing store
                            try FileManager.default.removeItem(at: storeURL)
                            LogManager.logger.info("Removed read-only database store")
                            // Reset container to force recreation on next access
                            DispatchQueue.main.async {
                                self._container = nil
                            }
                        } catch {
                            LogManager.logger.error("Failed to remove corrupted store: \(error)")
                        }
                    }
                } else if error.domain == NSCocoaErrorDomain && (error.code == 134109 || error.code == 134110) {
                    // Handle migration errors
                    LogManager.logger.error("Core Data migration failed, attempting to recreate database")
                    if let storeURL = storeDescription.url {
                        do {
                            try FileManager.default.removeItem(at: storeURL)
                            LogManager.logger.info("Removed corrupted database, will recreate on next launch")
                            // Reset container to force recreation on next access
                            DispatchQueue.main.async {
                                self._container = nil
                            }
                        } catch {
                            LogManager.logger.error("Failed to remove corrupted database: \(error)")
                        }
                    }
                }
            }
        }

        return container
    }

    lazy var queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var context: NSManagedObjectContext {
        container.viewContext
    }

    func save() {
        do {
            try context.save()
        } catch {
            LogManager.logger.error("CoreDataManager.save: \(error.localizedDescription)")
        }
    }

    func remove(_ objectID: NSManagedObjectID) {
        container.performBackgroundTask { context in
            let object = context.object(with: objectID)
            context.delete(object)
            try? context.save()
        }
    }

    /// Clear all objects from fetch request.
    func clear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext? = nil) {
        let context = context ?? self.context
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
        do {
            _ = try context.execute(deleteRequest)
        } catch {
            LogManager.logger.error("CoreDataManager.clear: \(error.localizedDescription)")
        }
    }

    func migrateChapterHistory(progress: (@Sendable (Float) -> Void)? = nil) async {
        await container.performBackgroundTask { context in
            let request = HistoryObject.fetchRequest()
            let historyObjects = (try? context.fetch(request)) ?? []
            let total = Float(historyObjects.count)
            var i: Float = 0
            var count = 0
            for historyObject in historyObjects {
                progress?(i / total)
                i += 1
                guard
                    historyObject.chapter == nil,
                    let chapterObject = self.getChapter(
                        sourceId: historyObject.sourceId,
                        mangaId: historyObject.mangaId,
                        chapterId: historyObject.chapterId,
                        context: context
                    )
                else { continue }
                historyObject.chapter = chapterObject
                count += 1
            }
            try? context.save()
        }
    }
}
