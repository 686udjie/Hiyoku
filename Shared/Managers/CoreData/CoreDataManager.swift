//
//  CoreDataManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import CoreData

final class CoreDataManager {

    static let containerID = Bundle.main
        .infoDictionary?["ICLOUD_CONTAINER_ID"] as? String ?? "iCloud.\(Bundle.main.bundleIdentifier!)"

    static let shared = CoreDataManager()

    private var observers: [NSObjectProtocol] = []
    private var lastHistoryToken: NSPersistentHistoryToken?

    private var shouldUseiCloud: Bool {
        UserDefaults.standard.bool(forKey: "General.icloudSync") && FileManager.default.ubiquityIdentityToken != nil
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: nil
        ) { [weak self] _ in
            self?.storeRemoteChange()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("General.icloudSync"), object: nil, queue: nil
        ) { [weak self] _ in
            guard
                let self,
                let cloudDescription = self.container.persistentStoreDescriptions.first
            else { return }
            if self.shouldUseiCloud {
                cloudDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CoreDataManager.containerID)
            } else {
                cloudDescription.cloudKitContainerOptions = nil
            }
        })
    }

    lazy var container: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "Aidoku")

        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        let cloudDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Aidoku.sqlite"))
        cloudDescription.configuration = "Cloud"
        cloudDescription.shouldMigrateStoreAutomatically = true
        cloudDescription.shouldInferMappingModelAutomatically = true

        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let localDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Local.sqlite"))
        localDescription.configuration = "Local"
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true

        localDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        localDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if shouldUseiCloud {
            cloudDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: CoreDataManager.containerID)
        } else {
            cloudDescription.cloudKitContainerOptions = nil
        }

        container.persistentStoreDescriptions = [
            cloudDescription,
            localDescription
        ]

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                LogManager.logger.error("Error loading persistent stores \(error), \(error.userInfo)")
            }
        }

        return container
    }()

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

extension CoreDataManager {

    func storeRemoteChange() {
        queue.addOperation {
            let context = self.container.newBackgroundContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.performAndWait {
                let historyFetchRequest = NSPersistentHistoryTransaction.fetchRequest!
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastHistoryToken)
                request.fetchRequest = historyFetchRequest

                let result = (try? context.execute(request)) as? NSPersistentHistoryResult
                guard
                    let transactions = result?.result as? [NSPersistentHistoryTransaction],
                    !transactions.isEmpty
                else { return }

                var newObjectIds = [NSManagedObjectID]()
                let entityNames = [
                    CategoryObject.entity().name,
                    ChapterObject.entity().name,
                    HistoryObject.entity().name,
                    LibraryMangaObject.entity().name,
                    MangaObject.entity().name,
                    TrackObject.entity().name
                ]

                for
                    transaction in transactions
                    where transaction.changes != nil && transaction.author == "NSCloudKitMirroringDelegate.import"
                {
                    for
                        change in transaction.changes!
                        where entityNames.contains(change.changedObjectID.entity.name) && change.changeType == .insert
                    {
                        newObjectIds.append(change.changedObjectID)
                    }
                }

                if !newObjectIds.isEmpty {
                    self.deduplicate(objectIds: newObjectIds)
                }

                self.lastHistoryToken = transactions.last!.token
            }
        }
    }

    func deduplicate(objectIds: [NSManagedObjectID]) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.performAndWait {
            for objectId in objectIds {
                deduplicate(objectId: objectId, context: context)
            }
            do {
                try context.save()
            } catch {
                LogManager.logger.error("deduplicate: \(error.localizedDescription)")
            }
        }
    }

    private func createDeduplicationRequest(for object: NSManagedObject) -> NSFetchRequest<NSFetchRequestResult>? {
        guard let entityName = object.entity.name else { return nil }
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let predicate: NSPredicate? = {
            switch object {
            case let manga as MangaObject:
                return NSPredicate(format: "sourceId == %@ AND id == %@", manga.sourceId, manga.id)
            case let category as CategoryObject:
                return NSPredicate(format: "title == %@", category.title ?? "")
            case let chapter as ChapterObject:
                return NSPredicate(
                    format: "sourceId == %@ AND mangaId == %@ AND id == %@",
                    chapter.sourceId, chapter.mangaId, chapter.id
                )
            case let history as HistoryObject:
                return NSPredicate(
                    format: "sourceId == %@ AND mangaId == %@ AND chapterId == %@",
                    history.sourceId, history.mangaId, history.chapterId
                )
            case let libraryManga as LibraryMangaObject:
                let sourceId = libraryManga.manga?.sourceId ?? ""
                let id = libraryManga.manga?.id ?? ""
                return NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", sourceId, id)
            case let track as TrackObject:
                return NSPredicate(format: "id == %@ AND trackerId == %@", track.id ?? "", track.trackerId ?? "")
            default:
                return nil
            }
        }()
        guard let predicate = predicate else { return nil }
        request.predicate = predicate
        return request
    }

    func deduplicate(objectId: NSManagedObjectID, context: NSManagedObjectContext) {
        let object = context.object(with: objectId)
        guard let request = createDeduplicationRequest(for: object),
              (try? context.count(for: request)) ?? 0 > 1,
              let objects = try? context.fetch(request) else { return }
        // also stupid but im dumb, this will be fine until it breaks
        objects.dropFirst().forEach { duplicate in
            if let managedObject = duplicate as? NSManagedObject {
                context.delete(managedObject)
            }
        }
    }
}
