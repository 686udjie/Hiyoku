//
//  Modules.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Foundation

struct ModuleMetadata: Codable, Hashable {
    let sourceName: String
    let author: Author
    let iconUrl: String
    let version: String
    let language: String
    let baseUrl: String
    let streamType: String
    let quality: String
    let searchBaseUrl: String
    let scriptUrl: String
    let asyncJS: Bool?
    let streamAsyncJS: Bool?
    let softsub: Bool?
    let multiStream: Bool?
    let multiSubs: Bool?
    let type: String?
    let novel: Bool?

    struct Author: Codable, Hashable {
        let name: String
        let icon: String
    }
}

struct ScrapingModule: Codable, Identifiable, Hashable {
    let id: UUID
    let metadata: ModuleMetadata
    var updateMetadata: ModuleMetadata?
    let localPath: String
    let metadataUrl: String
    var isActive: Bool

    init(
        id: UUID = UUID(),
        metadata: ModuleMetadata,
        updateMetadata: ModuleMetadata? = nil,
        localPath: String,
        metadataUrl: String,
        isActive: Bool = false
    ) {
        self.id = id
        self.metadata = metadata
        self.updateMetadata = updateMetadata
        self.localPath = localPath
        self.metadataUrl = metadataUrl
        self.isActive = isActive
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ScrapingModule, rhs: ScrapingModule) -> Bool {
        lhs.id == rhs.id
    }

    var isNovelModule: Bool {
        metadata.streamType.lowercased() == "novels" ||
        metadata.type?.lowercased() == "novels" ||
        metadata.novel == true
    }
    var isPlayerModule: Bool {
        !isNovelModule
    }

    func toSourceInfo(withMetadata: ModuleMetadata? = nil) -> SourceInfo2 {
        let meta = withMetadata ?? metadata
        return SourceInfo2(
            sourceId: id.uuidString,
            iconUrl: URL(string: meta.iconUrl),
            name: meta.sourceName,
            languages: [meta.language],
            version: Int(meta.version.components(separatedBy: ".").first ?? "1") ?? 1,
            contentRating: .safe,
            externalInfo: withMetadata != nil ? toExternalSourceInfo(withMetadata: meta) : nil,
            isPlayerSource: true
        )
    }

    func toExternalSourceInfo(withMetadata: ModuleMetadata? = nil) -> ExternalSourceInfo {
        let meta = withMetadata ?? metadata
        return ExternalSourceInfo(
            id: id.uuidString,
            name: meta.sourceName,
            version: Int(meta.version.components(separatedBy: ".").first ?? "1") ?? 1,
            iconURL: meta.iconUrl,
            downloadURL: meta.scriptUrl,
            languages: [meta.language],
            contentRating: .safe,
            altNames: [],
            baseURL: meta.baseUrl,
            minAppVersion: nil,
            maxAppVersion: nil,
            lang: nil,
            nsfw: nil,
            file: nil,
            icon: nil
        )
    }
}
