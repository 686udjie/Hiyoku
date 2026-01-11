//
//  PlayerEpisode.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Foundation

struct PlayerEpisode: Identifiable, Codable, Hashable {
    let id: UUID
    let number: Int
    let title: String
    let url: String
    let dateUploaded: Date?
    let scanlator: String?
    let language: String

    init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        url: String,
        dateUploaded: Date? = nil,
        scanlator: String? = nil,
        language: String = "en"
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.dateUploaded = dateUploaded
        self.scanlator = scanlator
        self.language = language
    }
}
