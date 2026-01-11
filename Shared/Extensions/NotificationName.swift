//
//  NotificationName.swift
//  Aidoku
//
//  Created by Skitty on 4/29/25.
//

import Foundation

extension Notification.Name {
    static let orientationDidChange = Self("orientationDidChange")

    static let updateSourceList = Self("updateSourceList")
    static let updateSourceLists = Self("updateSourceLists")

    // general
    static let incognitoMode = Self("General.incognitoMode")

    // library
    static let updateLibrary = Self("updateLibrary")
    static let addToLibrary = Self("addToLibrary")
    static let removeFromLibrary = Self("removeFromLibrary")
    static let migratedManga = Self("migratedManga")
    static let updateMangaDetails = Self("updateMangaDetails")
    static let updateCategories = Self("updateCategories")
    static let updateManga = Self("updateManga")
    static let updateMangaCategories = Self("updateMangaCategories")
    static let updateLibraryLock = Self("updateLibraryLock")
    static let pinTitles = Self("Library.pinTitles")

    // history
    static let updateHistory = Self("updateHistory")
    static let historyAdded = Self("historyAdded")
    static let historyRemoved = Self("historyRemoved")
    static let historySet = Self("historySet")

    // player history
    static let playerHistoryAdded = Self("playerHistoryAdded")
    static let playerHistoryUpdated = Self("playerHistoryUpdated")
    static let playerHistoryRemoved = Self("playerHistoryRemoved")

    // trackers
    static let updateTrackers = Self("updateTrackers")
    static let trackItemAdded = Self("trackItemAdded")
    static let syncTrackItem = Self("syncTrackItem")

    // downloads
    static let downloadProgressed = Self("downloadProgressed")
    static let downloadFinished = Self("downloadFinished")
    static let downloadRemoved = Self("downloadRemoved")
    static let downloadCancelled = Self("downloadCancelled")
    static let downloadsRemoved = Self("downloadsRemoved")
    static let downloadsCancelled = Self("downloadsCancelled")
    static let downloadsQueued = Self("downloadsQueued")
    static let downloadsPaused = Self("downloadsPaused")
    static let downloadsResumed = Self("downloadsResumed")

    // browse
    static let filterExternalSources = Self("filterExternalSources")

    // reader
    static let readerShowingBars = Self("readerShowingBars")
    static let readerHidingBars = Self("readerHidingBars")
    static let readerReadingMode = Self("Reader.readingMode")
    static let readerTapZones = Self("Reader.tapZones")
    static let readerOrientation = Self("Reader.orientation")

    // settings
    static let portraitRowsSetting = Self("General.portraitRows")
    static let landscapeRowsSetting = Self("General.landscapeRows")
    static let historyLockSetting = Self("History.lockHistory")

    // modules
    static let modulesSyncDidComplete = Self("modulesSyncDidComplete")
    static let moduleAdded = Self("moduleAdded")
    static let moduleRemoved = Self("moduleRemoved")
    static let moduleStateChanged = Self("moduleStateChanged")

    // player bookmarks
    static let playerBookmarkAdded = Self("playerBookmarkAdded")
    static let playerBookmarkRemoved = Self("playerBookmarkRemoved")

    // player library
    static let updatePlayerLibrary = Self("updatePlayerLibrary")
    static let addToPlayerLibrary = Self("addToPlayerLibrary")
    static let removeFromPlayerLibrary = Self("removeFromPlayerLibrary")
}
