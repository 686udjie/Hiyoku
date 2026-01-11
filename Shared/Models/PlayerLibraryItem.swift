//
//  PlayerLibraryItem.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Foundation

struct PlayerLibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    var imageUrl: String
    var originalImageUrl: String?
    var sourceUrl: String
    let moduleId: UUID
    let moduleName: String
    let dateAdded: Date
    var hasCustomCover: Bool = false

    init(
        id: UUID = UUID(),
        title: String,
        imageUrl: String,
        sourceUrl: String,
        moduleId: UUID,
        moduleName: String,
        dateAdded: Date = Date(),
        hasCustomCover: Bool = false,
        originalImageUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.imageUrl = imageUrl
        self.originalImageUrl = originalImageUrl
        self.sourceUrl = sourceUrl
        self.moduleId = moduleId
        self.moduleName = moduleName
        self.dateAdded = dateAdded
        self.hasCustomCover = hasCustomCover
    }
}
